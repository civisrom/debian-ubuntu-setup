#!/usr/bin/env bash
# VeraCrypt payload for /opt. Passwords are passed only through stdin.
set +x
set -euo pipefail
umask 077

VC_VERSION=1.26.29
VC_FPR=5069A233D55A0EEB174A5FC3821ACD02680D16DE
VAULT_BYTES=104857600
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WORK=''; MOUNT=''; PASSWORD_FILE=''; CREATED=''

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'EOF'
Использование (от root):
  opt-vault.sh create ИСТОЧНИК КОНТЕЙНЕР --password-file ФАЙЛ
  opt-vault.sh restore КОНТЕЙНЕР [--password-file ФАЙЛ]
  opt-vault.sh check КОНТЕЙНЕР [--password-file ФАЙЛ]

create: новый контейнер 100 МиБ; существующий файл не заменяется.
restore: восстановление в /opt, копия затронутых файлов в /var/backups/system-setup.
check: открытие только для чтения и проверка внутренней контрольной суммы.
Без --password-file пароль считывается VeraCrypt из stdin (или с терминала).
Файл пароля должен быть обычным файлом 600/400 вне репозитория и источника.
EOF
}

cleanup() {
    local rc=$?
    trap - EXIT INT TERM HUP
    if [[ -n $MOUNT ]]; then
        if veracrypt --text --non-interactive --list "$MOUNT" >/dev/null 2>&1; then
            if ! veracrypt --text --non-interactive --dismount "$MOUNT" >/dev/null 2>&1; then
                printf 'ERROR: Контейнер не закрыт; сохранён каталог %s. Выполните veracrypt -t -d %q\n' "$WORK" "$MOUNT" >&2
                exit 1
            fi
        elif mountpoint -q "$WORK/mount"; then
            printf 'ERROR: Контейнер не закрыт; сохранён каталог %s. Выполните veracrypt -t -d %q\n' "$WORK" "$MOUNT" >&2
            exit 1
        fi
        MOUNT=''
    fi
    [[ -z $WORK ]] || rm -rf -- "$WORK"
    if ((rc != 0)) && [[ -n $CREATED ]]; then
        printf 'ERROR: Создание не завершено; неполный контейнер: %s\n' "$CREATED" >&2
    fi
    exit "$rc"
}

download() {
    curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 20 --max-time 600 --retry 2 "$1" -o "$2"
}

install_veracrypt() {
    command -v veracrypt >/dev/null 2>&1 && return 0
    local platform arch package base status signer url got=0
    # shellcheck disable=SC1091
    . /etc/os-release
    arch=$(dpkg --print-architecture)
    case "$ID:$VERSION_ID:$arch" in
        debian:12:amd64) platform=Debian-12 ;;
        debian:13:amd64|debian:13:arm64) platform=Debian-13 ;;
        ubuntu:24.04:amd64|ubuntu:24.04:arm64) platform=Ubuntu-24.04 ;;
        ubuntu:26.04:amd64|ubuntu:26.04:arm64) platform=Ubuntu-26.04 ;;
        *) die "Нет проверенного пакета VeraCrypt для $ID $VERSION_ID $arch; установите VeraCrypt вручную" ;;
    esac
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl gnupg python3 < /dev/null
    package="veracrypt-console-${VC_VERSION}-${platform}-${arch}.deb"
    base="https://github.com/veracrypt/VeraCrypt/releases/download/VeraCrypt_${VC_VERSION}"
    download "$base/$package" "$WORK/$package"
    download "$base/$package.sig" "$WORK/$package.sig"
    for url in https://amcrypto.jp/VeraCrypt/VeraCrypt_PGP_public_key.asc https://veracrypt.io/VeraCrypt_PGP_public_key.asc; do
        if download "$url" "$WORK/veracrypt.asc"; then got=1; break; fi
    done
    ((got)) || die 'Не удалось получить публичный ключ VeraCrypt'
    mkdir -m 700 "$WORK/gnupg"
    gpg --homedir "$WORK/gnupg" --batch --quiet --import "$WORK/veracrypt.asc"
    status=$(gpg --homedir "$WORK/gnupg" --batch --status-fd 1 --verify "$WORK/$package.sig" "$WORK/$package" 2>/dev/null) \
        || die 'Подпись пакета VeraCrypt неверна'
    signer=$(awk '/^\[GNUPG:\] VALIDSIG / {print $NF}' <<< "$status")
    [[ $signer == "$VC_FPR" ]] || die 'Подпись сделана неожиданным ключом'
    DEBIAN_FRONTEND=noninteractive apt-get -o APT::Sandbox::User=root install -y --no-install-recommends "$WORK/$package" < /dev/null
    command -v veracrypt >/dev/null || die 'VeraCrypt не установлен'
}

with_password() {
    if [[ -n $PASSWORD_FILE ]]; then
        veracrypt --text --non-interactive --stdin "$@" < "$PASSWORD_FILE"
    elif [[ -t 0 ]]; then
        veracrypt --text "$@"
    else
        veracrypt --text --non-interactive --stdin "$@"
    fi
}

