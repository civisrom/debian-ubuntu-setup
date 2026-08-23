#!/bin/bash
# ============================================================================
# install-nft-docker-watch.sh
#
# Устанавливает systemd-сервис для применения nftables-правил после старта
# Docker и автоматического восстановления при каждом рестарте Docker.
#
# Что создаётся:
#   1. nftables-after-docker.service — применяет /etc/nftables.conf
#   2. nft-apply.sh — обёртка: валидация → бэкап → применение → проверка
#   3. Drop-in docker.service.d/nftables-reload.conf — триггер при рестарте Docker
#
# Использование:
#   sudo ./install-nft-docker-watch.sh            # интерактивное меню
#   sudo ./install-nft-docker-watch.sh install     # установка
#   sudo ./install-nft-docker-watch.sh reinstall   # переустановка
#   sudo ./install-nft-docker-watch.sh uninstall   # удаление
#   sudo ./install-nft-docker-watch.sh status      # статус + логи
#   sudo ./install-nft-docker-watch.sh apply       # применить правила вручную
# ============================================================================

set -euo pipefail

# ─── Константы ────────────────────────────────────────────────────────────
readonly NFT_CONF="/etc/nftables.conf"
readonly NFT_APPLY_SCRIPT="/usr/local/sbin/nft-apply.sh"
readonly NFT_BACKUP_DIR="/var/backups/nftables"
readonly NFT_APPLY_SHA256="794165f7d0d93c2aacc457e8a9d7d8d4f9bed12370fe4705fdddcb7a40a4f9dc"
readonly NFT_APPLY_URL="https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/config/nft-apply.sh"
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALLER_DIR

readonly SERVICE_NAME="nftables-after-docker.service"
readonly SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

readonly DROP_IN_DIR="/etc/systemd/system/docker.service.d"
readonly DROP_IN_PATH="${DROP_IN_DIR}/nftables-reload.conf"

# Kept in sync with the generated nft-apply.sh defaults below.
# shellcheck disable=SC2034
readonly DOCKER_WAIT_TIMEOUT=60   # секунд ожидания готовности Docker
# shellcheck disable=SC2034
readonly DOCKER_SETTLE_DELAY=2    # секунд после готовности Docker (создание br-*)

# ─── Цвета ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── Функции логирования ──────────────────────────────────────────────────

log_info()  { echo -e "${BLUE}[+]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*" >&2; }
log_error() { echo -e "${RED}[-]${NC} $*" >&2; }

print_header() {
    echo -e "${CYAN}${BOLD}$*${NC}"
}

# ─── Проверки ─────────────────────────────────────────────────────────────

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Требуется root. Запустите: sudo $0"
        exit 1
    fi
}

check_dependencies() {
    local missing=()
    for cmd in nft systemctl docker flock sha256sum; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Не найдены: ${missing[*]}"
        exit 1
    fi
}

check_nft_conf() {
    if [[ ! -f "$NFT_CONF" ]]; then
        log_error "Файл $NFT_CONF не найден"
        exit 1
    fi
}

# ─── Удаление ─────────────────────────────────────────────────────────────

do_uninstall() {
    log_info "Удаление nftables-after-docker..."

    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"
        log_info "Сервис остановлен"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME"
        log_info "Автозапуск отключён"
    fi

    local removed=0
    for f in "$SERVICE_PATH" "$DROP_IN_PATH" "$NFT_APPLY_SCRIPT"; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            log_info "Удалён: $f"
            ((++removed))
        fi
    done

    # Удалить drop-in каталог, если пуст
    if [[ -d "$DROP_IN_DIR" ]] && [[ -z "$(ls -A "$DROP_IN_DIR" 2>/dev/null)" ]]; then
        rmdir "$DROP_IN_DIR"
        log_info "Удалён пустой каталог: $DROP_IN_DIR"
    fi

    systemctl daemon-reload
    log_ok "Удаление завершено (бэкапы в $NFT_BACKUP_DIR сохранены)"
}

# ─── Тихая остановка существующего сервиса ────────────────────────────────

stop_existing() {
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        log_info "Существующий сервис остановлен"
    fi
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    fi
}

# ─── Установка ────────────────────────────────────────────────────────────