open_vault() {
    local volume=$1 access=$2 options=nokernelcrypto
    [[ $access != ro ]] || options=ro,nokernelcrypto
    mkdir -m 700 "$WORK/mount"
    # Register by volume path BEFORE mounting: cleanup also handles partial mounts.
    MOUNT=$volume
    if ! with_password --mount "$volume" "$WORK/mount" --pim=0 --keyfiles='' \
            --protect-hidden=no --mount-options="$options" --fs-options=umask=077; then
        die 'Контейнер не открыт; проверьте пароль и доступность FUSE, FAT и loop'
    fi
    MOUNT=$volume
    mountpoint -q "$WORK/mount" || die 'Файловая система контейнера не смонтирована'
}

main() {
    [[ ${1:-} != --help && ${1:-} != -h && $# != 0 ]] || { usage; return; }
    local action=$1 source='' volume
    shift
    case $action in
        create) (($# >= 2)) || die 'Нужны источник и контейнер'; source=$1; volume=$2; shift 2 ;;
        restore|check) (($# >= 1)) || die 'Нужен путь контейнера'; volume=$1; shift ;;
        *) die 'Неизвестное действие' ;;
    esac
    if (($#)); then
        [[ $# == 2 && $1 == --password-file ]] || die 'Неизвестные параметры'
        PASSWORD_FILE=$2
        [[ -f $PASSWORD_FILE && ! -L $PASSWORD_FILE && -s $PASSWORD_FILE ]] || die 'Нет непустого обычного файла пароля'
        case $(stat -c %a "$PASSWORD_FILE") in 600|400) ;; *) die 'Файл пароля должен иметь права 600 или 400' ;; esac
    fi
    ((EUID == 0)) || die 'Для монтирования контейнера запустите через sudo'
    [[ -f $SCRIPT_DIR/opt-payload.py ]] || die 'Рядом должен находиться opt-payload.py'
    if [[ $action == create ]]; then
        [[ -n $PASSWORD_FILE ]] || die 'Для создания укажите --password-file'
        [[ ! -e $volume && ! -L $volume ]] || die 'Контейнер уже существует'
        [[ -d $source && ! -L $source ]] || die 'Неверный каталог источника'
        source=$(realpath -- "$source")
        case $(realpath -- "$PASSWORD_FILE") in "$source"/*) die 'Пароль не должен попадать в источник' ;; esac
    else
        [[ -f $volume && ! -L $volume ]] || die 'Контейнер не найден'
    fi
    volume=$(realpath -m -- "$volume")
    if [[ $action == create ]]; then
        case $volume in "$source"/*) die 'Контейнер должен находиться вне источника' ;; esac
    fi
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/opt-vault.XXXXXXXX")
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    install_veracrypt
    command -v python3 >/dev/null || die 'Требуется python3'
    case $action in
        create)
            mkdir -m 700 "$WORK/data"
            python3 "$SCRIPT_DIR/opt-payload.py" pack "$source" "$WORK/data"
            [[ $(stat -c %s "$WORK/data/payload.tar.gz") -lt $((VAULT_BYTES - 2097152)) ]] || die 'Данные не помещаются в 100 МиБ'
            CREATED=$volume
            with_password --create "$volume" --size="$VAULT_BYTES" --volume-type=normal \
                --encryption=AES --hash=SHA-512 --filesystem=FAT --pim=0 --keyfiles='' --random-source=/dev/urandom
            chmod 600 "$volume"
            open_vault "$volume" nokernelcrypto
            cp -- "$WORK/data/payload.tar.gz" "$WORK/data/payload.sha256" "$WORK/mount/"
            sync -f "$WORK/mount/payload.tar.gz"
            python3 "$SCRIPT_DIR/opt-payload.py" verify "$WORK/mount"
            veracrypt --text --non-interactive --dismount "$MOUNT"
            MOUNT=''
            rmdir "$WORK/mount"
            open_vault "$volume" ro
            python3 "$SCRIPT_DIR/opt-payload.py" verify "$WORK/mount"
            if [[ ${SUDO_UID:-} =~ ^[0-9]+$ && ${SUDO_GID:-} =~ ^[0-9]+$ ]]; then
                chown "$SUDO_UID:$SUDO_GID" "$volume"
            fi
            CREATED=''
            printf 'Контейнер создан и повторно открыт: %s (%s байт)\n' "$volume" "$(stat -c %s "$volume")"
            ;;
        restore|check)
            open_vault "$volume" ro
            python3 "$SCRIPT_DIR/opt-payload.py" verify "$WORK/mount"
            if [[ $action == restore ]]; then
                python3 "$SCRIPT_DIR/opt-payload.py" restore "$WORK/mount" /opt /var/backups/system-setup
            fi
            printf 'Контейнер проверен: %s\n' "$volume"
            ;;
    esac
}

main "$@"