create_apply_script() {
    log_info "Создаём скрипт применения: $NFT_APPLY_SCRIPT"
    local source_path="${INSTALLER_DIR}/config/nft-apply.sh"
    local temp_path=""

    if [[ ! -f "$source_path" ]]; then
        temp_path=$(mktemp "${TMPDIR:-/tmp}/nft-apply.XXXXXX")
        if command -v curl >/dev/null 2>&1; then
            if ! curl --ipv4 -fsSL --connect-timeout 15 --max-time 120 --retry 3 \
                "$NFT_APPLY_URL" -o "$temp_path"; then
                rm -f -- "$temp_path"
                return 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if ! wget -4 -q --timeout=30 --tries=3 "$NFT_APPLY_URL" -O "$temp_path"; then
                rm -f -- "$temp_path"
                return 1
            fi
        else
            log_error "Нужен curl или wget для загрузки $NFT_APPLY_URL"
            rm -f -- "$temp_path"
            return 1
        fi
        source_path="$temp_path"
    fi

    if [[ "$(sha256sum "$source_path" | awk '{print $1}')" != "$NFT_APPLY_SHA256" ]]; then
        log_error "SHA256 не совпадает для nft-apply.sh; установка отменена"
        [[ -n "$temp_path" ]] && rm -f -- "$temp_path"
        return 1
    fi
    bash -n "$source_path"
    install -m 0755 -o root -g root "$source_path" "$NFT_APPLY_SCRIPT"
    [[ -n "$temp_path" ]] && rm -f -- "$temp_path"
}

create_service() {
    log_info "Создаём systemd unit: $SERVICE_PATH"

    cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=Apply nftables rules after Docker
# Запускаемся после Docker и сети. Не Requires — если Docker упал,
# мы не хотим чтобы systemd пытался тянуть его как зависимость.
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes

# nft-apply.sh: валидация → бэкап → wait docker → применение → верификация
ExecStart=${NFT_APPLY_SCRIPT}

# Ручной перезапуск правил: systemctl restart nftables-after-docker
ExecReload=${NFT_APPLY_SCRIPT}

# Таймаут достаточный для ожидания Docker + применения правил
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF
}

create_docker_dropin() {
    log_info "Создаём drop-in для docker.service: $DROP_IN_PATH"

    mkdir -p "$DROP_IN_DIR"

    # ExecStartPost: выполняется после каждого (ре)старта Docker.
    # systemctl restart — сбрасывает RemainAfterExit и запускает ExecStart заново.
    # --no-block — не блокирует запуск Docker если nft-apply тормозит.
    cat <<EOF > "$DROP_IN_PATH"
[Service]
ExecStartPost=/bin/systemctl restart --no-block ${SERVICE_NAME}
EOF
}

do_install() {
    check_dependencies
    check_nft_conf

    # Если сервис уже установлен — предупреждаем
    if [[ -f "$SERVICE_PATH" ]]; then
        log_warn "Сервис уже установлен. Обновляю файлы..."
        stop_existing
    fi

    # Создаём каталог бэкапов
    install -d -m 0700 -o root -g root "$NFT_BACKUP_DIR"

    create_apply_script
    create_service
    create_docker_dropin

    log_info "Перечитываем конфигурацию systemd"
    systemctl daemon-reload

    log_info "Включаем автозапуск сервиса"
    systemctl enable "$SERVICE_NAME"

    log_info "Запускаем сервис"
    if systemctl start "$SERVICE_NAME"; then
        log_ok "Сервис запущен"
    else
        log_error "Сервис не запустился. Проверьте: journalctl -u $SERVICE_NAME"
        return 1
    fi

    echo ""
    systemctl status "$SERVICE_NAME" --no-pager || true

    echo ""
    echo "========================================="
    log_ok "Установка завершена"
    echo "========================================="
    echo ""
    echo "Что установлено:"
    echo "  Сервис:   $SERVICE_PATH"
    echo "  Скрипт:   $NFT_APPLY_SCRIPT"
    echo "  Drop-in:  $DROP_IN_PATH"
    echo "  Бэкапы:   $NFT_BACKUP_DIR"
    echo ""
    echo "Команды:"
    echo "  journalctl -u $SERVICE_NAME       # логи"
    echo "  systemctl restart $SERVICE_NAME    # применить правила вручную"
    echo "  sudo $0 uninstall                  # удаление"
    echo ""
    echo "При каждом (ре)старте Docker правила nftables"
    echo "будут автоматически восстановлены."
}

do_reinstall() {
    log_info "Переустановка nftables-after-docker..."
    stop_existing
    do_install
}

do_status() {
    echo ""
    print_header "═══════════════════════════════════════════════"
    print_header "   nftables-after-docker — Статус"
    print_header "═══════════════════════════════════════════════"
    echo ""

    systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || log_warn "Сервис не найден"

    echo ""
    print_header "── Последние логи ──"
    echo ""
    journalctl -u "$SERVICE_NAME" -n 30 --no-pager 2>/dev/null || log_warn "Логи недоступны"

    echo ""
    print_header "── Файлы ──"
    for f in "$SERVICE_PATH" "$NFT_APPLY_SCRIPT" "$DROP_IN_PATH"; do
        if [[ -f "$f" ]]; then
            echo -e "  ${GREEN}✓${NC} $f"
        else
            echo -e "  ${RED}✗${NC} $f (отсутствует)"
        fi
    done

    echo ""
    print_header "── Бэкапы ──"
    if [[ -d "$NFT_BACKUP_DIR" ]]; then
        local count
        count=$(find "$NFT_BACKUP_DIR" -name "ruleset-*.nft" 2>/dev/null | wc -l)
        echo "  Каталог: $NFT_BACKUP_DIR ($count бэкапов)"
        # shellcheck disable=SC2012
        ls -1t "${NFT_BACKUP_DIR}"/ruleset-*.nft 2>/dev/null | head -5 | while read -r f; do
            echo "    $(basename "$f")"
        done
    else
        echo "  Каталог бэкапов не найден"
    fi
    echo ""
}

do_apply() {
    log_info "Ручное применение правил..."
    if [[ -x "$NFT_APPLY_SCRIPT" ]]; then
        exec "$NFT_APPLY_SCRIPT"
    else
        log_error "Скрипт $NFT_APPLY_SCRIPT не найден. Сначала выполните установку."
        exit 1
    fi
}

# ─── Интерактивное меню ───────────────────────────────────────────────────

show_menu() {
    echo ""
    print_header "═══════════════════════════════════════════════"
    print_header "   nftables-after-docker — Управление"
    print_header "═══════════════════════════════════════════════"
    echo ""
    echo "  Systemd-сервис для применения nftables-правил"
    echo "  после старта/рестарта Docker"
    echo ""
    print_header "── Выберите действие ──"
    echo ""
    echo "  1) Установка        — установить сервис, скрипт и drop-in"
    echo "  2) Переустановка    — остановить, обновить, запустить заново"
    echo "  3) Удаление         — полное удаление сервиса и файлов"
    echo "  4) Статус + логи    — состояние сервиса, логи, файлы, бэкапы"
    echo "  5) Применить правила— запустить nft-apply.sh вручную"
    echo ""
    echo "  0) Выход"
    echo ""

    read -p "Выберите [0-5] (по умолчанию: 0): " choice
    choice=${choice:-0}

    case "$choice" in
        1)
            do_install
            ;;
        2)
            do_reinstall
            ;;
        3)
            echo ""
            read -p "Вы уверены? Это удалит сервис и все файлы (y/N): " confirm
            confirm=${confirm:-n}
            if [[ "$confirm" = "y" || "$confirm" = "Y" ]]; then
                do_uninstall
            else
                log_info "Удаление отменено"
            fi
            ;;
        4)
            do_status
            ;;
        5)
            do_apply
            ;;
        0)
            log_info "Выход"
            exit 0
            ;;
        *)
            log_error "Неверный выбор: $choice"
            exit 1
            ;;
    esac
}

# ─── Точка входа ──────────────────────────────────────────────────────────

check_root

case "${1:-menu}" in
    install)
        do_install
        ;;
    reinstall|upgrade|update)
        do_reinstall
        ;;
    uninstall|remove|delete)
        do_uninstall
        ;;
    status)
        do_status
        ;;
    apply)
        do_apply
        ;;
    menu|"")
        show_menu
        ;;
    -h|--help|help)
        echo "Использование: $0 [install|reinstall|uninstall|status|apply|menu]"
        echo ""
        echo "  install    — установка сервиса"
        echo "  reinstall  — переустановка: остановить, обновить, запустить"
        echo "  uninstall  — полное удаление"
        echo "  status     — статус сервиса, логи, файлы, бэкапы"
        echo "  apply      — применить правила вручную (без systemd)"
        echo "  menu       — интерактивное меню (по умолчанию)"
        exit 0
        ;;
    *)
        log_error "Неизвестная команда: $1"
        echo "Использование: $0 [install|reinstall|uninstall|status|apply|menu]"
        exit 1
        ;;
esac
