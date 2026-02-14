#!/bin/bash

#############################################
# System Setup Script for Debian and Ubuntu
# Author: Enhanced Version v2.0
# Description: Initial package installation and system configuration
# Supported: Debian 12, 13 | Ubuntu 24.04, 25.04
#############################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Script version
SCRIPT_VERSION="2.0"

# Default language
SCRIPT_LANG="en"

# Localization system
declare -A TR

# Translation function for inline use (read -p prompts, echo, etc.)
t() {
    local key="$1"
    shift
    local translated="${TR[$key]:-$key}"
    if [ $# -gt 0 ]; then
        printf "$translated" "$@"
    else
        printf "%s" "$translated"
    fi
}

# Function to print colored messages (with auto-translation)
print_message() {
    local key="$1"
    shift
    local msg="${TR[$key]:-$key}"
    if [ $# -gt 0 ]; then
        msg=$(printf "$msg" "$@")
    fi
    echo -e "${GREEN}[INFO]${NC} $msg"
}

print_error() {
    local key="$1"
    shift
    local msg="${TR[$key]:-$key}"
    if [ $# -gt 0 ]; then
        msg=$(printf "$msg" "$@")
    fi
    echo -e "${RED}[ERROR]${NC} $msg"
}

print_warning() {
    local key="$1"
    shift
    local msg="${TR[$key]:-$key}"
    if [ $# -gt 0 ]; then
        msg=$(printf "$msg" "$@")
    fi
    echo -e "${YELLOW}[WARNING]${NC} $msg"
}

print_header() {
    local key="$1"
    shift
    local msg="${TR[$key]:-$key}"
    if [ $# -gt 0 ]; then
        msg=$(printf "$msg" "$@")
    fi
    echo -e "${BLUE}$msg${NC}"
}

print_success() {
    local key="$1"
    shift
    local msg="${TR[$key]:-$key}"
    if [ $# -gt 0 ]; then
        msg=$(printf "$msg" "$@")
    fi
    echo -e "${GREEN}[SUCCESS]${NC} $msg"
}

# Helper function to check if variable is yes
is_yes() {
    [ "$1" = "y" ] || [ "$1" = "Y" ]
}

# Load Russian translations
load_translations_ru() {
    # === Root check and system detection ===
    TR["This script must be run as root"]="Этот скрипт должен быть запущен от имени root"
    TR["Running in non-interactive mode with default settings"]="Запуск в неинтерактивном режиме с настройками по умолчанию"
    TR["Enhanced Configuration Tool"]="Расширенный инструмент настройки"
    TR["Cannot detect OS or OS is not supported"]="Невозможно определить ОС или ОС не поддерживается"
    TR["Please select the operating system:"]="Пожалуйста, выберите операционную систему:"
    TR["Invalid choice. Exiting."]="Неверный выбор. Выход."
    TR["Cannot detect OS and running in non-interactive mode"]="Невозможно определить ОС в неинтерактивном режиме"
    TR["Please run the script locally: sudo bash system-setup.sh"]="Запустите скрипт локально: sudo bash system-setup.sh"
    TR["Detected OS: %s %s"]="Обнаружена ОС: %s %s"
    TR["This script only supports Debian and Ubuntu"]="Этот скрипт поддерживает только Debian и Ubuntu"
    TR["Detected Debian version: %s (officially supported: 12, 13)"]="Обнаружена версия Debian: %s (официально поддерживаются: 12, 13)"
    TR["Detected Ubuntu version: %s (officially supported: 24.04, 25.04)"]="Обнаружена версия Ubuntu: %s (официально поддерживаются: 24.04, 25.04)"
    TR["Selected: Debian 12 (Bookworm)"]="Выбрано: Debian 12 (Bookworm)"
    TR["Selected: Debian 13 (Trixie)"]="Выбрано: Debian 13 (Trixie)"
    TR["Selected: Ubuntu 24.04 (Noble)"]="Выбрано: Ubuntu 24.04 (Noble)"
    TR["Selected: Ubuntu 25.04 (Plucky)"]="Выбрано: Ubuntu 25.04 (Plucky)"

    # === Configuration Options header ===
    TR["Configuration Options"]="Параметры конфигурации"

    # === RustDesk ===
    TR["Do you want to install RustDesk server in Docker?"]="Хотите установить сервер RustDesk в Docker?"
    TR["This will create /opt/rustdesk directory with docker-compose.yml"]="Будет создана директория /opt/rustdesk с docker-compose.yml"
    TR["and install it as a systemd service"]="и установлен как сервис systemd"

    # === Opt archive ===
    TR["Do you want to extract additional files to /opt?"]="Хотите извлечь дополнительные файлы в /opt?"
    TR["This will download opt.7z and copy all its contents to /opt"]="Будет загружен opt.7z и всё его содержимое скопировано в /opt"
    TR["Files in 'scripts' subfolder will be made executable (except .ini)"]="Файлы в подпапке 'scripts' станут исполняемыми (кроме .ini)"
    TR["The archive is password-protected. Please enter the password:"]="Архив защищён паролем. Пожалуйста, введите пароль:"
    TR["No password provided. opt.7z will not be extracted."]="Пароль не указан. opt.7z не будет извлечён."
    TR["Password saved. Archive will be extracted during installation."]="Пароль сохранён. Архив будет извлечён при установке."

    # === Root password ===
    TR["Do you want to set a password for root user?"]="Хотите установить пароль для пользователя root?"
    TR["Password cannot be empty"]="Пароль не может быть пустым"
    TR["Root password will be set"]="Пароль root будет установлен"
    TR["Passwords do not match. Please try again."]="Пароли не совпадают. Попробуйте ещё раз."

    # === User creation ===
    TR["Do you want to create a new user?"]="Хотите создать нового пользователя?"
    TR["Username cannot be empty"]="Имя пользователя не может быть пустым"
    TR["User %s already exists"]="Пользователь %s уже существует"
    TR["User %s will be created"]="Пользователь %s будет создан"

    # === SSH key ===
    TR["Do you want to configure SSH key for %s?"]="Хотите настроить SSH ключ для %s?"
    TR["Enter SSH public key for %s"]="Введите публичный SSH ключ для %s"
    TR["Example: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB..."]="Пример: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB..."
    TR["No SSH key provided, skipping SSH key configuration"]="SSH ключ не указан, настройка SSH ключа пропущена"

    # === Zsh ===
    TR["Do you want to install and configure zsh with Oh My Zsh for %s?"]="Хотите установить и настроить zsh с Oh My Zsh для %s?"

    # === Crontab ===
    TR["Do you want to configure crontab for root?"]="Хотите настроить crontab для root?"
    TR["Crontab configuration mode:"]="Режим настройки crontab:"
    TR["You can add multiple cron tasks after the environment variables"]="Вы можете добавить несколько задач cron после переменных окружения"
    TR["1) Enter tasks manually (line by line)"]="1) Ввести задачи вручную (построчно)"
    TR["2) Paste tasks from clipboard (recommended for multiple tasks)"]="2) Вставить задачи из буфера обмена (рекомендуется для нескольких задач)"
    TR["3) Skip adding tasks (only set environment variables)"]="3) Пропустить добавление задач (только установить переменные окружения)"
    TR["Enter cron tasks line by line"]="Введите задачи cron построчно"
    TR["Format: minute hour day month weekday command"]="Формат: минута час день месяц день_недели команда"
    TR["Example: 0 2 * * * /root/backup.sh"]="Пример: 0 2 * * * /root/backup.sh"
    TR["Press CTRL+D when finished"]="Нажмите CTRL+D для завершения"
    TR["Paste your cron tasks from clipboard"]="Вставьте ваши задачи cron из буфера обмена"
    TR["After pasting, type 'END' on a new line and press ENTER to finish"]="После вставки введите 'END' на новой строке и нажмите ENTER"
    TR["Paste now and type END when done:"]="Вставьте сейчас и введите END когда закончите:"
    TR["No tasks entered"]="Задачи не введены"
    TR["Captured %s cron task(s)"]="Получено %s задач(а) cron"
    TR["Skipping cron tasks - only environment variables will be set"]="Пропуск задач cron — будут установлены только переменные окружения"
    TR["Invalid option. Skipping cron tasks."]="Неверный вариант. Пропуск задач cron."

    # === SSH configuration ===
    TR["Do you want to configure SSH (change port and set AllowUsers)?"]="Хотите настроить SSH (изменить порт и установить AllowUsers)?"
    TR["Port %s is already in use by another service"]="Порт %s уже используется другим сервисом"
    TR["Invalid port number. Must be between 1 and 65535"]="Неверный номер порта. Должен быть от 1 до 65535"
    TR["Enter usernames for AllowUsers (space-separated, leave empty to skip)"]="Введите имена пользователей для AllowUsers (через пробел, оставьте пустым для пропуска)"
    TR["Example: user1 user2 user3"]="Пример: user1 user2 user3"
    TR["Suggestion: %s"]="Предложение: %s"
    TR["The following users do not exist:%s"]="Следующие пользователи не существуют:%s"
    TR["Setting AllowUsers with non-existent users may lock you out of SSH!"]="Установка AllowUsers с несуществующими пользователями может заблокировать доступ по SSH!"
    TR["AllowUsers configuration skipped"]="Настройка AllowUsers пропущена"
    TR["Advanced SSH Security Parameters"]="Расширенные параметры безопасности SSH"
    TR["Configure additional SSH security settings"]="Настройка дополнительных параметров безопасности SSH"
    TR["PubkeyAuthentication - Enable public key authentication"]="PubkeyAuthentication — Аутентификация по публичному ключу"
    TR["PasswordAuthentication - Enable password authentication"]="PasswordAuthentication — Аутентификация по паролю"
    TR["PermitEmptyPasswords - Prevent empty password authentication (ALWAYS set to 'no')"]="PermitEmptyPasswords — Запрет пустых паролей (ВСЕГДА установлено в 'no')"
    TR["PermitRootLogin - Allow root user to login via SSH"]="PermitRootLogin — Разрешить вход root через SSH"

    # === Python venv ===
    TR["Do you want to create Python virtual environment?"]="Хотите создать виртуальное окружение Python?"

    # === Docker ===
    TR["Do you want to install Docker?"]="Хотите установить Docker?"
    TR["Do you want to install ufw-docker (UFW integration for Docker)?"]="Хотите установить ufw-docker (интеграция UFW с Docker)?"
    TR["Note: This can be installed even without Docker"]="Примечание: можно установить даже без Docker"

    # === Go ===
    TR["Do you want to install the latest version of Go?"]="Хотите установить последнюю версию Go?"
    TR["Go will be installed for user: %s"]="Go будет установлен для пользователя: %s"
    TR["Note: Go installation requires a user to be created"]="Примечание: для установки Go необходим созданный пользователь"

    # === ipset ===
    TR["Do you want to build and install the latest version of ipset?"]="Хотите собрать и установить последнюю версию ipset?"
    TR["This will compile ipset from source"]="ipset будет скомпилирован из исходного кода"

    # === UFW ===
    TR["Do you want to configure UFW firewall?"]="Хотите настроить файрвол UFW?"
    TR["Do you want to block ICMP (ping) requests?"]="Хотите заблокировать ICMP (ping) запросы?"
    TR["Note: This will make your server invisible to ping"]="Примечание: сервер станет невидимым для ping"
    TR["Do you want to install custom UFW Docker rules script?"]="Хотите установить скрипт пользовательских правил UFW для Docker?"
    TR["Available versions:"]="Доступные версии:"
    TR["Both versions support custom SSH port configuration"]="Обе версии поддерживают настройку пользовательского порта SSH"
    TR["Both versions available from archive or repository"]="Обе версии доступны из архива или репозитория"
    TR["Note: The script will run AFTER all other installations complete"]="Примечание: скрипт запустится ПОСЛЕ завершения всех установок"
    TR["Select version:"]="Выберите версию:"
    TR["Invalid version. Using v6 as default."]="Неверная версия. Используется v6 по умолчанию."
    TR["Selected version: v%s"]="Выбрана версия: v%s"
    TR["Select installation source:"]="Выберите источник установки:"
    TR["No password provided. Custom UFW rules will not be installed."]="Пароль не указан. Пользовательские правила UFW не будут установлены."
    TR["Will install from public repository (no password required)"]="Установка из публичного репозитория (пароль не требуется)"
    TR["Enter SSH port for UFW rules:"]="Введите порт SSH для правил UFW:"
    TR["This port will be used instead of the default in the script"]="Этот порт будет использоваться вместо значения по умолчанию в скрипте"
    TR["Note: This keeps your actual SSH port private"]="Примечание: ваш реальный порт SSH останется скрытым"
    TR["Invalid port number. Using default port 22."]="Неверный номер порта. Используется порт 22 по умолчанию."
    TR["SSH port set to: %s"]="Порт SSH установлен: %s"
    TR["UFW Firewall Configuration"]="Настройка файрвола UFW"
    TR["Port %s (SSH) will be allowed automatically"]="Порт %s (SSH) будет разрешён автоматически"
    TR["You can add additional ports to UFW"]="Вы можете добавить дополнительные порты в UFW"
    TR["Format examples:"]="Примеры формата:"
    TR["Custom ports will be configured: %s"]="Пользовательские порты будут настроены: %s"

    # === sysctl ===
    TR["Do you want to optimize system parameters (sysctl.conf)?"]="Хотите оптимизировать системные параметры (sysctl.conf)?"

    # === IPv6 GRUB ===
    TR["Do you want to disable IPv6 at kernel level (GRUB)?"]="Хотите отключить IPv6 на уровне ядра (GRUB)?"
    TR["This adds 'ipv6.disable=1' to GRUB_CMDLINE_LINUX_DEFAULT"]="Добавляет 'ipv6.disable=1' в GRUB_CMDLINE_LINUX_DEFAULT"
    TR["Note: This is in addition to sysctl IPv6 disable and requires reboot"]="Примечание: это дополнение к отключению IPv6 через sysctl, требует перезагрузки"

    # === Repositories ===
    TR["Do you want to configure %s repositories?"]="Хотите настроить репозитории %s?"
    TR["Do you want to add Tataranovich repository (custom mc build)?"]="Хотите добавить репозиторий Tataranovich (сборка mc)?"
    TR["This will install Midnight Commander from tataranovich.com"]="Будет установлен Midnight Commander из tataranovich.com"
    TR["Note: Tataranovich repository is not available for Debian 13+"]="Примечание: репозиторий Tataranovich недоступен для Debian 13+"
    TR["Do you want to add additional PPA repositories for Ubuntu?"]="Хотите добавить дополнительные PPA-репозитории для Ubuntu?"
    TR["Available PPAs:"]="Доступные PPA:"
    TR["Select which PPAs to add:"]="Выберите, какие PPA добавить:"
    TR["Do you want to add Tataranovich repository for Ubuntu (custom mc build)?"]="Хотите добавить репозиторий Tataranovich для Ubuntu (сборка mc)?"

    # === IPv6 interfaces ===
    TR["Do you want to disable IPv6 in /etc/network/interfaces?"]="Хотите отключить IPv6 в /etc/network/interfaces?"
    TR["This will comment out all inet6 configuration lines"]="Все строки конфигурации inet6 будут закомментированы"
    TR["Note: This is useful if you're using static network configuration"]="Примечание: полезно при использовании статической настройки сети"

    # === MOTD ===
    TR["Do you want to install custom MOTD (Message of the Day)?"]="Хотите установить пользовательский MOTD (сообщение дня)?"

    # === BBR ===
    TR["Advanced Network Optimization (BBR)"]="Расширенная сетевая оптимизация (BBR)"
    TR["Do you want to run the BBR Network Optimizer script?"]="Хотите запустить скрипт оптимизации сети BBR?"
    TR["This will apply TCP BBR congestion control and other network optimizations"]="Будет применён контроль перегрузки TCP BBR и другие сетевые оптимизации"
    TR["Note: This script will run AFTER all other installations complete"]="Примечание: скрипт запустится ПОСЛЕ завершения всех остальных установок"
    TR["BBR Network Optimizer Options:"]="Параметры оптимизатора сети BBR:"
    TR["The following functions can be enabled/disabled:"]="Следующие функции можно включить/отключить:"
    TR["BBR optimization settings will be applied after main installation"]="Настройки оптимизации BBR будут применены после основной установки"

    # === Non-interactive mode ===
    TR["Non-interactive mode - using default settings:"]="Неинтерактивный режим — используются настройки по умолчанию:"
    TR["- Root password: NO"]="- Пароль root: НЕТ"
    TR["- Create user: NO"]="- Создание пользователя: НЕТ"
    TR["- SSH configuration: NO"]="- Настройка SSH: НЕТ"
    TR["- Python venv: NO"]="- Python venv: НЕТ"
    TR["- Docker: NO"]="- Docker: НЕТ"
    TR["- ufw-docker: NO"]="- ufw-docker: НЕТ"
    TR["- UFW: YES"]="- UFW: ДА"
    TR["- Block ICMP: NO"]="- Блокировка ICMP: НЕТ"
    TR["- sysctl: YES"]="- sysctl: ДА"
    TR["- Repositories: YES"]="- Репозитории: ДА"
    TR["- MOTD: NO"]="- MOTD: НЕТ"
    TR["- Custom UFW Port: None"]="- Пользовательские порты UFW: Нет"
    TR["- Crontab: NO"]="- Crontab: НЕТ"
    TR["- BBR Optimizer: NO"]="- Оптимизатор BBR: НЕТ"

    # === Configuration Summary ===
    TR["Configuration Summary:"]="Сводка конфигурации:"
    TR["Proceed with installation?"]="Продолжить установку?"
    TR["Installation cancelled by user"]="Установка отменена пользователем"

    # === Package installation ===
    TR["Installing packages..."]="Установка пакетов..."
    TR["Updating package lists..."]="Обновление списка пакетов..."
    TR["Package lists updated"]="Список пакетов обновлён"
    TR["Failed to update package lists"]="Не удалось обновить список пакетов"
    TR["Upgrading existing packages..."]="Обновление установленных пакетов..."
    TR["Packages upgraded successfully"]="Пакеты успешно обновлены"
    TR["Failed to upgrade packages"]="Не удалось обновить пакеты"
    TR["Installing common packages..."]="Установка общих пакетов..."
    TR["Common packages installed successfully"]="Общие пакеты установлены успешно"
    TR["Some packages failed to install"]="Некоторые пакеты не удалось установить"
    TR["Installing OS-specific packages for %s..."]="Установка специфичных пакетов для %s..."
    TR["OS-specific packages installed successfully"]="Специфичные пакеты ОС установлены успешно"
    TR["Some OS-specific packages failed to install"]="Некоторые специфичные пакеты ОС не удалось установить"

    # === Root password setting ===
    TR["Setting root password..."]="Установка пароля root..."
    TR["Root password set successfully"]="Пароль root установлен успешно"
    TR["Failed to set root password"]="Не удалось установить пароль root"
    TR["Skipping root password (not requested)"]="Пропуск установки пароля root (не запрошено)"

    # === User creation ===
    TR["Creating user %s..."]="Создание пользователя %s..."
    TR["User %s created successfully"]="Пользователь %s создан успешно"
    TR["Failed to create user %s"]="Не удалось создать пользователя %s"
    TR["Password set for %s"]="Пароль установлен для %s"
    TR["User %s added to sudo group"]="Пользователь %s добавлен в группу sudo"
    TR["Using existing user: %s"]="Используется существующий пользователь: %s"
    TR["User %s is already in sudo group"]="Пользователь %s уже в группе sudo"
    TR["Skipping user creation (not requested)"]="Пропуск создания пользователя (не запрошено)"

    # === SSH key configuration ===
    TR["Configuring SSH key for %s"]="Настройка SSH ключа для %s"
    TR["Created .ssh directory for %s"]="Создана директория .ssh для %s"
    TR["SSH key added to %s"]="SSH ключ добавлен в %s"
    TR["SSH key configured successfully for %s"]="SSH ключ успешно настроен для %s"

    # === Repository configuration ===
    TR["Configuring Debian repositories..."]="Настройка репозиториев Debian..."
    TR["Configuring Ubuntu repositories..."]="Настройка репозиториев Ubuntu..."
    TR["Repositories configured"]="Репозитории настроены"
    TR["Skipping repository configuration (not requested)"]="Пропуск настройки репозиториев (не запрошено)"
    TR["Adding Tataranovich repository..."]="Добавление репозитория Tataranovich..."
    TR["Tataranovich repository added"]="Репозиторий Tataranovich добавлен"
    TR["Failed to add Tataranovich repository"]="Не удалось добавить репозиторий Tataranovich"
    TR["Installing mc from Tataranovich repository..."]="Установка mc из репозитория Tataranovich..."
    TR["mc installed from Tataranovich repository"]="mc установлен из репозитория Tataranovich"
    TR["Adding PPA repositories..."]="Добавление PPA-репозиториев..."
    TR["Adding PPA: %s"]="Добавление PPA: %s"
    TR["PPA %s added successfully"]="PPA %s добавлен успешно"
    TR["Failed to add PPA: %s"]="Не удалось добавить PPA: %s"

    # === Zsh installation ===
    TR["Installing Oh My Zsh for %s"]="Установка Oh My Zsh для %s"
    TR["Installing Oh My Zsh..."]="Установка Oh My Zsh..."
    TR["Oh My Zsh installed successfully"]="Oh My Zsh установлен успешно"
    TR["Installing zsh plugins..."]="Установка плагинов zsh..."
    TR["Zsh plugins installed successfully"]="Плагины zsh установлены успешно"
    TR["Downloading custom .zshrc configuration..."]="Загрузка пользовательской конфигурации .zshrc..."
    TR["Custom .zshrc downloaded successfully"]="Пользовательская конфигурация .zshrc загружена успешно"
    TR["Failed to download custom .zshrc, using default"]="Не удалось загрузить .zshrc, используется стандартный"
    TR["Changing default shell to zsh for %s"]="Смена оболочки по умолчанию на zsh для %s"
    TR["Default shell changed to zsh"]="Оболочка по умолчанию изменена на zsh"
    TR["Oh My Zsh installation failed"]="Установка Oh My Zsh не удалась"

    # === sysctl configuration ===
    TR["Configuring sysctl.conf..."]="Настройка sysctl.conf..."
    TR["sysctl.conf configured"]="sysctl.conf настроен"
    TR["Applying sysctl settings..."]="Применение настроек sysctl..."
    TR["Some sysctl parameters may not have been applied"]="Некоторые параметры sysctl могли не примениться"
    TR["Removing IPv6 nameservers from %s (IPv6 is now disabled)..."]="Удаление IPv6 nameserver из %s (IPv6 теперь отключен)..."
    TR["IPv6 nameservers removed from %s"]="IPv6 nameserver удалены из %s"
    TR["No IPv4 nameservers found, adding fallback DNS servers..."]="IPv4 nameserver не найдены, добавляем резервные DNS серверы..."
    TR["Fallback DNS servers (8.8.8.8, 1.1.1.1) added to %s"]="Резервные DNS серверы (8.8.8.8, 1.1.1.1) добавлены в %s"
    TR["Skipping sysctl configuration (not requested)"]="Пропуск настройки sysctl (не запрошено)"
    TR["Original sysctl.conf backed up"]="Резервная копия sysctl.conf создана"

    # === GRUB IPv6 ===
    TR["Disabling IPv6 at kernel level via GRUB..."]="Отключение IPv6 на уровне ядра через GRUB..."
    TR["Original GRUB config backed up"]="Резервная копия конфигурации GRUB создана"
    TR["GRUB config file not found: %s"]="Файл конфигурации GRUB не найден: %s"
    TR["Skipping IPv6 GRUB disable"]="Пропуск отключения IPv6 через GRUB"
    TR["ipv6.disable=1 already present in GRUB config"]="ipv6.disable=1 уже присутствует в конфигурации GRUB"
    TR["Added ipv6.disable=1 to GRUB config"]="Добавлено ipv6.disable=1 в конфигурацию GRUB"
    TR["Updating GRUB..."]="Обновление GRUB..."
    TR["GRUB updated successfully"]="GRUB обновлён успешно"
    TR["Failed to update GRUB"]="Не удалось обновить GRUB"
    TR["IPv6 will be disabled at kernel level after reboot"]="IPv6 будет отключён на уровне ядра после перезагрузки"

    # === IPv6 interfaces ===
    TR["Commenting out IPv6 configuration in /etc/network/interfaces..."]="Комментирование конфигурации IPv6 в /etc/network/interfaces..."
    TR["File %s not found"]="Файл %s не найден"
    TR["Your system may use netplan or NetworkManager instead"]="Ваша система может использовать netplan или NetworkManager"
    TR["Skipping /etc/network/interfaces IPv6 configuration"]="Пропуск настройки IPv6 в /etc/network/interfaces"
    TR["Original %s backed up"]="Резервная копия %s создана"
    TR["Found IPv6 configuration in %s"]="Найдена конфигурация IPv6 в %s"
    TR["IPv6 configuration commented out in %s"]="Конфигурация IPv6 закомментирована в %s"
    TR["Modified %s preview:"]="Предварительный просмотр изменённого %s:"
    TR["No IPv6 lines remaining (all commented)"]="Строк IPv6 не осталось (все закомментированы)"
    TR["IPv6 nameservers removed from %s"]="DNS-серверы IPv6 удалены из %s"
    TR["No IPv6 nameservers found in %s"]="DNS-серверы IPv6 не найдены в %s"
    TR["Not modifying %s - would result in empty file"]="Файл %s не изменён — результат был бы пустым"
    TR["Failed to create modified interfaces file"]="Не удалось создать изменённый файл интерфейсов"
    TR["Restored from backup"]="Восстановлено из резервной копии"
    TR["No IPv6 configuration found in %s"]="Конфигурация IPv6 не найдена в %s"
    TR["File is already without IPv6 or uses different format"]="Файл уже без IPv6 или использует другой формат"
    TR["Network configuration changed. You may need to restart networking:"]="Сетевая конфигурация изменена. Возможно, потребуется перезапуск сети:"
    TR["Skipping IPv6 commenting in /etc/network/interfaces (not requested)"]="Пропуск комментирования IPv6 в /etc/network/interfaces (не запрошено)"

    # === SSH configuration ===
    TR["Configuring SSH..."]="Настройка SSH..."
    TR["Original sshd_config backed up"]="Резервная копия sshd_config создана"
    TR["SSH port changed to %s"]="Порт SSH изменён на %s"
    TR["SSH port set to %s"]="Порт SSH установлен на %s"
    TR["Configured: %s = %s"]="Настроено: %s = %s"
    TR["AllowUsers set to: %s"]="AllowUsers установлено: %s"
    TR["Testing SSH configuration..."]="Проверка конфигурации SSH..."
    TR["SSH configuration test passed"]="Проверка конфигурации SSH пройдена"
    TR["SSH configuration test FAILED!"]="Проверка конфигурации SSH НЕ ПРОЙДЕНА!"
    TR["Restoring original sshd_config..."]="Восстановление исходного sshd_config..."
    TR["Original sshd_config restored"]="Исходный sshd_config восстановлён"
    TR["Restarting SSH service..."]="Перезапуск службы SSH..."
    TR["SSH service restarted"]="Служба SSH перезапущена"
    TR["Failed to restart SSH service"]="Не удалось перезапустить службу SSH"
    TR["Skipping SSH configuration (not requested)"]="Пропуск настройки SSH (не запрошено)"

    # === UFW configuration ===
    TR["Configuring UFW firewall..."]="Настройка файрвола UFW..."
    TR["Setting UFW default policies..."]="Установка политик UFW по умолчанию..."
    TR["Failed to set UFW default policy"]="Не удалось установить политику UFW по умолчанию"
    TR["UFW default policies configured"]="Политики UFW по умолчанию настроены"
    TR["UFW rule added: Allow SSH (port %s)"]="Правило UFW добавлено: разрешить SSH (порт %s)"
    TR["Failed to add SSH UFW rule"]="Не удалось добавить правило UFW для SSH"
    TR["Configuring custom ports: %s"]="Настройка пользовательских портов: %s"
    TR["UFW rule added: Allow port %s/%s"]="Правило UFW добавлено: разрешить порт %s/%s"
    TR["Invalid port number: %s (must be 1-65535). Skipping."]="Неверный номер порта: %s (должен быть 1-65535). Пропуск."
    TR["Invalid port format: %s (expected: number or number/protocol). Skipping."]="Неверный формат порта: %s (ожидается: номер или номер/протокол). Пропуск."
    TR["Enabling UFW..."]="Включение UFW..."
    TR["Failed to enable UFW"]="Не удалось включить UFW"
    TR["Skipping UFW configuration (not requested)"]="Пропуск настройки UFW (не запрошено)"

    # === ICMP blocking ===
    TR["Configuring ICMP blocking..."]="Настройка блокировки ICMP..."
    TR["ICMP blocking configured in %s"]="Блокировка ICMP настроена в %s"
    TR["Reloading UFW to apply ICMP blocking..."]="Перезагрузка UFW для применения блокировки ICMP..."
    TR["Failed to reload UFW"]="Не удалось перезагрузить UFW"
    TR["UFW reloaded"]="UFW перезагружен"
    TR["Failed to configure ICMP blocking"]="Не удалось настроить блокировку ICMP"

    # === Docker installation ===
    TR["Installing Docker..."]="Установка Docker..."
    TR["Docker is already installed"]="Docker уже установлен"
    TR["Downloading Docker installation script..."]="Загрузка скрипта установки Docker..."
    TR["Running Docker installation script..."]="Запуск скрипта установки Docker..."
    TR["Docker installed successfully"]="Docker установлен успешно"
    TR["Failed to download Docker installation script"]="Не удалось загрузить скрипт установки Docker"
    TR["Docker installation script failed (check network/DNS)"]="Скрипт установки Docker завершился с ошибкой (проверьте сеть/DNS)"
    TR["Failed to start Docker"]="Не удалось запустить Docker"
    TR["Failed to enable Docker"]="Не удалось включить Docker"
    TR["Creating docker group..."]="Создание группы docker..."
    TR["User %s added to docker group"]="Пользователь %s добавлен в группу docker"
    TR["Skipping Docker installation (not requested)"]="Пропуск установки Docker (не запрошено)"

    # === Go installation ===
    TR["Installing latest version of Go for user %s..."]="Установка последней версии Go для пользователя %s..."
    TR["Cannot install Go: No user was created"]="Невозможно установить Go: пользователь не был создан"
    TR["Go installation requires a non-root user"]="Для установки Go необходим непривилегированный пользователь"
    TR["Fetching latest Go version..."]="Получение последней версии Go..."
    TR["Could not fetch latest Go version, using fallback: go1.23.4"]="Не удалось получить версию Go, используется: go1.23.4"
    TR["Latest Go version: %s"]="Последняя версия Go: %s"
    TR["Downloading Go..."]="Загрузка Go..."
    TR["Go downloaded successfully"]="Go загружен успешно"
    TR["Failed to download Go"]="Не удалось загрузить Go"
    TR["Extracting Go to /usr/local..."]="Извлечение Go в /usr/local..."
    TR["Go extracted successfully"]="Go извлечён успешно"
    TR["Go installed successfully: %s"]="Go установлен успешно: %s"
    TR["Go installation verification failed"]="Проверка установки Go не пройдена"

    # === ipset installation ===
    TR["Installing ipset from source..."]="Установка ipset из исходного кода..."
    TR["Installing build dependencies for ipset..."]="Установка зависимостей сборки для ipset..."
    TR["Fetching latest ipset version..."]="Получение последней версии ipset..."
    TR["Latest ipset version: %s"]="Последняя версия ipset: %s"
    TR["Downloading ipset from: %s"]="Загрузка ipset из: %s"
    TR["ipset downloaded successfully"]="ipset загружен успешно"
    TR["Extracting ipset..."]="Извлечение ipset..."
    TR["Configuring ipset with kernel headers..."]="Настройка ipset с заголовками ядра..."
    TR["Configuration successful"]="Настройка успешна"
    TR["Building ipset (using %s cores)..."]="Сборка ipset (используется %s ядер)..."
    TR["Build successful"]="Сборка успешна"
    TR["Installing ipset..."]="Установка ipset..."
    TR["ipset installed successfully"]="ipset установлен успешно"
    TR["ipset version: %s"]="Версия ipset: %s"
    TR["ipset installed but version check failed"]="ipset установлен, но проверка версии не прошла"
    TR["Failed to install ipset"]="Не удалось установить ipset"
    TR["Failed to build ipset"]="Не удалось собрать ipset"
    TR["Failed to configure ipset"]="Не удалось настроить ipset"
    TR["Check that kernel headers are properly installed"]="Проверьте правильность установки заголовков ядра"
    TR["Failed to extract ipset archive contents"]="Не удалось извлечь содержимое архива ipset"
    TR["Failed to download ipset"]="Не удалось загрузить ipset"
    TR["Skipping ipset installation (not requested)"]="Пропуск установки ipset (не запрошено)"

    # === Python venv ===
    TR["Creating Python virtual environment..."]="Создание виртуального окружения Python..."
    TR["Virtual environment created at %s"]="Виртуальное окружение создано в %s"
    TR["Failed to create virtual environment"]="Не удалось создать виртуальное окружение"
    TR["Skipping Python venv creation (not requested)"]="Пропуск создания Python venv (не запрошено)"

    # === Crontab ===
    TR["Configuring crontab for root..."]="Настройка crontab для root..."
    TR["Existing crontab backed up"]="Существующий crontab сохранён"
    TR["Crontab configured successfully"]="Crontab настроен успешно"
    TR["Current crontab:"]="Текущий crontab:"
    TR["Skipping crontab configuration (not requested)"]="Пропуск настройки crontab (не запрошено)"

    # === MOTD ===
    TR["Installing custom MOTD..."]="Установка пользовательского MOTD..."
    TR["Custom MOTD installed successfully"]="Пользовательский MOTD установлен успешно"
    TR["Failed to install MOTD"]="Не удалось установить MOTD"
    TR["Skipping MOTD installation (not requested)"]="Пропуск установки MOTD (не запрошено)"
    TR["Disabling default MOTD components..."]="Отключение стандартных компонентов MOTD..."
    TR["Default MOTD components disabled"]="Стандартные компоненты MOTD отключены"

    # === ufw-docker ===
    TR["Installing ufw-docker..."]="Установка ufw-docker..."
    TR["ufw-docker installed successfully"]="ufw-docker установлен успешно"
    TR["Failed to install ufw-docker"]="Не удалось установить ufw-docker"
    TR["Skipping ufw-docker installation (not requested)"]="Пропуск установки ufw-docker (не запрошено)"

    # === RustDesk ===
    TR["Installing RustDesk server..."]="Установка сервера RustDesk..."
    TR["RustDesk server installed successfully"]="Сервер RustDesk установлен успешно"
    TR["Failed to install RustDesk server"]="Не удалось установить сервер RustDesk"
    TR["Skipping RustDesk installation (not requested)"]="Пропуск установки RustDesk (не запрошено)"
    TR["RustDesk directory created: /opt/rustdesk"]="Директория RustDesk создана: /opt/rustdesk"

    # === Opt archive ===
    TR["Extracting opt.7z archive..."]="Извлечение архива opt.7z..."
    TR["opt.7z extracted successfully"]="opt.7z успешно извлечён"
    TR["Failed to extract opt.7z"]="Не удалось извлечь opt.7z"
    TR["Skipping opt.7z extraction (not requested)"]="Пропуск извлечения opt.7z (не запрошено)"
    TR["Setting permissions for scripts..."]="Установка прав на скрипты..."
    TR["Permissions set for scripts"]="Права на скрипты установлены"

    # === UFW custom rules ===
    TR["Installing custom UFW Docker rules..."]="Установка пользовательских правил UFW для Docker..."
    TR["Custom UFW Docker rules installed"]="Пользовательские правила UFW для Docker установлены"
    TR["Failed to install custom UFW Docker rules"]="Не удалось установить пользовательские правила UFW для Docker"

    # === BBR Optimizer ===
    TR["Running BBR Network Optimizer..."]="Запуск оптимизатора сети BBR..."
    TR["BBR Network Optimizer completed"]="Оптимизатор сети BBR завершён"
    TR["BBR Network Optimizer failed"]="Оптимизатор сети BBR завершился с ошибкой"
    TR["Skipping BBR Network Optimizer (not requested)"]="Пропуск оптимизатора сети BBR (не запрошено)"

    # === Final summary ===
    TR["Installation Complete!"]="Установка завершена!"
    TR["System Setup Summary:"]="Сводка настройки системы:"
    TR["IMPORTANT NOTES:"]="ВАЖНЫЕ ЗАМЕЧАНИЯ:"
    TR["Post-Installation Steps:"]="Шаги после установки:"
    TR["Thank you for using the setup script!"]="Спасибо за использование скрипта настройки!"
    TR["A reboot is recommended to apply all changes"]="Рекомендуется перезагрузка для применения всех изменений"
    TR["Reboot now? (y/N): "]="Перезагрузить сейчас? (y/N): "

    # === read -p prompts ===
    TR["Enter your choice [1-4]: "]="Введите ваш выбор [1-4]: "
    TR["Continue anyway? (y/N): "]="Продолжить? (y/N): "
    TR["Install RustDesk? (y/N): "]="Установить RustDesk? (y/N): "
    TR["Extract opt.7z to /opt? (y/N): "]="Извлечь opt.7z в /opt? (y/N): "
    TR["Password: "]="Пароль: "
    TR["Set root password? (y/N): "]="Установить пароль root? (y/N): "
    TR["Enter new root password: "]="Введите новый пароль root: "
    TR["Confirm root password: "]="Подтвердите пароль root: "
    TR["Create new user? (y/N): "]="Создать нового пользователя? (y/N): "
    TR["Enter username for new user: "]="Введите имя нового пользователя: "
    TR["Continue with existing user? (y/N): "]="Продолжить с существующим пользователем? (y/N): "
    TR["Enter password for %s: "]="Введите пароль для %s: "
    TR["Confirm password: "]="Подтвердите пароль: "
    TR["Configure SSH key? (y/N): "]="Настроить SSH ключ? (y/N): "
    TR["SSH public key: "]="Публичный SSH ключ: "
    TR["Install zsh? (y/N): "]="Установить zsh? (y/N): "
    TR["Configure crontab? (y/N): "]="Настроить crontab? (y/N): "
    TR["Choose option [1-3] (default: 3): "]="Выберите вариант [1-3] (по умолчанию: 3): "
    TR["Configure SSH? (y/N): "]="Настроить SSH? (y/N): "
    TR["Enter new SSH port (default 22): "]="Введите новый порт SSH (по умолчанию 22): "
    TR["AllowUsers: "]="AllowUsers: "
    TR["Configure PubkeyAuthentication? (y/N): "]="Настроить PubkeyAuthentication? (y/N): "
    TR["Set PubkeyAuthentication to yes or no? (Y/n): "]="Установить PubkeyAuthentication в yes или no? (Y/n): "
    TR["Configure PasswordAuthentication? (y/N): "]="Настроить PasswordAuthentication? (y/N): "
    TR["Set PasswordAuthentication to yes or no? (Y/n): "]="Установить PasswordAuthentication в yes или no? (Y/n): "
    TR["Configure PermitEmptyPasswords? (y/N): "]="Настроить PermitEmptyPasswords? (y/N): "
    TR["Configure PermitRootLogin? (y/N): "]="Настроить PermitRootLogin? (y/N): "
    TR["Set PermitRootLogin to yes or no? (Y/n): "]="Установить PermitRootLogin в yes или no? (Y/n): "
    TR["Create Python venv? (y/N): "]="Создать Python venv? (y/N): "
    TR["Enter path for virtual environment (default: /root/skripts): "]="Введите путь для виртуального окружения (по умолчанию: /root/skripts): "
    TR["Install Docker? (y/N): "]="Установить Docker? (y/N): "
    TR["Install ufw-docker? (y/N): "]="Установить ufw-docker? (y/N): "
    TR["Install Go? (y/N): "]="Установить Go? (y/N): "
    TR["Install ipset? (y/N): "]="Установить ipset? (y/N): "
    TR["Configure UFW? (Y/n): "]="Настроить UFW? (Y/n): "
    TR["Block ICMP? (y/N): "]="Блокировать ICMP? (y/N): "
    TR["Install custom UFW Docker rules? (y/N): "]="Установить правила UFW для Docker? (y/N): "
    TR["Enter version (4 or 6, default: 6): "]="Введите версию (4 или 6, по умолчанию: 6): "
    TR["Choose source (1 or 2, default: 1): "]="Выберите источник (1 или 2, по умолчанию: 1): "
    TR["SSH Port (default: 22): "]="Порт SSH (по умолчанию: 22): "
    TR["Configure sysctl? (Y/n): "]="Настроить sysctl? (Y/n): "
    TR["Disable IPv6 via GRUB? (y/N): "]="Отключить IPv6 через GRUB? (y/N): "
    TR["Configure repositories? (Y/n): "]="Настроить репозитории? (Y/n): "
    TR["Add Tataranovich repository? (y/N): "]="Добавить репозиторий Tataranovich? (y/N): "
    TR["Add PPA repositories? (y/N): "]="Добавить PPA-репозитории? (y/N): "
    TR["   Add Ondrej Nginx PPA? (y/N): "]="   Добавить Ondrej Nginx PPA? (y/N): "
    TR["   Add Git Core PPA? (y/N): "]="   Добавить Git Core PPA? (y/N): "
    TR["   Add Ubuntu Toolchain PPA? (y/N): "]="   Добавить Ubuntu Toolchain PPA? (y/N): "
    TR["Add Tataranovich repository for Ubuntu? (y/N): "]="Добавить репозиторий Tataranovich для Ubuntu? (y/N): "
    TR["Comment out IPv6 in /etc/network/interfaces? (y/N): "]="Закомментировать IPv6 в /etc/network/interfaces? (y/N): "
    TR["Install MOTD? (y/N): "]="Установить MOTD? (y/N): "
    TR["Enter additional ports (comma-separated, press Enter to skip): "]="Введите дополнительные порты (через запятую, Enter для пропуска): "
    TR["Run BBR Network Optimizer? (y/N): "]="Запустить оптимизатор сети BBR? (y/N): "
    TR["Proceed with these settings? (Y/n): "]="Продолжить с этими настройками? (Y/n): "
    TR["OR reboot the system"]="ИЛИ перезагрузите систему"

    # === Echo menu items ===
    TR["Single port:     8080"]="Один порт:       8080"
    TR["With protocol:   8080/tcp  or  53/udp"]="С протоколом:    8080/tcp  или  53/udp"
    TR["Multiple ports:  8080,8443,9000"]="Несколько портов: 8080,8443,9000"
    TR["Mixed:          8080/tcp,53/udp,3000"]="Смешанные:       8080/tcp,53/udp,3000"

    # === BBR sub-options ===
    TR["1. Force IPv4 for APT (recommended for IPv6 connectivity issues)"]="1. Принудительный IPv4 для APT (рекомендуется при проблемах с IPv6)"
    TR["2. Full system update and upgrade (apt update && upgrade)"]="2. Полное обновление системы (apt update && upgrade)"
    TR["3. Fix /etc/hosts file (add hostname entry)"]="3. Исправление файла /etc/hosts (добавление записи hostname)"
    TR["4. Fix DNS configuration (set Cloudflare DNS)"]="4. Исправление настроек DNS (установка Cloudflare DNS)"

    # === Summary section labels ===
    TR["OS: %s %s (%s)"]="ОС: %s %s (%s)"
    TR["YES"]="ДА"
    TR["NO"]="НЕТ"
    TR["YES (%s)"]="ДА (%s)"
    TR["YES (Docker)"]="ДА (Docker)"
    TR["YES (Port: %s, Users: %s)"]="ДА (Порт: %s, Пользователи: %s)"
    TR["YES (Path: %s)"]="ДА (Путь: %s)"
    TR["YES (latest version)"]="ДА (последняя версия)"
    TR["YES (build from source)"]="ДА (сборка из исходного кода)"
    TR["YES (kernel level)"]="ДА (уровень ядра)"
    TR["None"]="Нет"
    TR["Standard"]="Стандартная"
    TR["Enhanced with RustDesk"]="Расширенная с RustDesk"
    TR["Archive (password-protected)"]="Архив (защищён паролем)"
    TR["Repository (public)"]="Репозиторий (публичный)"

    # === Final report section ===
    TR["Useful commands:"]="Полезные команды:"
    TR["Rebooting system..."]="Перезагрузка системы..."
    TR["Please reboot manually when ready"]="Пожалуйста, перезагрузите вручную, когда будете готовы"
    TR["Script completed in %s seconds"]="Скрипт выполнен за %s секунд"

    # === Misc messages found throughout the script ===
    TR["Backing up sshd_config..."]="Резервное копирование sshd_config..."
    TR["Installing 7zip..."]="Установка 7zip..."
    TR["7zip installed"]="7zip установлен"
    TR["Downloading opt.7z..."]="Загрузка opt.7z..."
    TR["Downloading UFW Docker rules archive..."]="Загрузка архива правил UFW для Docker..."
    TR["Downloading UFW Docker rules from repository..."]="Загрузка правил UFW для Docker из репозитория..."
    TR["Script downloaded: %s"]="Скрипт загружен: %s"
    TR["Making script executable..."]="Установка прав на выполнение..."
    TR["Running UFW Docker rules script..."]="Запуск скрипта правил UFW для Docker..."
    TR["UFW Docker rules script completed"]="Скрипт правил UFW для Docker завершён"
    TR["Failed to run UFW Docker rules script"]="Не удалось запустить скрипт правил UFW для Docker"
    TR["Cleaning up temporary files..."]="Очистка временных файлов..."
    TR["Temporary files cleaned up"]="Временные файлы очищены"

    # More installation messages
    TR["Installing mc from standard repository..."]="Установка mc из стандартного репозитория..."
    TR["mc installed from standard repository"]="mc установлен из стандартного репозитория"
    TR["Skipping Tataranovich repository (not requested)"]="Пропуск репозитория Tataranovich (не запрошено)"
    TR["Adding Tataranovich repository for Ubuntu..."]="Добавление репозитория Tataranovich для Ubuntu..."

    # Docker-compose and RustDesk messages
    TR["Docker Compose is already available"]="Docker Compose уже доступен"
    TR["Creating RustDesk directory structure..."]="Создание структуры каталогов RustDesk..."
    TR["Starting RustDesk server..."]="Запуск сервера RustDesk..."
    TR["RustDesk server is running"]="Сервер RustDesk запущен"
    TR["Creating systemd service for RustDesk..."]="Создание сервиса systemd для RustDesk..."

    # Post-install steps
    TR["Review UFW status: sudo ufw status verbose"]="Проверьте статус UFW: sudo ufw status verbose"
    TR["Test SSH connection on new port before closing current session!"]="Проверьте SSH подключение на новом порту перед закрытием текущей сессии!"
    TR["Verify all services are running correctly"]="Убедитесь, что все сервисы работают корректно"
    TR["Verify Docker installation: docker --version"]="Проверьте установку Docker: docker --version"

    # === BBR sub-option prompts (t() calls) ===
    TR["   Enable force_ipv4_apt? (Y/n): "]="   Включить force_ipv4_apt? (Y/n): "
    TR["   Enable full_update_upgrade? (Y/n): "]="   Включить full_update_upgrade? (Y/n): "
    TR["   Enable fix_etc_hosts? (Y/n): "]="   Включить fix_etc_hosts? (Y/n): "
    TR["   Enable fix_dns? (Y/n): "]="   Включить fix_dns? (Y/n): "
    TR["Continue with these settings? (Y/n): "]="Продолжить с этими настройками? (Y/n): "
    TR["Do you want to reinstall Docker? (y/N): "]="Хотите переустановить Docker? (y/N): "

    # === Configuration Options header ===
    TR["   Configuration Options"]="   Параметры конфигурации"

    # === Crontab examples ===
    TR["Example:"]="Пример:"
    TR["  0 2 * * * /root/backup.sh"]="  0 2 * * * /root/backup.sh"
    TR["  */5 * * * * /root/check.sh"]="  */5 * * * * /root/check.sh"
    TR["  @reboot /root/startup.sh"]="  @reboot /root/startup.sh"

    # === UFW Docker rules menu items ===
    TR["  v4 - ufw-docker-rules-v4.sh (standard version)"]="  v4 - ufw-docker-rules-v4.sh (стандартная версия)"
    TR["  v6 - ufw-docker-rules-v6.sh (enhanced with RustDesk support, recommended)"]="  v6 - ufw-docker-rules-v6.sh (расширенная с поддержкой RustDesk, рекомендуется)"
    TR["  4 - Standard version"]="  4 - Стандартная версия"
    TR["  6 - Enhanced version with RustDesk support (recommended)"]="  6 - Расширенная версия с поддержкой RustDesk (рекомендуется)"
    TR["  1 - Install from password-protected archive (ufw-docker-rules-v4.7z)"]="  1 - Установка из защищённого паролем архива (ufw-docker-rules-v4.7z)"
    TR["      Archive contains both v4 and v6 scripts"]="      Архив содержит скрипты v4 и v6"
    TR["  2 - Install from public repository (https://raw.githubusercontent.com/civisrom/ufw-rules-docker/...)"]="  2 - Установка из публичного репозитория (https://raw.githubusercontent.com/civisrom/ufw-rules-docker/...)"

    # === Repository info ===
    TR["Repository: https://www.tataranovich.com/debian/"]="Репозиторий: https://www.tataranovich.com/debian/"
    TR["Repository: https://www.tataranovich.com/ubuntu/"]="Репозиторий: https://www.tataranovich.com/ubuntu/"
    TR["  1. ppa:ondrej/nginx - Latest Nginx builds"]="  1. ppa:ondrej/nginx — Последние сборки Nginx"
    TR["  2. ppa:git-core/ppa - Latest Git version"]="  2. ppa:git-core/ppa — Последняя версия Git"
    TR["  3. ppa:ubuntu-toolchain-r/test - Latest GCC toolchain"]="  3. ppa:ubuntu-toolchain-r/test — Последний набор GCC"
    TR["1. ppa:ondrej/nginx - Latest Nginx with HTTP/3, QUIC support"]="1. ppa:ondrej/nginx — Последний Nginx с поддержкой HTTP/3, QUIC"
    TR["2. ppa:git-core/ppa - Latest stable Git releases"]="2. ppa:git-core/ppa — Стабильные релизы Git"
    TR["3. ppa:ubuntu-toolchain-r/test - Latest GCC, G++, and toolchain"]="3. ppa:ubuntu-toolchain-r/test — Последний GCC, G++ и инструменты"

    # === Port format examples ===
    TR["  Single port:     8080"]="  Один порт:       8080"
    TR["  With protocol:   8080/tcp  or  53/udp"]="  С протоколом:    8080/tcp  или  53/udp"
    TR["  Multiple ports:  8080,8443,9000"]="  Несколько портов: 8080,8443,9000"
    TR["  Mixed:          8080/tcp,53/udp,3000"]="  Смешанные:       8080/tcp,53/udp,3000"

    # === BBR header ===
    TR["   Advanced Network Optimization (BBR)"]="   Расширенная сетевая оптимизация (BBR)"

    # === Installation phase ===
    TR["Continuing with default settings (non-interactive mode)..."]="Продолжение с настройками по умолчанию (неинтерактивный режим)..."
    TR["Starting installation..."]="Начало установки..."
    TR["Package lists updated successfully"]="Список пакетов успешно обновлён"
    TR["CRITICAL: Failed to update package lists"]="КРИТИЧЕСКАЯ ОШИБКА: не удалось обновить список пакетов"
    TR["Installation cannot continue"]="Установка не может быть продолжена"
    TR["Installing common packages for Debian..."]="Установка общих пакетов для Debian..."
    TR["Installing Debian-specific packages..."]="Установка пакетов, специфичных для Debian..."
    TR["Some Debian-specific packages may not be available"]="Некоторые пакеты для Debian могут быть недоступны"
    TR["No Debian-specific packages to install"]="Нет специфичных пакетов Debian для установки"
    TR["Installing common packages for Ubuntu..."]="Установка общих пакетов для Ubuntu..."
    TR["Installing Ubuntu-specific packages..."]="Установка пакетов, специфичных для Ubuntu..."
    TR["Some Ubuntu-specific packages may not be available"]="Некоторые пакеты для Ubuntu могут быть недоступны"
    TR["No Ubuntu-specific packages to install"]="Нет специфичных пакетов Ubuntu для установки"

    # === RustDesk installation ===
    TR["Installing RustDesk server in Docker..."]="Установка сервера RustDesk в Docker..."
    TR["Creating directory: %s..."]="Создание каталога: %s..."
    TR["Directory created successfully"]="Каталог успешно создан"
    TR["CRITICAL: Failed to create directory %s"]="КРИТИЧЕСКАЯ ОШИБКА: не удалось создать каталог %s"
    TR["Downloading docker-compose.yml..."]="Загрузка docker-compose.yml..."
    TR["docker-compose.yml downloaded successfully"]="docker-compose.yml успешно загружен"
    TR["CRITICAL: Failed to download docker-compose.yml"]="КРИТИЧЕСКАЯ ОШИБКА: не удалось загрузить docker-compose.yml"
    TR["Downloading systemd service file..."]="Загрузка файла сервиса systemd..."
    TR["Service file downloaded successfully"]="Файл сервиса успешно загружен"
    TR["CRITICAL: Failed to download service file"]="КРИТИЧЕСКАЯ ОШИБКА: не удалось загрузить файл сервиса"
    TR["Reloading systemd daemon..."]="Перезагрузка демона systemd..."
    TR["Systemd daemon reloaded successfully"]="Демон systemd успешно перезагружен"
    TR["CRITICAL: Failed to reload systemd daemon"]="КРИТИЧЕСКАЯ ОШИБКА: не удалось перезагрузить демон systemd"
    TR["Enabling rustdesk-compose service..."]="Включение сервиса rustdesk-compose..."
    TR["Service enabled successfully"]="Сервис успешно включён"
    TR["CRITICAL: Failed to enable rustdesk-compose service"]="КРИТИЧЕСКАЯ ОШИБКА: не удалось включить сервис rustdesk-compose"
    TR["Docker found, starting rustdesk-compose service..."]="Docker найден, запуск сервиса rustdesk-compose..."
    TR["RustDesk service started successfully"]="Сервис RustDesk успешно запущен"
    TR["RustDesk service is running"]="Сервис RustDesk работает"
    TR["RustDesk service is enabled but not running (Docker might not be installed yet)"]="Сервис RustDesk включён, но не запущен (Docker может быть ещё не установлен)"
    TR["Service will start automatically after Docker installation"]="Сервис запустится автоматически после установки Docker"
    TR["Failed to start rustdesk-compose service"]="Не удалось запустить сервис rustdesk-compose"
    TR["Docker not installed yet - RustDesk service will start after Docker is installed"]="Docker ещё не установлен — сервис RustDesk запустится после установки Docker"
    TR["RustDesk installation completed"]="Установка RustDesk завершена"
    TR["Directory: %s"]="Каталог: %s"
    TR["Service: rustdesk-compose.service"]="Сервис: rustdesk-compose.service"

    # === User creation details ===
    TR["Creating new user: %s"]="Создание нового пользователя: %s"
    TR["SSH key added to %s/.ssh/authorized_keys"]="SSH ключ добавлен в %s/.ssh/authorized_keys"

    # === Repository configuration details ===
    TR["Original sources.list backed up"]="Резервная копия sources.list создана"
    TR["Configured Debian 13 (Trixie) repositories without backports"]="Настроены репозитории Debian 13 (Trixie) без backports"
    TR["Configured Debian %s (%s) repositories with backports"]="Настроены репозитории Debian %s (%s) с backports"
    TR["Debian repositories configured"]="Репозитории Debian настроены"
    TR["Main sources.list cleared (repositories moved to sources.list.d)"]="Основной sources.list очищен (репозитории перемещены в sources.list.d)"
    TR["Existing ubuntu.sources backed up"]="Резервная копия ubuntu.sources создана"
    TR["Ubuntu repositories configured in: %s"]="Репозитории Ubuntu настроены в: %s"
    TR["Format: DEB822 (ubuntu.sources)"]="Формат: DEB822 (ubuntu.sources)"
    TR["Codename: %s"]="Кодовое имя: %s"
    TR["Repositories enabled: main, restricted, universe, multiverse"]="Включены репозитории: main, restricted, universe, multiverse"

    # === Ubuntu PPA details ===
    TR["Adding Ubuntu PPA repositories..."]="Добавление PPA-репозиториев Ubuntu..."
    TR["Installing software-properties-common..."]="Установка software-properties-common..."
    TR["Adding ppa:ondrej/nginx..."]="Добавление ppa:ondrej/nginx..."
    TR["Press ENTER when prompted to confirm the PPA addition"]="Нажмите ENTER при запросе подтверждения добавления PPA"
    TR["Ondrej Nginx PPA added successfully"]="Ondrej Nginx PPA успешно добавлен"
    TR["Failed to add Ondrej Nginx PPA, continuing..."]="Не удалось добавить Ondrej Nginx PPA, продолжаем..."
    TR["Adding ppa:git-core/ppa..."]="Добавление ppa:git-core/ppa..."
    TR["Git Core PPA added successfully"]="Git Core PPA успешно добавлен"
    TR["Failed to add Git Core PPA, continuing..."]="Не удалось добавить Git Core PPA, продолжаем..."
    TR["Adding ppa:ubuntu-toolchain-r/test..."]="Добавление ppa:ubuntu-toolchain-r/test..."
    TR["Ubuntu Toolchain PPA added successfully"]="Ubuntu Toolchain PPA успешно добавлен"
    TR["Failed to add Ubuntu Toolchain PPA, continuing..."]="Не удалось добавить Ubuntu Toolchain PPA, продолжаем..."
    TR["Updating package lists with new PPA repositories..."]="Обновление списка пакетов с новыми PPA..."
    TR["Added PPA repositories:"]="Добавленные PPA-репозитории:"

    TR["Failed to update package lists after adding PPAs"]="Не удалось обновить список пакетов после добавления PPA"

    # === Tataranovich Ubuntu details ===
    TR["Configuring Tataranovich repository for Ubuntu..."]="Настройка репозитория Tataranovich для Ubuntu..."
    TR["Installing prerequisites for Tataranovich repository..."]="Установка необходимых компонентов для репозитория Tataranovich..."
    TR["Downloading Tataranovich GPG key..."]="Загрузка GPG ключа Tataranovich..."
    TR["GPG key downloaded successfully"]="GPG ключ успешно загружен"
    TR["Failed to download Tataranovich GPG key"]="Не удалось загрузить GPG ключ Tataranovich"
    TR["Skipping Tataranovich repository configuration"]="Пропуск настройки репозитория Tataranovich"
    TR["Tataranovich repository added: /etc/apt/sources.list.d/tataranovich-ubuntu.list"]="Репозиторий Tataranovich добавлен: /etc/apt/sources.list.d/tataranovich-ubuntu.list"
    TR["Updating package lists with Tataranovich repository..."]="Обновление списка пакетов с репозиторием Tataranovich..."
    TR["Installing Midnight Commander from Tataranovich repository..."]="Установка Midnight Commander из репозитория Tataranovich..."
    TR["Midnight Commander installed successfully from Tataranovich repository"]="Midnight Commander успешно установлен из репозитория Tataranovich"
    TR["Installed: %s"]="Установлено: %s"
    TR["Failed to install mc from Tataranovich repository"]="Не удалось установить mc из репозитория Tataranovich"
    TR["Installing mc from standard repositories..."]="Установка mc из стандартных репозиториев..."
    TR["Failed to install mc"]="Не удалось установить mc"
    TR["Failed to update package lists with Tataranovich repository"]="Не удалось обновить список пакетов с репозиторием Tataranovich"

    # === Tataranovich Debian details ===
    TR["Configuring Tataranovich repository for Debian 12..."]="Настройка репозитория Tataranovich для Debian 12..."
    TR["Tataranovich repository added: /etc/apt/sources.list.d/tataranovich.list"]="Репозиторий Tataranovich добавлен: /etc/apt/sources.list.d/tataranovich.list"
    TR["Installing Midnight Commander from standard repositories..."]="Установка Midnight Commander из стандартных репозиториев..."

    # === sysctl details ===
    TR["Configuring system parameters (sysctl.conf)..."]="Настройка системных параметров (sysctl.conf)..."

    # === GRUB details ===
    TR["IPv6 disable parameter already present in GRUB config"]="Параметр отключения IPv6 уже присутствует в конфигурации GRUB"
    TR["Added ipv6.disable=1 to GRUB_CMDLINE_LINUX_DEFAULT"]="Добавлено ipv6.disable=1 в GRUB_CMDLINE_LINUX_DEFAULT"
    TR["Added GRUB_CMDLINE_LINUX_DEFAULT with ipv6.disable=1"]="Добавлено GRUB_CMDLINE_LINUX_DEFAULT с ipv6.disable=1"
    TR["Updating GRUB configuration..."]="Обновление конфигурации GRUB..."
    TR["GRUB configuration updated successfully"]="Конфигурация GRUB успешно обновлена"
    TR["Failed to update GRUB configuration"]="Не удалось обновить конфигурацию GRUB"
    TR["Check /tmp/grub-update.log for details"]="Подробности в /tmp/grub-update.log"
    TR["Attempting to restore GRUB config from backup..."]="Попытка восстановления конфигурации GRUB из резервной копии..."
    TR["GRUB config restored from backup"]="Конфигурация GRUB восстановлена из резервной копии"
    TR["Current GRUB_CMDLINE_LINUX_DEFAULT:"]="Текущий GRUB_CMDLINE_LINUX_DEFAULT:"
    TR["Skipping IPv6 GRUB disable (not requested)"]="Пропуск отключения IPv6 через GRUB (не запрошено)"

    # === Network interfaces details ===
    TR["  sudo systemctl restart networking"]="  sudo systemctl restart networking"
    TR["  OR reboot the system"]="  ИЛИ перезагрузите систему"

    # === SSH details ===
    TR["SSH parameter set: %s %s"]="Параметр SSH установлен: %s %s"
    TR["SSH parameter added: %s %s"]="Параметр SSH добавлен: %s %s"
    TR["PermitEmptyPasswords set to 'no' for security reasons"]="PermitEmptyPasswords установлен в 'no' из соображений безопасности"
    TR["SSH configuration is valid"]="Конфигурация SSH корректна"
    TR["SSH service restarted (sshd)"]="Служба SSH перезапущена (sshd)"
    TR["SSH service restarted (ssh)"]="Служба SSH перезапущена (ssh)"
    TR["SSH service restarted (service ssh)"]="Служба SSH перезапущена (service ssh)"
    TR["SSH service restarted (service sshd)"]="Служба SSH перезапущена (service sshd)"
    TR["Please restart SSH manually: sudo systemctl restart ssh"]="Перезапустите SSH вручную: sudo systemctl restart ssh"
    TR["SSH configuration test failed!"]="Проверка конфигурации SSH не пройдена!"
    TR["Restoring backup..."]="Восстановление из резервной копии..."
    TR["SSH configuration restored from backup"]="Конфигурация SSH восстановлена из резервной копии"
    TR["No backup found to restore"]="Резервная копия для восстановления не найдена"

    # === UFW details ===
    TR["UFW rule added: Allow port %s/tcp (default)"]="Правило UFW добавлено: разрешить порт %s/tcp (по умолчанию)"
    TR["Invalid port format: %s. Expected: PORT or PORT/PROTOCOL. Skipping."]="Неверный формат порта: %s. Ожидается: ПОРТ или ПОРТ/ПРОТОКОЛ. Пропуск."
    TR["Custom ports configuration completed"]="Настройка пользовательских портов завершена"
    TR["Configuring ICMP blocking in UFW..."]="Настройка блокировки ICMP в UFW..."
    TR["ICMP blocking is already configured in before.rules"]="Блокировка ICMP уже настроена в before.rules"
    TR["Skipping ICMP configuration to avoid duplicates"]="Пропуск настройки ICMP во избежание дубликатов"
    TR["Original before.rules backed up"]="Резервная копия before.rules создана"
    TR["Found ICMP section in before.rules"]="Найден раздел ICMP в before.rules"
    TR["Restored original file permissions: %s"]="Восстановлены исходные права файла: %s"
    TR["Set default file permissions: 640"]="Установлены права файла по умолчанию: 640"
    TR["ICMP blocking configured successfully"]="Блокировка ICMP успешно настроена"
    TR["Failed to modify before.rules (temporary file is empty)"]="Не удалось изменить before.rules (временный файл пуст)"
    TR["ICMP section not found in before.rules"]="Раздел ICMP не найден в before.rules"
    TR["Skipping ICMP blocking configuration"]="Пропуск настройки блокировки ICMP"
    TR["ICMP (ping) requests are now blocked"]="ICMP (ping) запросы теперь заблокированы"
    TR["Your server will not respond to ping"]="Ваш сервер не будет отвечать на ping"
    TR["ICMP blocking not requested - server will respond to ping"]="Блокировка ICMP не запрошена — сервер будет отвечать на ping"

    # === Docker details ===
    TR["Docker is already installed: %s"]="Docker уже установлен: %s"
    TR["Skipping Docker installation"]="Пропуск установки Docker"
    TR["Reinstalling Docker..."]="Переустановка Docker..."
    TR["To activate docker group without logout, user can run: newgrp docker"]="Для активации группы docker без выхода, пользователь может выполнить: newgrp docker"
    TR["Users need to log out and log back in (or run 'newgrp docker') for docker group to take effect"]="Пользователям нужно выйти и войти (или выполнить 'newgrp docker') для активации группы docker"
    TR["Docker version: %s"]="Версия Docker: %s"
    TR["Docker Compose version: %s"]="Версия Docker Compose: %s"

    # === ufw-docker details ===
    TR["ufw-docker downloaded successfully"]="ufw-docker успешно загружен"
    TR["Configuring ufw-docker..."]="Настройка ufw-docker..."
    TR["ufw-docker configured successfully"]="ufw-docker успешно настроен"
    TR["Note: Docker is not installed. ufw-docker will be ready when you install Docker."]="Примечание: Docker не установлен. ufw-docker будет готов после установки Docker."
    TR["Failed to download ufw-docker"]="Не удалось загрузить ufw-docker"

    # === Go details ===
    TR["Unsupported architecture: %s"]="Неподдерживаемая архитектура: %s"
    TR["Go installation skipped"]="Установка Go пропущена"
    TR["Detected architecture: %s (Go architecture: %s)"]="Обнаружена архитектура: %s (архитектура Go: %s)"
    TR["Downloading Go from: %s"]="Загрузка Go из: %s"
    TR["Removing old Go installation..."]="Удаление старой установки Go..."
    TR["Extracting Go..."]="Извлечение Go..."
    TR["Go extracted to /usr/local/go"]="Go извлечён в /usr/local/go"
    TR["Configuring Go environment for %s..."]="Настройка окружения Go для %s..."
    TR["Go PATH added to %s"]="Go PATH добавлен в %s"
    TR["Go PATH already configured in %s"]="Go PATH уже настроен в %s"
    TR["Go binary location: /usr/local/go/bin/go"]="Расположение Go: /usr/local/go/bin/go"
    TR["User %s can use Go after reloading shell or running: source %s"]="Пользователь %s сможет использовать Go после перезагрузки оболочки или выполнения: source %s"
    TR["Skipping Go installation (not requested)"]="Пропуск установки Go (не запрошено)"

    # === ipset details ===
    TR["Building and installing latest version of ipset..."]="Сборка и установка последней версии ipset..."
    TR["Kernel headers not found at: %s"]="Заголовки ядра не найдены: %s"
    TR["Installing kernel headers..."]="Установка заголовков ядра..."
    TR["Kernel headers installed successfully"]="Заголовки ядра успешно установлены"
    TR["Failed to install kernel headers"]="Не удалось установить заголовки ядра"
    TR["ipset compilation requires kernel headers"]="Для компиляции ipset необходимы заголовки ядра"
    TR["Try manually: sudo apt-get install linux-headers-%s"]="Попробуйте вручную: sudo apt-get install linux-headers-%s"
    TR["Skipping ipset installation"]="Пропуск установки ipset"
    TR["Kernel headers found: %s"]="Заголовки ядра найдены: %s"
    TR["Could not fetch latest ipset version, using fallback: 7.24"]="Не удалось получить версию ipset, используется: 7.24"

    # === Python venv details ===
    TR["Created directory: %s"]="Создан каталог: %s"
    TR["Creating venv at: %s"]="Создание venv в: %s"
    TR["Virtual environment created successfully"]="Виртуальное окружение успешно создано"
    TR["Installing Python packages..."]="Установка Python-пакетов..."
    TR["Python packages installed successfully"]="Python-пакеты успешно установлены"
    TR["Virtual environment location: %s"]="Расположение виртуального окружения: %s"
    TR["To activate: source %s/bin/activate"]="Для активации: source %s/bin/activate"
    TR["Skipping Python virtual environment creation (not requested)"]="Пропуск создания виртуального окружения Python (не запрошено)"

    # === Crontab details ===
    TR["Configured crontab:"]="Настроенный crontab:"

    # === MOTD details ===
    TR["Installing custom MOTD (Message of the Day)..."]="Установка пользовательского MOTD (сообщения дня)..."
    TR["Downloading MOTD installation script for %s..."]="Загрузка скрипта установки MOTD для %s..."
    TR["Running MOTD installation script..."]="Запуск скрипта установки MOTD..."
    TR["Applying MOTD post-installation fixes..."]="Применение исправлений после установки MOTD..."
    TR["Set executable permissions on MOTD scripts and directory"]="Установлены права на выполнение для скриптов MOTD"
    TR["Enabled UsePAM in SSH config (required for MOTD)"]="Включён UsePAM в конфигурации SSH (требуется для MOTD)"
    TR["Enabled PrintMotd in SSH config"]="Включён PrintMotd в конфигурации SSH"
    TR["Added PrintMotd to SSH config"]="Добавлен PrintMotd в конфигурацию SSH"
    TR["Disabled PrintLastLog to avoid conflicts"]="Отключён PrintLastLog во избежание конфликтов"
    TR["Restarting SSH service for MOTD changes..."]="Перезапуск службы SSH для применения MOTD..."
    TR["SSH service restarted successfully"]="Служба SSH успешно перезапущена"
    TR["Could not restart SSH automatically, please restart manually"]="Не удалось перезапустить SSH автоматически, перезапустите вручную"
    TR["Disabled static /etc/motd file"]="Отключён статический файл /etc/motd"
    TR["PAM MOTD module not found in %s"]="Модуль PAM MOTD не найден в %s"
    TR["Adding pam_motd.so to PAM configuration..."]="Добавление pam_motd.so в конфигурацию PAM..."
    TR["PAM MOTD configuration added"]="Конфигурация PAM MOTD добавлена"
    TR["PAM MOTD module already configured"]="Модуль PAM MOTD уже настроен"
    TR["PAM SSH config not found: %s"]="Конфигурация PAM SSH не найдена: %s"
    TR["run-parts not found, installing debianutils..."]="run-parts не найден, установка debianutils..."
    TR["Failed to install debianutils"]="Не удалось установить debianutils"
    TR["/run directory does not exist (unusual)"]="Каталог /run не существует (необычно)"
    TR["/run/motd.dynamic exists as directory, removing..."]="/run/motd.dynamic является каталогом, удаление..."
    TR["Removed incorrect directory /run/motd.dynamic"]="Удалён некорректный каталог /run/motd.dynamic"
    TR["Prepared /run/motd.dynamic file"]="Подготовлен файл /run/motd.dynamic"
    TR["Testing MOTD generation..."]="Тестирование генерации MOTD..."
    TR["MOTD scripts executed successfully"]="Скрипты MOTD выполнены успешно"
    TR["MOTD content generated successfully"]="Содержимое MOTD успешно сгенерировано"
    TR["MOTD scripts ran but produced no output"]="Скрипты MOTD выполнились, но не выдали вывод"
    TR["Some MOTD scripts may have errors"]="Некоторые скрипты MOTD могут содержать ошибки"
    TR["Error details:"]="Подробности ошибки:"
    TR["Cannot test MOTD without run-parts"]="Невозможно протестировать MOTD без run-parts"
    TR["   MOTD Preview (will be shown on SSH login)"]="   Предварительный просмотр MOTD (будет показан при SSH-входе)"
    TR["Cannot display MOTD preview"]="Невозможно отобразить предварительный просмотр MOTD"
    TR["MOTD configuration completed successfully!"]="Настройка MOTD успешно завершена!"
    TR["What was configured:"]="Что было настроено:"
    TR["  ✓ MOTD scripts installed in /etc/update-motd.d/"]="  ✓ Скрипты MOTD установлены в /etc/update-motd.d/"
    TR["  ✓ SSH configured to display MOTD"]="  ✓ SSH настроен для отображения MOTD"
    TR["  ✓ PAM configured for MOTD"]="  ✓ PAM настроен для MOTD"
    TR["  ✓ Static MOTD file disabled"]="  ✓ Статический файл MOTD отключён"
    TR["Important: MOTD will be visible on your NEXT SSH login"]="Важно: MOTD будет видно при СЛЕДУЮЩЕМ входе по SSH"
    TR["To test now: exit and reconnect via SSH"]="Для проверки: выйдите и переподключитесь по SSH"
    TR["MOTD installation completed with warnings"]="Установка MOTD завершена с предупреждениями"
    TR["Failed to download MOTD installation script"]="Не удалось загрузить скрипт установки MOTD"

    # === Custom UFW Docker rules details ===
    TR["Installing custom UFW Docker rules (v%s)..."]="Установка пользовательских правил UFW Docker (v%s)..."
    TR["Installing from public repository..."]="Установка из публичного репозитория..."
    TR["Downloading script from repository..."]="Загрузка скрипта из репозитория..."
    TR["Script downloaded successfully"]="Скрипт успешно загружен"
    TR["Configuring script to use custom SSH port: %s"]="Настройка скрипта с пользовательским портом SSH: %s"
    TR["SSH port configured successfully in ufw-docker-rules-v%s.sh"]="Порт SSH успешно настроен в ufw-docker-rules-v%s.sh"
    TR["Script installed with executable permissions"]="Скрипт установлен с правами на выполнение"
    TR["Executing custom UFW Docker rules script..."]="Запуск скрипта правил UFW для Docker..."
    TR["Using custom SSH port: %s"]="Используется пользовательский порт SSH: %s"
    TR["  Custom UFW Docker Rules Script Output (v%s)"]="  Вывод скрипта правил UFW Docker (v%s)"
    TR["Custom UFW Docker rules applied successfully"]="Пользовательские правила UFW Docker успешно применены"
    TR["Custom UFW Docker rules script completed with warnings"]="Скрипт правил UFW Docker завершён с предупреждениями"
    TR["Failed to download script from repository"]="Не удалось загрузить скрипт из репозитория"
    TR["URL: %s"]="URL: %s"
    TR["Installing from password-protected archive..."]="Установка из защищённого паролем архива..."
    TR["Installing p7zip-full for archive extraction..."]="Установка p7zip-full для извлечения архива..."
    TR["p7zip-full installed successfully"]="p7zip-full успешно установлен"
    TR["CRITICAL: Failed to install p7zip-full"]="КРИТИЧЕСКАЯ ОШИБКА: не удалось установить p7zip-full"
    TR["Downloading custom UFW rules archive..."]="Загрузка архива правил UFW..."
    TR["Archive downloaded successfully"]="Архив успешно загружен"
    TR["Extracting archive..."]="Извлечение архива..."
    TR["Archive extracted successfully"]="Архив успешно извлечён"
    TR["Found script: %s"]="Найден скрипт: %s"
    TR["Installing script to %s..."]="Установка скрипта в %s..."
    TR["Script file not found in archive: %s"]="Файл скрипта не найден в архиве: %s"
    TR["Checked locations:"]="Проверенные расположения:"
    TR["  - %s/%s"]="  - %s/%s"
    TR["  - %s/opt/%s"]="  - %s/opt/%s"
    TR["  - %s/opt/scripts/%s"]="  - %s/opt/scripts/%s"
    TR["Archive deleted"]="Архив удалён"
    TR["Failed to extract archive. Check if password is correct."]="Не удалось извлечь архив. Проверьте правильность пароля."
    TR["Password authentication failed or archive is corrupted"]="Ошибка аутентификации по паролю или архив повреждён"
    TR["Failed to download custom UFW rules archive"]="Не удалось загрузить архив правил UFW"
    TR["Skipping custom UFW Docker rules (not requested)"]="Пропуск пользовательских правил UFW Docker (не запрошено)"

    # === opt.7z extraction details ===
    TR["   Extracting opt.7z Archive to /opt"]="   Извлечение архива opt.7z в /opt"
    TR["Cannot extract opt.7z archive"]="Невозможно извлечь архив opt.7z"
    TR["Downloading opt.7z archive for /opt files..."]="Загрузка архива opt.7z для файлов /opt..."
    TR["opt.7z archive downloaded successfully"]="Архив opt.7z успешно загружен"
    TR["opt.7z archive extracted successfully"]="Архив opt.7z успешно извлечён"
    TR["Copying files and folders to /opt..."]="Копирование файлов и папок в /opt..."
    TR["Files copied to /opt successfully"]="Файлы успешно скопированы в /opt"
    TR["Setting executable permissions for scripts in /opt/scripts..."]="Установка прав на выполнение для скриптов в /opt/scripts..."
    TR["Made %s file(s) executable in /opt/scripts"]="Сделано %s файл(ов) исполняемыми в /opt/scripts"
    TR["Contents copied to /opt:"]="Содержимое скопировано в /opt:"
    TR["opt.7z archive is empty"]="Архив opt.7z пуст"
    TR["Failed to extract opt.7z archive. Check if password is correct."]="Не удалось извлечь архив opt.7z. Проверьте правильность пароля."
    TR["Failed to download opt.7z archive"]="Не удалось загрузить архив opt.7z"
    TR["Skipping opt.7z extraction (not requested)"]="Пропуск извлечения opt.7z (не запрошено)"

    # === BBR Optimizer details ===
    TR["   Running BBR Network Optimizer"]="   Запуск оптимизатора сети BBR"
    TR["Downloading BBR Network Optimizer script..."]="Загрузка скрипта оптимизатора сети BBR..."
    TR["BBR script downloaded successfully"]="Скрипт BBR успешно загружен"
    TR["Configuring BBR script options..."]="Настройка параметров скрипта BBR..."
    TR["Applying BBR network optimizations..."]="Применение сетевых оптимизаций BBR..."
    TR["Running BBR Network Optimizer with selected options..."]="Запуск оптимизатора сети BBR с выбранными параметрами..."
    TR["Options: Force IPv4: %s, Full Update: %s, Fix Hosts: %s, Fix DNS: %s"]="Параметры: Принудительный IPv4: %s, Полное обновление: %s, Исправление Hosts: %s, Исправление DNS: %s"
    TR["Failed to download BBR Network Optimizer script"]="Не удалось загрузить скрипт оптимизатора сети BBR"
    TR["You can manually run it later from: %s"]="Вы можете запустить его вручную позже: %s"

    # === Final summary ===
    TR["System setup completed successfully!"]="Настройка системы успешно завершена!"
    TR["Summary:"]="Сводка:"
    TR["- Packages installed"]="- Пакеты установлены"
    TR["- RustDesk Server: Installed and enabled"]="- Сервер RustDesk: установлен и включён"
    TR["  Directory: /opt/rustdesk"]="  Каталог: /opt/rustdesk"
    TR["  Service: rustdesk-compose.service"]="  Сервис: rustdesk-compose.service"
    TR["  Status: Running"]="  Статус: Работает"
    TR["  Status: Enabled (will start with Docker)"]="  Статус: Включён (запустится с Docker)"
    TR["- RustDesk Server: Installation attempted but service not enabled"]="- Сервер RustDesk: попытка установки, но сервис не включён"
    TR["- RustDesk Server: Not installed"]="- Сервер RustDesk: не установлен"
    TR["- Root password: SET"]="- Пароль root: УСТАНОВЛЕН"
    TR["- Root password: NOT SET"]="- Пароль root: НЕ УСТАНОВЛЕН"
    TR["- New user created: %s"]="- Создан новый пользователь: %s"
    TR["  - SSH key configured"]="  - SSH ключ настроен"
    TR["  - zsh and Oh My Zsh installed"]="  - zsh и Oh My Zsh установлены"
    TR["- New user: NOT CREATED"]="- Новый пользователь: НЕ СОЗДАН"
    TR["- Crontab configured for root"]="- Crontab настроен для root"
    TR["- Crontab: NOT CONFIGURED"]="- Crontab: НЕ НАСТРОЕН"
    TR["- SSH configured (Port: %s, AllowUsers: %s)"]="- SSH настроен (Порт: %s, AllowUsers: %s)"
    TR["  - PubkeyAuthentication: %s"]="  - PubkeyAuthentication: %s"
    TR["  - PasswordAuthentication: %s"]="  - PasswordAuthentication: %s"
    TR["  - PermitEmptyPasswords: %s (security enforced)"]="  - PermitEmptyPasswords: %s (принудительная безопасность)"
    TR["  - PermitRootLogin: %s"]="  - PermitRootLogin: %s"
    TR["- SSH: NOT CONFIGURED"]="- SSH: НЕ НАСТРОЕН"
    TR["- Python venv created at: %s"]="- Python venv создан в: %s"
    TR["- Python venv: NOT CREATED"]="- Python venv: НЕ СОЗДАН"
    TR["- System parameters optimized (sysctl.conf)"]="- Системные параметры оптимизированы (sysctl.conf)"
    TR["- sysctl: SKIPPED"]="- sysctl: ПРОПУЩЕН"
    TR["- IPv6 disabled via GRUB (kernel level)"]="- IPv6 отключён через GRUB (уровень ядра)"
    TR["  Note: Requires reboot to take effect"]="  Примечание: требуется перезагрузка"
    TR["- Debian repositories configured"]="- Репозитории Debian настроены"
    TR["- Tataranovich repository (Debian): ADDED (custom mc)"]="- Репозиторий Tataranovich (Debian): ДОБАВЛЕН (сборка mc)"
    TR["- Ubuntu repositories configured (main, restricted, universe, multiverse)"]="- Репозитории Ubuntu настроены (main, restricted, universe, multiverse)"
    TR["- Tataranovich repository (Ubuntu): ADDED (custom mc)"]="- Репозиторий Tataranovich (Ubuntu): ДОБАВЛЕН (сборка mc)"
    TR["- Ubuntu PPA repositories:"]="- PPA-репозитории Ubuntu:"
    TR["  ✓ ppa:ondrej/nginx (Latest Nginx)"]="  ✓ ppa:ondrej/nginx (последний Nginx)"
    TR["  ✓ ppa:git-core/ppa (Latest Git)"]="  ✓ ppa:git-core/ppa (последний Git)"
    TR["  ✓ ppa:ubuntu-toolchain-r/test (Latest GCC)"]="  ✓ ppa:ubuntu-toolchain-r/test (последний GCC)"
    TR["- IPv6 commented in /etc/network/interfaces"]="- IPv6 закомментирован в /etc/network/interfaces"
    TR["  Note: May require network restart or reboot"]="  Примечание: может потребоваться перезапуск сети или перезагрузка"
    TR["- UFW firewall configured and enabled"]="- Файрвол UFW настроен и включён"
    TR["- ICMP (ping) blocking: ENABLED"]="- Блокировка ICMP (ping): ВКЛЮЧЕНА"
    TR["- ICMP (ping) blocking: DISABLED (server responds to ping)"]="- Блокировка ICMP (ping): ОТКЛЮЧЕНА (сервер отвечает на ping)"
    TR["- Custom UFW ports: %s"]="- Пользовательские порты UFW: %s"
    TR["- UFW: SKIPPED"]="- UFW: ПРОПУЩЕН"
    TR["- Docker: Installed"]="- Docker: установлен"
    TR["- Docker: Not installed"]="- Docker: не установлен"
    TR["- Docker installation may have failed"]="- Установка Docker могла завершиться с ошибкой"
    TR["- ufw-docker: Installed and configured"]="- ufw-docker: установлен и настроен"
    TR["- ufw-docker: Installation attempted but not found"]="- ufw-docker: попытка установки, но не найден"
    TR["- ufw-docker: Not installed"]="- ufw-docker: не установлен"
    TR["- Go: Installed (%s)"]="- Go: установлен (%s)"
    TR["  Configured in: %s/.zshrc"]="  Настроен в: %s/.zshrc"
    TR["  Configured in: %s/.bashrc"]="  Настроен в: %s/.bashrc"
    TR["- Go: Installation attempted but not found"]="- Go: попытка установки, но не найден"
    TR["- Go: Not installed"]="- Go: не установлен"
    TR["- ipset: Installed (%s)"]="- ipset: установлен (%s)"
    TR["- ipset: Installation attempted but not found"]="- ipset: попытка установки, но не найден"
    TR["- ipset: Not installed"]="- ipset: не установлен"
    TR["- Custom MOTD: Installed"]="- Пользовательский MOTD: установлен"
    TR["  Note: MOTD will be visible on next SSH login"]="  Примечание: MOTD будет виден при следующем входе по SSH"
    TR["- Custom MOTD: Not installed"]="- Пользовательский MOTD: не установлен"
    TR["- Custom UFW Docker rules: Installed and executed (v%s, %s)"]="- Правила UFW Docker: установлены и выполнены (v%s, %s)"
    TR["  Script location: %s"]="  Расположение скрипта: %s"
    TR["  Custom SSH port configured: %s"]="  Пользовательский порт SSH: %s"
    TR["  Archive extracted to: /opt"]="  Архив извлечён в: /opt"
    TR["  Executable scripts in /opt/scripts: %s"]="  Исполняемые скрипты в /opt/scripts: %s"
    TR["- Custom UFW Docker rules: Installation attempted but failed"]="- Правила UFW Docker: попытка установки не удалась"
    TR["- Custom UFW Docker rules: Not installed"]="- Правила UFW Docker: не установлены"
    TR["- BBR Network Optimizer: Executed"]="- Оптимизатор сети BBR: выполнен"
    TR["- BBR Network Optimizer: Not executed"]="- Оптимизатор сети BBR: не выполнен"

    # === Backup files info ===
    TR["Backup files saved with timestamp (format: filename.backup.YYYYMMDD-HHMMSS~):"]="Резервные копии сохранены с меткой времени (формат: filename.backup.YYYYMMDD-HHMMSS~):"

    # === Post-installation steps ===
    TR["Recommended next steps:"]="Рекомендуемые следующие шаги:"
    TR["%s. Test SSH connection with new user: ssh %s@hostname"]="  %s. Проверьте SSH подключение нового пользователя: ssh %s@hostname"
    TR["   Note: zsh is configured, log in to see Oh My Zsh"]="   Примечание: zsh настроен, войдите для проверки Oh My Zsh"
    TR["%s. IMPORTANT: SSH port changed to %s"]="  %s. ВАЖНО: порт SSH изменён на %s"
    TR["   Make sure to update your SSH client before logging out!"]="   Обязательно обновите настройки SSH-клиента перед выходом!"
    TR["   Test connection: ssh -p %s user@host"]="   Проверьте подключение: ssh -p %s user@host"
    TR["%s. Review UFW status: sudo ufw status verbose"]="  %s. Проверьте статус UFW: sudo ufw status verbose"
    TR["%s. Check sysctl: sysctl net.ipv4.tcp_congestion_control"]="  %s. Проверьте sysctl: sysctl net.ipv4.tcp_congestion_control"
    TR["%s. Activate Python venv: source %s/bin/activate"]="  %s. Активируйте Python venv: source %s/bin/activate"
    TR["%s. User %s needs to log out and back in to use Docker without sudo"]="  %s. Пользователь %s должен выйти и войти для использования Docker без sudo"
    TR["%s. Check crontab: sudo crontab -l"]="  %s. Проверьте crontab: sudo crontab -l"
    TR["%s. Check GRUB IPv6 disable after reboot: cat /proc/cmdline | grep ipv6"]="  %s. Проверьте отключение IPv6 через GRUB после перезагрузки: cat /proc/cmdline | grep ipv6"
    TR["%s. Test MOTD: Reconnect via SSH to see custom MOTD"]="  %s. Проверьте MOTD: переподключитесь по SSH для проверки"
    TR["%s. Reboot system to apply all changes: sudo reboot"]="  %s. Перезагрузите систему для применения всех изменений: sudo reboot"

    # === Useful commands ===
    TR["su - %s"]="su - %s"

    # === Configuration Summary inline values ===
    TR["  RustDesk Server: "]="  Сервер RustDesk: "
    TR["  Root password: "]="  Пароль root: "
    TR["  New user: "]="  Новый пользователь: "
    TR["    - SSH key: "]="    - SSH ключ: "
    TR["    - zsh: "]="    - zsh: "
    TR["  Crontab: "]="  Crontab: "
    TR["  SSH Configuration: "]="  Настройка SSH: "
    TR["    - PubkeyAuthentication: %s"]="    - PubkeyAuthentication: %s"
    TR["    - PasswordAuthentication: %s"]="    - PasswordAuthentication: %s"
    TR["    - PermitEmptyPasswords: %s"]="    - PermitEmptyPasswords: %s"
    TR["    - PermitRootLogin: %s"]="    - PermitRootLogin: %s"
    TR["  Python venv: "]="  Python venv: "
    TR["  Docker: "]="  Docker: "
    TR["  ufw-docker: "]="  ufw-docker: "
    TR["  Go language: "]="  Go: "
    TR["  ipset: "]="  ipset: "
    TR["  UFW Firewall: "]="  UFW: "
    TR["  Block ICMP (ping): "]="  Блокировка ICMP (ping): "
    TR["  Custom UFW Docker rules: YES (v%s, %s)"]="  Правила UFW Docker: ДА (v%s, %s)"
    TR["    - Extract opt.7z to /opt: "]="    - Извлечь opt.7z в /opt: "
    TR["    - Custom SSH port: %s"]="    - Порт SSH: %s"
    TR["  Custom UFW Docker rules: NO"]="  Правила UFW Docker: НЕТ"
    TR["  sysctl optimization: "]="  Оптимизация sysctl: "
    TR["  IPv6 disable via GRUB: "]="  Отключение IPv6 через GRUB: "
    TR["  Repositories configuration: "]="  Настройка репозиториев: "
    TR["  Tataranovich repository (Debian): YES"]="  Репозиторий Tataranovich (Debian): ДА"
    TR["  Tataranovich repository (Ubuntu): YES"]="  Репозиторий Tataranovich (Ubuntu): ДА"
    TR["  Ubuntu PPA repositories:"]="  PPA-репозитории Ubuntu:"
    TR["    - Ondrej Nginx: YES"]="    - Ondrej Nginx: ДА"
    TR["    - Git Core: YES"]="    - Git Core: ДА"
    TR["    - Ubuntu Toolchain: YES"]="    - Ubuntu Toolchain: ДА"
    TR["  Comment IPv6 in /etc/network/interfaces: "]="  Комментирование IPv6 в /etc/network/interfaces: "
    TR["  Custom MOTD: "]="  Пользовательский MOTD: "
    TR["  UFW Custom Ports: %s"]="  Порты UFW: %s"
    TR["  UFW Custom Ports: None"]="  Порты UFW: Нет"
    TR["  BBR Network Optimizer: YES"]="  Оптимизатор сети BBR: ДА"
    TR["    - Force IPv4 APT: "]="    - Принудительный IPv4 APT: "
    TR["    - Full Update: "]="    - Полное обновление: "
    TR["    - Fix /etc/hosts: "]="    - Исправление /etc/hosts: "
    TR["    - Fix DNS: "]="    - Исправление DNS: "
    TR["  BBR Network Optimizer: NO"]="  Оптимизатор сети BBR: НЕТ"
}
# End of load_translations_ru

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Detect if running interactively
if [ -t 0 ]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# Language selection / Выбор языка
if [ "$INTERACTIVE" = true ]; then
    echo ""
    echo "Select language / Выберите язык:"
    echo "  1) English"
    echo "  2) Русский"
    read -p "Choice / Выбор [1]: " LANG_CHOICE
    case "$LANG_CHOICE" in
        2) SCRIPT_LANG="ru"; load_translations_ru ;;
        *) SCRIPT_LANG="en" ;;
    esac
else
    SCRIPT_LANG="en"
fi

if [ "$INTERACTIVE" = false ]; then
    print_warning "Running in non-interactive mode with default settings"
fi

# Print banner
echo ""
if [ "$SCRIPT_LANG" = "ru" ]; then
    print_header "╔══════════════════════════════════════════════════════╗"
    print_header "║   Скрипт настройки Debian/Ubuntu v%s              ║" "${SCRIPT_VERSION}"
    print_header "║   Расширенный инструмент конфигурации               ║"
    print_header "╚══════════════════════════════════════════════════════╝"
else
    print_header "╔═══════════════════════════════════════════════╗"
    print_header "║   Debian/Ubuntu System Setup Script v%s    ║" "${SCRIPT_VERSION}"
    print_header "║   Enhanced Configuration Tool                 ║"
    print_header "╚═══════════════════════════════════════════════╝"
fi
echo ""

# ============================================
# INITIAL CONFIGURATION PROMPTS
# ============================================

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    DETECTED_OS="$OS"
else
    DETECTED_OS=""
fi

# If OS cannot be detected, ask user to choose (only in interactive mode)
if [ -z "$DETECTED_OS" ] || ( [ "$OS" != "debian" ] && [ "$OS" != "ubuntu" ] ); then
    if [ "$INTERACTIVE" = true ]; then
        print_warning "Cannot detect OS or OS is not supported"
        echo ""
        print_message "Please select the operating system:"
        echo "  1) Debian 12 (Bookworm)"
        echo "  2) Debian 13 (Trixie)"
        echo "  3) Ubuntu 24.04 (Noble)"
        echo "  4) Ubuntu 25.04 (Plucky)"
        echo ""
        read -p "$(t "Enter your choice [1-4]: ")" OS_CHOICE
        
        case $OS_CHOICE in
            1)
                OS="debian"
                VERSION="12"
                VERSION_CODENAME="bookworm"
                print_message "Selected: Debian 12 (Bookworm)"
                ;;
            2)
                OS="debian"
                VERSION="13"
                VERSION_CODENAME="trixie"
                print_message "Selected: Debian 13 (Trixie)"
                ;;
            3)
                OS="ubuntu"
                VERSION="24.04"
                VERSION_CODENAME="noble"
                print_message "Selected: Ubuntu 24.04 (Noble)"
                ;;
            4)
                OS="ubuntu"
                VERSION="25.04"
                VERSION_CODENAME="plucky"
                print_message "Selected: Ubuntu 25.04 (Plucky)"
                ;;
            *)
                print_error "Invalid choice. Exiting."
                exit 1
                ;;
        esac
    else
        print_error "Cannot detect OS and running in non-interactive mode"
        print_error "Please run the script locally: sudo bash system-setup.sh"
        exit 1
    fi
else
    print_message "Detected OS: %s %s" "$OS" "$VERSION"
    VERSION_CODENAME=${VERSION_CODENAME:-unknown}
    
    # Validate OS
    if [ "$OS" != "debian" ] && [ "$OS" != "ubuntu" ]; then
        print_error "This script only supports Debian and Ubuntu"
        exit 1
    fi
    
    # Validate version
    if [ "$OS" = "debian" ]; then
        if [ "$VERSION" != "12" ] && [ "$VERSION" != "13" ]; then
            print_warning "Detected Debian version: %s (officially supported: 12, 13)" "$VERSION"
            read -p "$(t "Continue anyway? (y/N): ")" CONTINUE_ANYWAY
            CONTINUE_ANYWAY=${CONTINUE_ANYWAY:-n}
            if [ "$CONTINUE_ANYWAY" != "y" ] && [ "$CONTINUE_ANYWAY" != "Y" ]; then
                exit 1
            fi
        fi
    elif [ "$OS" = "ubuntu" ]; then
        if [ "$VERSION" != "24.04" ] && [ "$VERSION" != "25.04" ]; then
            print_warning "Detected Ubuntu version: %s (officially supported: 24.04, 25.04)" "$VERSION"
            read -p "$(t "Continue anyway? (y/N): ")" CONTINUE_ANYWAY
            CONTINUE_ANYWAY=${CONTINUE_ANYWAY:-n}
            if [ "$CONTINUE_ANYWAY" != "y" ] && [ "$CONTINUE_ANYWAY" != "Y" ]; then
                exit 1
            fi
        fi
    fi
fi

echo ""

# ============================================
# INTERACTIVE CONFIGURATION SELECTION
# ============================================

print_header "═══════════════════════════════════════════════"
print_header "   Configuration Options"
print_header "═══════════════════════════════════════════════"
echo ""

if [ "$INTERACTIVE" = true ]; then
    # Ask about RustDesk installation
    print_message "Do you want to install RustDesk server in Docker?"
    print_message "This will create /opt/rustdesk directory with docker-compose.yml"
    print_message "and install it as a systemd service"
    read -p "$(t "Install RustDesk? (y/N): ")" INSTALL_RUSTDESK
    INSTALL_RUSTDESK=${INSTALL_RUSTDESK:-n}

    echo ""

    # Ask about extracting opt.7z archive
    print_message "Do you want to extract additional files to /opt?"
    print_message "This will download opt.7z and copy all its contents to /opt"
    print_message "Files in 'scripts' subfolder will be made executable (except .ini)"
    read -p "$(t "Extract opt.7z to /opt? (y/N): ")" EXTRACT_OPT_ARCHIVE
    EXTRACT_OPT_ARCHIVE=${EXTRACT_OPT_ARCHIVE:-n}

    if [ "$EXTRACT_OPT_ARCHIVE" = "y" ] || [ "$EXTRACT_OPT_ARCHIVE" = "Y" ]; then
        print_message "The archive is password-protected. Please enter the password:"
        read -s -p "$(t "Password: ")" OPT_ARCHIVE_PASSWORD
        echo ""
        if [ -z "$OPT_ARCHIVE_PASSWORD" ]; then
            print_warning "No password provided. opt.7z will not be extracted."
            EXTRACT_OPT_ARCHIVE="n"
        else
            print_message "Password saved. Archive will be extracted during installation."
        fi
    else
        OPT_ARCHIVE_PASSWORD=""
    fi

    echo ""

    # Ask about root password
    print_message "Do you want to set a password for root user?"
    read -p "$(t "Set root password? (y/N): ")" SET_ROOT_PASSWORD
    SET_ROOT_PASSWORD=${SET_ROOT_PASSWORD:-n}
    
    if [ "$SET_ROOT_PASSWORD" = "y" ] || [ "$SET_ROOT_PASSWORD" = "Y" ]; then
        while true; do
            read -s -p "$(t "Enter new root password: ")" ROOT_PASSWORD
            echo ""
            read -s -p "$(t "Confirm root password: ")" ROOT_PASSWORD_CONFIRM
            echo ""
            
            if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]; then
                if [ -z "$ROOT_PASSWORD" ]; then
                    print_error "Password cannot be empty"
                    continue
                fi
                print_message "Root password will be set"
                break
            else
                print_error "Passwords do not match. Please try again."
            fi
        done
    else
        ROOT_PASSWORD=""
    fi
    
    echo ""
    
    # Ask about creating new user
    print_message "Do you want to create a new user?"
    read -p "$(t "Create new user? (y/N): ")" CREATE_USER
    CREATE_USER=${CREATE_USER:-n}
    
    if [ "$CREATE_USER" = "y" ] || [ "$CREATE_USER" = "Y" ]; then
        read -p "$(t "Enter username for new user: ")" NEW_USERNAME
        
        if [ -z "$NEW_USERNAME" ]; then
            print_error "Username cannot be empty"
            CREATE_USER="n"
        else
            # Check if user already exists
            if id "$NEW_USERNAME" &>/dev/null; then
                print_warning "User %s already exists" "$NEW_USERNAME"

                read -p "$(t "Continue with existing user? (y/N): ")" USE_EXISTING
                USE_EXISTING=${USE_EXISTING:-n}
                
                if [ "$USE_EXISTING" != "y" ] && [ "$USE_EXISTING" != "Y" ]; then
                    CREATE_USER="n"
                    NEW_USERNAME=""
                else
                    CREATE_USER="existing"
                fi
            else
                while true; do
                    read -s -p "$(t "Enter password for %s: " "$NEW_USERNAME")" NEW_USER_PASSWORD
                    echo ""
                    read -s -p "$(t "Confirm password: ")" NEW_USER_PASSWORD_CONFIRM
                    echo ""
                    
                    if [ "$NEW_USER_PASSWORD" = "$NEW_USER_PASSWORD_CONFIRM" ]; then
                        if [ -z "$NEW_USER_PASSWORD" ]; then
                            print_error "Password cannot be empty"
                            continue
                        fi
                        print_message "User %s will be created" "$NEW_USERNAME"

                        break
                    else
                        print_error "Passwords do not match. Please try again."
                    fi
                done
            fi
        fi
    else
        NEW_USERNAME=""
        NEW_USER_PASSWORD=""
    fi
    
    echo ""
    
    # Ask about SSH key for new user
    if [ ! -z "$NEW_USERNAME" ]; then
        print_message "Do you want to configure SSH key for %s?" "$NEW_USERNAME"

        read -p "$(t "Configure SSH key? (y/N): ")" CONFIGURE_USER_SSH_KEY
        CONFIGURE_USER_SSH_KEY=${CONFIGURE_USER_SSH_KEY:-n}
        
        if [ "$CONFIGURE_USER_SSH_KEY" = "y" ] || [ "$CONFIGURE_USER_SSH_KEY" = "Y" ]; then
            echo ""
            print_message "Enter SSH public key for %s" "$NEW_USERNAME"

            print_message "Example: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB..."
            read -p "$(t "SSH public key: ")" USER_SSH_KEY
            
            if [ -z "$USER_SSH_KEY" ]; then
                print_warning "No SSH key provided, skipping SSH key configuration"
                CONFIGURE_USER_SSH_KEY="n"
            fi
        else
            USER_SSH_KEY=""
        fi
    else
        CONFIGURE_USER_SSH_KEY="n"
        USER_SSH_KEY=""
    fi
    
    echo ""
    
    # Ask about zsh installation for new user
    if [ ! -z "$NEW_USERNAME" ]; then
        print_message "Do you want to install and configure zsh with Oh My Zsh for %s?" "$NEW_USERNAME"

        read -p "$(t "Install zsh? (y/N): ")" INSTALL_ZSH
        INSTALL_ZSH=${INSTALL_ZSH:-n}
    else
        INSTALL_ZSH="n"
    fi
    
    echo ""
    
    # Ask about crontab configuration
    print_message "Do you want to configure crontab for root?"
    read -p "$(t "Configure crontab? (y/N): ")" CONFIGURE_CRONTAB
    CONFIGURE_CRONTAB=${CONFIGURE_CRONTAB:-n}
    
    if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
        echo ""
        print_message "Crontab configuration mode:"
        print_message "You can add multiple cron tasks after the environment variables"
        print_message "1) Enter tasks manually (line by line)"
        print_message "2) Paste tasks from clipboard (recommended for multiple tasks)"
        print_message "3) Skip adding tasks (only set environment variables)"
        echo ""
        read -p "$(t "Choose option [1-3] (default: 3): ")" CRONTAB_MODE
        CRONTAB_MODE=${CRONTAB_MODE:-3}
        
        case $CRONTAB_MODE in
            1)
                print_message "Enter cron tasks line by line"
                print_message "Format: minute hour day month weekday command"
                print_message "Example: 0 2 * * * /root/backup.sh"
                print_message "Press CTRL+D when finished"
                echo ""
                CRONTAB_TASKS=""
                while IFS= read -r line; do
                    if [ ! -z "$line" ]; then
                        CRONTAB_TASKS="${CRONTAB_TASKS}${line}"$'\n'
                    fi
                done
                ;;
            2)
                print_message "Paste your cron tasks from clipboard"
                print_message "After pasting, type 'END' on a new line and press ENTER to finish"
                print_message ""
                print_message "Format: minute hour day month weekday command"
                print_message "Example:"
                print_message "  0 2 * * * /root/backup.sh"
                print_message "  */5 * * * * /root/check.sh"
                print_message "  @reboot /root/startup.sh"
                print_message ""
                print_message "Paste now and type END when done:"
                echo ""
                CRONTAB_TASKS=""
                while IFS= read -r line; do
                    # Stop on END marker
                    if [ "$line" = "END" ] || [ "$line" = "end" ]; then
                        break
                    fi
                    # Add line (including empty lines if they're part of the paste)
                    CRONTAB_TASKS="${CRONTAB_TASKS}${line}"$'\n'
                done
                
                # Remove trailing newline if exists
                CRONTAB_TASKS="${CRONTAB_TASKS%$'\n'}"
                
                if [ -z "$CRONTAB_TASKS" ]; then
                    print_warning "No tasks entered"
                else
                    # Count non-empty lines
                    TASK_COUNT=$(echo "$CRONTAB_TASKS" | grep -c -v '^[[:space:]]*$')
                    print_message "Captured %s cron task(s)" "$TASK_COUNT"

                fi
                ;;
            3)
                print_message "Skipping cron tasks - only environment variables will be set"
                CRONTAB_TASKS=""
                ;;
            *)
                print_warning "Invalid option. Skipping cron tasks."
                CRONTAB_TASKS=""
                ;;
        esac
    else
        CRONTAB_TASKS=""
    fi
    
    echo ""
    
    # Ask about SSH configuration
    print_message "Do you want to configure SSH (change port and set AllowUsers)?"
    read -p "$(t "Configure SSH? (y/N): ")" CONFIGURE_SSH
    CONFIGURE_SSH=${CONFIGURE_SSH:-n}
    
    if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
        while true; do
            read -p "$(t "Enter new SSH port (default 22): ")" SSH_PORT
            SSH_PORT=${SSH_PORT:-22}

            # Validate port number
            if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ]; then
                # Check if port is already in use
                if ss -tuln | grep -q ":${SSH_PORT} "; then
                    print_warning "Port %s is already in use by another service" "$SSH_PORT"

                    read -p "$(t "Continue anyway? (y/N): ")" CONTINUE_PORT
                    if [ "$CONTINUE_PORT" = "y" ] || [ "$CONTINUE_PORT" = "Y" ]; then
                        break
                    fi
                else
                    break
                fi
            else
                print_error "Invalid port number. Must be between 1 and 65535"
            fi
        done

        echo ""
        print_message "Enter usernames for AllowUsers (space-separated, leave empty to skip)"
        print_message "Example: user1 user2 user3"
        if [ ! -z "$NEW_USERNAME" ]; then
            print_message "Suggestion: %s" "$NEW_USERNAME"

        fi
        read -p "$(t "AllowUsers: ")" SSH_ALLOW_USERS

        # Validate users exist
        if [ ! -z "$SSH_ALLOW_USERS" ]; then
            INVALID_USERS=""
            for username in $SSH_ALLOW_USERS; do
                if ! id "$username" &>/dev/null; then
                    INVALID_USERS="$INVALID_USERS $username"
                fi
            done

            if [ ! -z "$INVALID_USERS" ]; then
                print_warning "The following users do not exist:%s" "$INVALID_USERS"

                print_warning "Setting AllowUsers with non-existent users may lock you out of SSH!"
                read -p "$(t "Continue anyway? (y/N): ")" CONTINUE_USERS
                if [ "$CONTINUE_USERS" != "y" ] && [ "$CONTINUE_USERS" != "Y" ]; then
                    SSH_ALLOW_USERS=""
                    print_message "AllowUsers configuration skipped"
                fi
            fi
        fi

        echo ""
        print_header "Advanced SSH Security Parameters"
        print_message "Configure additional SSH security settings"
        echo ""
        
        # PubkeyAuthentication
        print_message "PubkeyAuthentication - Enable public key authentication"
        read -p "$(t "Configure PubkeyAuthentication? (y/N): ")" CONFIG_PUBKEY
        CONFIG_PUBKEY=${CONFIG_PUBKEY:-n}
        if [ "$CONFIG_PUBKEY" = "y" ] || [ "$CONFIG_PUBKEY" = "Y" ]; then
            read -p "$(t "Set PubkeyAuthentication to yes or no? (Y/n): ")" SSH_PUBKEY_AUTH
            SSH_PUBKEY_AUTH=${SSH_PUBKEY_AUTH:-y}
            if [ "$SSH_PUBKEY_AUTH" = "y" ] || [ "$SSH_PUBKEY_AUTH" = "Y" ]; then
                SSH_PUBKEY_AUTH="yes"
            else
                SSH_PUBKEY_AUTH="no"
            fi
        else
            SSH_PUBKEY_AUTH=""
        fi
        
        # PasswordAuthentication
        print_message "PasswordAuthentication - Enable password authentication"
        read -p "$(t "Configure PasswordAuthentication? (y/N): ")" CONFIG_PASSWORD
        CONFIG_PASSWORD=${CONFIG_PASSWORD:-n}
        if [ "$CONFIG_PASSWORD" = "y" ] || [ "$CONFIG_PASSWORD" = "Y" ]; then
            read -p "$(t "Set PasswordAuthentication to yes or no? (Y/n): ")" SSH_PASSWORD_AUTH
            SSH_PASSWORD_AUTH=${SSH_PASSWORD_AUTH:-y}
            if [ "$SSH_PASSWORD_AUTH" = "y" ] || [ "$SSH_PASSWORD_AUTH" = "Y" ]; then
                SSH_PASSWORD_AUTH="yes"
            else
                SSH_PASSWORD_AUTH="no"
            fi
        else
            SSH_PASSWORD_AUTH=""
        fi
        
        # PermitEmptyPasswords - ALWAYS set to no, only ask about uncommenting
        print_message "PermitEmptyPasswords - Prevent empty password authentication (ALWAYS set to 'no')"
        read -p "$(t "Configure PermitEmptyPasswords? (y/N): ")" CONFIG_EMPTY_PASS
        CONFIG_EMPTY_PASS=${CONFIG_EMPTY_PASS:-n}
        if [ "$CONFIG_EMPTY_PASS" = "y" ] || [ "$CONFIG_EMPTY_PASS" = "Y" ]; then
            SSH_EMPTY_PASSWORDS="no"  # ALWAYS no for security
        else
            SSH_EMPTY_PASSWORDS=""
        fi
        
        # PermitRootLogin
        print_message "PermitRootLogin - Allow root user to login via SSH"
        read -p "$(t "Configure PermitRootLogin? (y/N): ")" CONFIG_ROOT_LOGIN
        CONFIG_ROOT_LOGIN=${CONFIG_ROOT_LOGIN:-n}
        if [ "$CONFIG_ROOT_LOGIN" = "y" ] || [ "$CONFIG_ROOT_LOGIN" = "Y" ]; then
            read -p "$(t "Set PermitRootLogin to yes or no? (Y/n): ")" SSH_ROOT_LOGIN
            SSH_ROOT_LOGIN=${SSH_ROOT_LOGIN:-y}
            if [ "$SSH_ROOT_LOGIN" = "y" ] || [ "$SSH_ROOT_LOGIN" = "Y" ]; then
                SSH_ROOT_LOGIN="yes"
            else
                SSH_ROOT_LOGIN="no"
            fi
        else
            SSH_ROOT_LOGIN=""
        fi
    else
        SSH_PORT="22"
        SSH_ALLOW_USERS=""
        SSH_PUBKEY_AUTH=""
        SSH_PASSWORD_AUTH=""
        SSH_EMPTY_PASSWORDS=""
        SSH_ROOT_LOGIN=""
    fi
    
    # Ask about Python virtual environment
    print_message "Do you want to create Python virtual environment?"
    read -p "$(t "Create Python venv? (y/N): ")" CREATE_VENV
    CREATE_VENV=${CREATE_VENV:-n}
    
    if [ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ]; then
        read -p "$(t "Enter path for virtual environment (default: /root/skripts): ")" VENV_PATH
        VENV_PATH=${VENV_PATH:-/root/skripts}
    else
        VENV_PATH=""
    fi
    
    # Ask about Docker installation
    print_message "Do you want to install Docker?"
    read -p "$(t "Install Docker? (y/N): ")" INSTALL_DOCKER
    INSTALL_DOCKER=${INSTALL_DOCKER:-n}
    
    # Ask about ufw-docker installation (separate from Docker)
    print_message "Do you want to install ufw-docker (UFW integration for Docker)?"
    print_message "Note: This can be installed even without Docker"
    read -p "$(t "Install ufw-docker? (y/N): ")" INSTALL_UFW_DOCKER
    INSTALL_UFW_DOCKER=${INSTALL_UFW_DOCKER:-n}
    
    # Ask about Go installation
    echo ""
    print_message "Do you want to install the latest version of Go?"
    if [ ! -z "$NEW_USERNAME" ]; then
        print_message "Go will be installed for user: %s" "$NEW_USERNAME"

    else
        print_message "Note: Go installation requires a user to be created"
    fi
    read -p "$(t "Install Go? (y/N): ")" INSTALL_GO
    INSTALL_GO=${INSTALL_GO:-n}
    
    # Ask about ipset installation
    echo ""
    print_message "Do you want to build and install the latest version of ipset?"
    print_message "This will compile ipset from source"
    read -p "$(t "Install ipset? (y/N): ")" INSTALL_IPSET
    INSTALL_IPSET=${INSTALL_IPSET:-n}
    
    echo ""
    
    # Ask about UFW configuration
    print_message "Do you want to configure UFW firewall?"
    read -p "$(t "Configure UFW? (Y/n): ")" CONFIGURE_UFW
    CONFIGURE_UFW=${CONFIGURE_UFW:-y}
    
    # Ask about ICMP blocking (only if UFW is enabled)
    if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
        echo ""
        print_message "Do you want to block ICMP (ping) requests?"
        print_message "Note: This will make your server invisible to ping"
        read -p "$(t "Block ICMP? (y/N): ")" BLOCK_ICMP
        BLOCK_ICMP=${BLOCK_ICMP:-n}
        
        # Ask about custom UFW Docker rules
        echo ""
        print_message "Do you want to install custom UFW Docker rules script?"
        print_message "Available versions:"
        print_message "  v4 - ufw-docker-rules-v4.sh (standard version)"
        print_message "  v6 - ufw-docker-rules-v6.sh (enhanced with RustDesk support, recommended)"
        print_message "Both versions support custom SSH port configuration"
        print_message "Both versions available from archive or repository"
        print_message "Note: The script will run AFTER all other installations complete"
        read -p "$(t "Install custom UFW Docker rules? (y/N): ")" INSTALL_UFW_CUSTOM_RULES
        INSTALL_UFW_CUSTOM_RULES=${INSTALL_UFW_CUSTOM_RULES:-n}

        if [ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ]; then
            echo ""
            print_message "Select version:"
            print_message "  4 - Standard version"
            print_message "  6 - Enhanced version with RustDesk support (recommended)"
            read -p "$(t "Enter version (4 or 6, default: 6): ")" UFW_RULES_VERSION
            UFW_RULES_VERSION=${UFW_RULES_VERSION:-6}

            if [ "$UFW_RULES_VERSION" != "4" ] && [ "$UFW_RULES_VERSION" != "6" ]; then
                print_warning "Invalid version. Using v6 as default."
                UFW_RULES_VERSION="6"
            fi

            print_message "Selected version: v%s" "${UFW_RULES_VERSION}"


            # Ask about installation source
            echo ""
            print_message "Select installation source:"
            print_message "  1 - Install from password-protected archive (ufw-docker-rules-v4.7z)"
            print_message "      Archive contains both v4 and v6 scripts"
            print_message "  2 - Install from public repository (https://raw.githubusercontent.com/civisrom/ufw-rules-docker/...)"
            read -p "$(t "Choose source (1 or 2, default: 1): ")" UFW_INSTALL_SOURCE
            UFW_INSTALL_SOURCE=${UFW_INSTALL_SOURCE:-1}

            if [ "$UFW_INSTALL_SOURCE" = "1" ]; then
                echo ""
                print_message "The archive is password-protected. Please enter the password:"
                read -s -p "$(t "Password: ")" UFW_CUSTOM_RULES_PASSWORD
                echo ""
                if [ -z "$UFW_CUSTOM_RULES_PASSWORD" ]; then
                    print_warning "No password provided. Custom UFW rules will not be installed."
                    INSTALL_UFW_CUSTOM_RULES="n"
                    UFW_SSH_PORT=""
                else
                    UFW_SSH_PORT=""
                fi
            else
                # Repository installation - no password needed
                UFW_CUSTOM_RULES_PASSWORD=""
                print_message "Will install from public repository (no password required)"

                # Ask for SSH port to override default in script
                echo ""
                print_message "Enter SSH port for UFW rules:"
                print_message "This port will be used instead of the default in the script"
                print_message "Note: This keeps your actual SSH port private"
                read -p "$(t "SSH Port (default: 22): ")" UFW_SSH_PORT
                UFW_SSH_PORT=${UFW_SSH_PORT:-22}

                # Validate port number
                if ! [[ "$UFW_SSH_PORT" =~ ^[0-9]+$ ]] || [ "$UFW_SSH_PORT" -lt 1 ] || [ "$UFW_SSH_PORT" -gt 65535 ]; then
                    print_warning "Invalid port number. Using default port 22."
                    UFW_SSH_PORT="22"
                fi

                print_message "SSH port set to: %s" "$UFW_SSH_PORT"

            fi
        else
            UFW_RULES_VERSION="6"
            UFW_INSTALL_SOURCE="1"
            UFW_SSH_PORT=""
        fi
    else
        BLOCK_ICMP="n"
        INSTALL_UFW_CUSTOM_RULES="n"
        UFW_RULES_VERSION="6"
        UFW_INSTALL_SOURCE="1"
        UFW_SSH_PORT=""
    fi
    
    # Ask about sysctl configuration
    print_message "Do you want to optimize system parameters (sysctl.conf)?"
    read -p "$(t "Configure sysctl? (Y/n): ")" CONFIGURE_SYSCTL
    CONFIGURE_SYSCTL=${CONFIGURE_SYSCTL:-y}
    
    # Ask about IPv6 disable via GRUB (Debian only)
    if [ "$OS" = "debian" ]; then
        echo ""
        print_message "Do you want to disable IPv6 at kernel level (GRUB)?"
        print_message "This adds 'ipv6.disable=1' to GRUB_CMDLINE_LINUX_DEFAULT"
        print_message "Note: This is in addition to sysctl IPv6 disable and requires reboot"
        read -p "$(t "Disable IPv6 via GRUB? (y/N): ")" DISABLE_IPV6_GRUB
        DISABLE_IPV6_GRUB=${DISABLE_IPV6_GRUB:-n}
    else
        DISABLE_IPV6_GRUB="n"
    fi
    
    # Ask about repository configuration
    if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        print_message "Do you want to configure %s repositories?" "${OS^}"

        read -p "$(t "Configure repositories? (Y/n): ")" CONFIGURE_REPOS
        CONFIGURE_REPOS=${CONFIGURE_REPOS:-y}
    fi
    
    # Ask about Tataranovich repository (only for Debian 12, independent from repository configuration)
    if [ "$OS" = "debian" ] && [ "$VERSION" = "12" ]; then
        echo ""
        print_message "Do you want to add Tataranovich repository (custom mc build)?"
        print_message "This will install Midnight Commander from tataranovich.com"
        print_message "Repository: https://www.tataranovich.com/debian/"
        read -p "$(t "Add Tataranovich repository? (y/N): ")" ADD_TATARANOVICH_REPO
        ADD_TATARANOVICH_REPO=${ADD_TATARANOVICH_REPO:-n}
    else
        # Disable Tataranovich for Debian 13+
        ADD_TATARANOVICH_REPO="n"
        if [ "$OS" = "debian" ] && [ "$VERSION" -ge "13" ]; then
            echo ""
            print_message "Note: Tataranovich repository is not available for Debian 13+"
        fi
    fi
    
    # Ask about Ubuntu PPA repositories (only for Ubuntu)
    if [ "$OS" = "ubuntu" ]; then
        echo ""
        print_message "Do you want to add additional PPA repositories for Ubuntu?"
        print_message "Available PPAs:"
        print_message "  1. ppa:ondrej/nginx - Latest Nginx builds"
        print_message "  2. ppa:git-core/ppa - Latest Git version"
        print_message "  3. ppa:ubuntu-toolchain-r/test - Latest GCC toolchain"
        read -p "$(t "Add PPA repositories? (y/N): ")" ADD_UBUNTU_PPAS
        ADD_UBUNTU_PPAS=${ADD_UBUNTU_PPAS:-n}
        
        # Initialize PPA selection flags
        ADD_PPA_NGINX="n"
        ADD_PPA_GIT="n"
        ADD_PPA_TOOLCHAIN="n"
        
        if [ "$ADD_UBUNTU_PPAS" = "y" ] || [ "$ADD_UBUNTU_PPAS" = "Y" ]; then
            echo ""
            print_message "Select which PPAs to add:"
            echo ""
            
            # Ondrej Nginx PPA
            print_message "1. ppa:ondrej/nginx - Latest Nginx with HTTP/3, QUIC support"
            read -p "$(t "   Add Ondrej Nginx PPA? (y/N): ")" ADD_PPA_NGINX
            ADD_PPA_NGINX=${ADD_PPA_NGINX:-n}
            
            # Git Core PPA
            print_message "2. ppa:git-core/ppa - Latest stable Git releases"
            read -p "$(t "   Add Git Core PPA? (y/N): ")" ADD_PPA_GIT
            ADD_PPA_GIT=${ADD_PPA_GIT:-n}
            
            # Ubuntu Toolchain PPA
            print_message "3. ppa:ubuntu-toolchain-r/test - Latest GCC, G++, and toolchain"
            read -p "$(t "   Add Ubuntu Toolchain PPA? (y/N): ")" ADD_PPA_TOOLCHAIN
            ADD_PPA_TOOLCHAIN=${ADD_PPA_TOOLCHAIN:-n}
        fi
        
        # Ask about Tataranovich repository for Ubuntu
        echo ""
        print_message "Do you want to add Tataranovich repository for Ubuntu (custom mc build)?"
        print_message "This will install Midnight Commander from tataranovich.com"
        print_message "Repository: https://www.tataranovich.com/ubuntu/"
        read -p "$(t "Add Tataranovich repository for Ubuntu? (y/N): ")" ADD_TATARANOVICH_UBUNTU
        ADD_TATARANOVICH_UBUNTU=${ADD_TATARANOVICH_UBUNTU:-n}
    else
        ADD_UBUNTU_PPAS="n"
        ADD_PPA_NGINX="n"
        ADD_PPA_GIT="n"
        ADD_PPA_TOOLCHAIN="n"
        ADD_TATARANOVICH_UBUNTU="n"
    fi
    
    # Ask about disabling IPv6 in /etc/network/interfaces
    echo ""
    print_message "Do you want to disable IPv6 in /etc/network/interfaces?"
    print_message "This will comment out all inet6 configuration lines"
    print_message "Note: This is useful if you're using static network configuration"
    read -p "$(t "Comment out IPv6 in /etc/network/interfaces? (y/N): ")" COMMENT_IPV6_INTERFACES
    COMMENT_IPV6_INTERFACES=${COMMENT_IPV6_INTERFACES:-n}
    
    # Ask about MOTD installation
    print_message "Do you want to install custom MOTD (Message of the Day)?"
    read -p "$(t "Install MOTD? (y/N): ")" INSTALL_MOTD
    INSTALL_MOTD=${INSTALL_MOTD:-n}
    
    # Ask for UFW ports (if UFW is enabled)
    if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
        echo ""
        print_message "UFW Firewall Configuration"
        print_message "Port %s (SSH) will be allowed automatically" "$SSH_PORT"

        echo ""
        print_message "You can add additional ports to UFW"
        print_message "Format examples:"
        print_message "  Single port:     8080"
        print_message "  With protocol:   8080/tcp  or  53/udp"
        print_message "  Multiple ports:  8080,8443,9000"
        print_message "  Mixed:          8080/tcp,53/udp,3000"
        echo ""
        read -p "$(t "Enter additional ports (comma-separated, press Enter to skip): ")" CUSTOM_PORTS
        
        if [ ! -z "$CUSTOM_PORTS" ]; then
            print_message "Custom ports will be configured: %s" "$CUSTOM_PORTS"

        fi
    else
        CUSTOM_PORTS=""
    fi
    
    # Ask about BBR Network Optimizer
    echo ""
    print_header "═══════════════════════════════════════════════"
    print_header "   Advanced Network Optimization (BBR)"
    print_header "═══════════════════════════════════════════════"
    echo ""
    print_message "Do you want to run the BBR Network Optimizer script?"
    print_message "This will apply TCP BBR congestion control and other network optimizations"
    print_message "Note: This script will run AFTER all other installations complete"
    read -p "$(t "Run BBR Network Optimizer? (y/N): ")" RUN_BBR_OPTIMIZER
    RUN_BBR_OPTIMIZER=${RUN_BBR_OPTIMIZER:-n}
    
    if [ "$RUN_BBR_OPTIMIZER" = "y" ] || [ "$RUN_BBR_OPTIMIZER" = "Y" ]; then
        echo ""
        print_message "BBR Network Optimizer Options:"
        print_message "The following functions can be enabled/disabled:"
        echo ""
        
        # Force IPv4 for APT
        print_message "1. Force IPv4 for APT (recommended for IPv6 connectivity issues)"
        read -p "$(t "   Enable force_ipv4_apt? (Y/n): ")" BBR_FORCE_IPV4
        BBR_FORCE_IPV4=${BBR_FORCE_IPV4:-y}
        
        # Full system update
        print_message "2. Full system update and upgrade (apt update && upgrade)"
        read -p "$(t "   Enable full_update_upgrade? (Y/n): ")" BBR_FULL_UPDATE
        BBR_FULL_UPDATE=${BBR_FULL_UPDATE:-y}
        
        # Fix /etc/hosts
        print_message "3. Fix /etc/hosts file (add hostname entry)"
        read -p "$(t "   Enable fix_etc_hosts? (Y/n): ")" BBR_FIX_HOSTS
        BBR_FIX_HOSTS=${BBR_FIX_HOSTS:-y}
        
        # Fix DNS
        print_message "4. Fix DNS configuration (set Cloudflare DNS)"
        read -p "$(t "   Enable fix_dns? (Y/n): ")" BBR_FIX_DNS
        BBR_FIX_DNS=${BBR_FIX_DNS:-y}
        
        echo ""
        print_message "BBR optimization settings will be applied after main installation"
    else
        BBR_FORCE_IPV4="n"
        BBR_FULL_UPDATE="n"
        BBR_FIX_HOSTS="n"
        BBR_FIX_DNS="n"
    fi
    
else
    # Default settings for non-interactive mode
    SET_ROOT_PASSWORD="n"
    ROOT_PASSWORD=""
    CREATE_USER="n"
    NEW_USERNAME=""
    NEW_USER_PASSWORD=""
    CONFIGURE_USER_SSH_KEY="n"
    USER_SSH_KEY=""
    INSTALL_ZSH="n"
    CONFIGURE_CRONTAB="n"
    CRONTAB_MODE="3"
    CRONTAB_TASKS=""
    CONFIGURE_SSH="n"
    SSH_PORT="22"
    SSH_ALLOW_USERS=""
    SSH_PUBKEY_AUTH=""
    SSH_PASSWORD_AUTH=""
    SSH_EMPTY_PASSWORDS=""
    SSH_ROOT_LOGIN=""
    CREATE_VENV="n"
    VENV_PATH=""
    INSTALL_DOCKER="n"
    CONFIGURE_UFW="y"
    BLOCK_ICMP="n"
    INSTALL_UFW_CUSTOM_RULES="n"
    EXTRACT_OPT_ARCHIVE="n"
    UFW_RULES_VERSION="6"
    UFW_CUSTOM_RULES_PASSWORD=""
    CONFIGURE_SYSCTL="y"
    CONFIGURE_REPOS="y"
    INSTALL_MOTD="n"
    CUSTOM_PORTS=""
    INSTALL_UFW_DOCKER="n"
    ADD_TATARANOVICH_REPO="n"
    ADD_TATARANOVICH_UBUNTU="n"
    ADD_UBUNTU_PPAS="n"
    ADD_PPA_NGINX="n"
    ADD_PPA_GIT="n"
    ADD_PPA_TOOLCHAIN="n"
    COMMENT_IPV6_INTERFACES="n"
    INSTALL_GO="n"
    INSTALL_IPSET="n"
    INSTALL_RUSTDESK="n"
    RUN_BBR_OPTIMIZER="n"
    BBR_FORCE_IPV4="n"
    BBR_FULL_UPDATE="n"
    BBR_FIX_HOSTS="n"
    BBR_FIX_DNS="n"
    DISABLE_IPV6_GRUB="n"
    
    print_message "Non-interactive mode - using default settings:"
    print_message "- Root password: NO"
    print_message "- Create user: NO"
    print_message "- SSH configuration: NO"
    print_message "- Python venv: NO"
    print_message "- Docker: NO"
    print_message "- ufw-docker: NO"
    print_message "- UFW: YES"
    print_message "- Block ICMP: NO"
    print_message "- sysctl: YES"
    print_message "- Repositories: YES"
    print_message "- MOTD: NO"
    print_message "- Custom UFW Port: None"
    print_message "- Crontab: NO"
    print_message "- BBR Optimizer: NO"
fi
echo ""

# Confirm settings
print_header "═══════════════════════════════════════════════"
print_message "Configuration Summary:"
echo -n "  " && print_message "OS: %s %s (%s)" "$OS" "$VERSION" "$VERSION_CODENAME"

print_message "  RustDesk Server: $([ "$INSTALL_RUSTDESK" = "y" ] || [ "$INSTALL_RUSTDESK" = "Y" ] && t "YES (Docker)" || t "NO")"
print_message "  Root password: $([ "$SET_ROOT_PASSWORD" = "y" ] || [ "$SET_ROOT_PASSWORD" = "Y" ] && t "YES" || t "NO")"
print_message "  New user: $([ ! -z "$NEW_USERNAME" ] && t "YES (%s)" "$NEW_USERNAME" || t "NO")"
if [ ! -z "$NEW_USERNAME" ]; then
    print_message "    - SSH key: $([ "$CONFIGURE_USER_SSH_KEY" = "y" ] || [ "$CONFIGURE_USER_SSH_KEY" = "Y" ] && t "YES" || t "NO")"
    print_message "    - zsh: $([ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ] && t "YES" || t "NO")"
fi
print_message "  Crontab: $([ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ] && t "YES" || t "NO")"
print_message "  SSH Configuration: $([ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ] && t "YES (Port: %s, Users: %s)" "$SSH_PORT" "${SSH_ALLOW_USERS:-none}" || t "NO")"
if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    if [ ! -z "$SSH_PUBKEY_AUTH" ]; then
        print_message "    - PubkeyAuthentication: %s" "$SSH_PUBKEY_AUTH"

    fi
    if [ ! -z "$SSH_PASSWORD_AUTH" ]; then
        print_message "    - PasswordAuthentication: %s" "$SSH_PASSWORD_AUTH"

    fi
    if [ ! -z "$SSH_EMPTY_PASSWORDS" ]; then
        print_message "    - PermitEmptyPasswords: %s" "$SSH_EMPTY_PASSWORDS"

    fi
    if [ ! -z "$SSH_ROOT_LOGIN" ]; then
        print_message "    - PermitRootLogin: %s" "$SSH_ROOT_LOGIN"

    fi
fi
print_message "  Python venv: $([ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ] && t "YES (Path: %s)" "$VENV_PATH" || t "NO")"
print_message "  Docker: $([ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ] && t "YES" || t "NO")"
print_message "  ufw-docker: $([ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ] && t "YES" || t "NO")"
print_message "  Go language: $([ "$INSTALL_GO" = "y" ] || [ "$INSTALL_GO" = "Y" ] && t "YES (latest version)" || t "NO")"
print_message "  ipset: $([ "$INSTALL_IPSET" = "y" ] || [ "$INSTALL_IPSET" = "Y" ] && t "YES (build from source)" || t "NO")"
print_message "  UFW Firewall: $([ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ] && t "YES" || t "NO")"
if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_message "  Block ICMP (ping): $([ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ] && t "YES" || t "NO")"
    if [ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ]; then
        UFW_SOURCE_TEXT="$([ "$UFW_INSTALL_SOURCE" = "2" ] && echo "from repository" || echo "from archive")"
        print_message "  Custom UFW Docker rules: YES (v%s, %s)" "${UFW_RULES_VERSION}" "${UFW_SOURCE_TEXT}"

        if [ "$UFW_INSTALL_SOURCE" = "1" ]; then
            print_message "    - Extract opt.7z to /opt: $([ "$EXTRACT_OPT_ARCHIVE" = "y" ] || [ "$EXTRACT_OPT_ARCHIVE" = "Y" ] && t "YES" || t "NO")"
        elif [ "$UFW_INSTALL_SOURCE" = "2" ] && [ -n "$UFW_SSH_PORT" ]; then
            print_message "    - Custom SSH port: %s" "$UFW_SSH_PORT"

        fi
    else
        print_message "  Custom UFW Docker rules: NO"
    fi
fi
print_message "  sysctl optimization: $([ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ] && t "YES" || t "NO")"
if [ "$OS" = "debian" ]; then
    print_message "  IPv6 disable via GRUB: $([ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ] && t "YES (kernel level)" || t "NO")"
fi
print_message "  Repositories configuration: $([ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ] && t "YES" || t "NO")"
if [ "$OS" = "debian" ] && { [ "$ADD_TATARANOVICH_REPO" = "y" ] || [ "$ADD_TATARANOVICH_REPO" = "Y" ]; }; then
    print_message "  Tataranovich repository (Debian): YES"
fi
if [ "$OS" = "ubuntu" ] && { [ "$ADD_TATARANOVICH_UBUNTU" = "y" ] || [ "$ADD_TATARANOVICH_UBUNTU" = "Y" ]; }; then
    print_message "  Tataranovich repository (Ubuntu): YES"
fi
if [ "$OS" = "ubuntu" ] && { [ "$ADD_UBUNTU_PPAS" = "y" ] || [ "$ADD_UBUNTU_PPAS" = "Y" ]; }; then
    print_message "  Ubuntu PPA repositories:"
    if [ "$ADD_PPA_NGINX" = "y" ] || [ "$ADD_PPA_NGINX" = "Y" ]; then
        print_message "    - Ondrej Nginx: YES"
    fi
    if [ "$ADD_PPA_GIT" = "y" ] || [ "$ADD_PPA_GIT" = "Y" ]; then
        print_message "    - Git Core: YES"
    fi
    if [ "$ADD_PPA_TOOLCHAIN" = "y" ] || [ "$ADD_PPA_TOOLCHAIN" = "Y" ]; then
        print_message "    - Ubuntu Toolchain: YES"
    fi
fi
print_message "  Comment IPv6 in /etc/network/interfaces: $([ "$COMMENT_IPV6_INTERFACES" = "y" ] || [ "$COMMENT_IPV6_INTERFACES" = "Y" ] && t "YES" || t "NO")"
print_message "  Custom MOTD: $([ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ] && t "YES" || t "NO")"
if [ ! -z "$CUSTOM_PORTS" ]; then
    print_message "  UFW Custom Ports: %s" "$CUSTOM_PORTS"

else
    print_message "  UFW Custom Ports: None"
fi
if [ "$RUN_BBR_OPTIMIZER" = "y" ] || [ "$RUN_BBR_OPTIMIZER" = "Y" ]; then
    print_message "  BBR Network Optimizer: YES"
    print_message "    - Force IPv4 APT: $([ "$BBR_FORCE_IPV4" = "y" ] || [ "$BBR_FORCE_IPV4" = "Y" ] && t "YES" || t "NO")"
    print_message "    - Full Update: $([ "$BBR_FULL_UPDATE" = "y" ] || [ "$BBR_FULL_UPDATE" = "Y" ] && t "YES" || t "NO")"
    print_message "    - Fix /etc/hosts: $([ "$BBR_FIX_HOSTS" = "y" ] || [ "$BBR_FIX_HOSTS" = "Y" ] && t "YES" || t "NO")"
    print_message "    - Fix DNS: $([ "$BBR_FIX_DNS" = "y" ] || [ "$BBR_FIX_DNS" = "Y" ] && t "YES" || t "NO")"
else
    print_message "  BBR Network Optimizer: NO"
fi
print_header "═══════════════════════════════════════════════"
echo ""

if [ "$INTERACTIVE" = true ]; then
    read -p "$(t "Continue with these settings? (Y/n): ")" CONFIRM
    CONFIRM=${CONFIRM:-y}
    
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        print_error "Installation cancelled by user"
        exit 0
    fi
else
    print_message "Continuing with default settings (non-interactive mode)..."
    sleep 2
fi

echo ""
print_message "Starting installation..."
echo ""

# Update package lists
print_message "Updating package lists..."
if apt-get update; then
    print_message "Package lists updated successfully"
else
    print_error "CRITICAL: Failed to update package lists"
    print_error "Installation cannot continue"
    exit 1
fi

# Common packages for both Debian and Ubuntu
COMMON_PACKAGES=(
    htop
    mc
    mc-data
    wget
    #iptables
    #ufw
    nano
    apt-utils
    curl
    git
    rsyslog
    systemd
    auditd
    manpages
    gnupg2
    sudo
    net-tools
    apache2-utils
    sqlite3
    ca-certificates
    lsb-release
    traceroute
    cron
    pwgen
    libwww-perl
    apg
    makepasswd
    squashfs-tools
    jq
    bash
    build-essential
    pkg-config
    libmnl-dev
    libnftnl-dev
    autoconf
    automake
    libtool
    python3
    python3-venv
    vim
)

# Add zsh if requested
if [ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ]; then
    COMMON_PACKAGES+=(zsh)
fi

# Debian-specific packages
# Note: linux-headers-$(uname -r) will be automatically replaced with current kernel version
# You can comment out (#) any package to disable its installation
DEBIAN_PACKAGES=(
    linux-headers-$(uname -r)
    openvswitch-switch-dpdk
)

# Ubuntu-specific packages
# Note: linux-headers-$(uname -r) will be automatically replaced with current kernel version
# You can comment out (#) any package to disable its installation
UBUNTU_PACKAGES=(
    #linux-headers-$(uname -r)
    landscape-common
    update-notifier-common
    ubuntu-keyring
    openvswitch-switch-dpdk
)

# Install packages based on OS
print_message "Installing packages..."

if [ "$OS" = "debian" ]; then
    print_message "Installing common packages for Debian..."
    apt-get install -y "${COMMON_PACKAGES[@]}"
    
    if [ ${#DEBIAN_PACKAGES[@]} -gt 0 ]; then
        print_message "Installing Debian-specific packages..."
        apt-get install -y "${DEBIAN_PACKAGES[@]}" || print_warning "Some Debian-specific packages may not be available"
    else
        print_message "No Debian-specific packages to install"
    fi
    
elif [ "$OS" = "ubuntu" ]; then
    print_message "Installing common packages for Ubuntu..."
    apt-get install -y "${COMMON_PACKAGES[@]}"
    
    if [ ${#UBUNTU_PACKAGES[@]} -gt 0 ]; then
        print_message "Installing Ubuntu-specific packages..."
        apt-get install -y "${UBUNTU_PACKAGES[@]}" || print_warning "Some Ubuntu-specific packages may not be available"
    else
        print_message "No Ubuntu-specific packages to install"
    fi
fi

# ============================================
# INSTALL RUSTDESK SERVER (DOCKER)
# ============================================

if [ "$INSTALL_RUSTDESK" = "y" ] || [ "$INSTALL_RUSTDESK" = "Y" ]; then
    print_message "Installing RustDesk server in Docker..."
    echo ""

    RUSTDESK_DIR="/opt/rustdesk"
    RUSTDESK_COMPOSE_URL="https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/refs/heads/main/config/docker-compose.yml"
    RUSTDESK_SERVICE_URL="https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/refs/heads/main/config/rustdesk-compose.service"
    RUSTDESK_SERVICE_PATH="/etc/systemd/system/rustdesk-compose.service"

    # Create rustdesk directory
    print_message "Creating directory: %s..." "$RUSTDESK_DIR"

    if mkdir -p "$RUSTDESK_DIR"; then
        print_message "Directory created successfully"
    else
        print_error "CRITICAL: Failed to create directory %s" "$RUSTDESK_DIR"

        print_error "Installation cannot continue"
        exit 1
    fi

    # Download docker-compose.yml
    print_message "Downloading docker-compose.yml..."
    if curl -fsSL "$RUSTDESK_COMPOSE_URL" -o "${RUSTDESK_DIR}/docker-compose.yml"; then
        print_message "docker-compose.yml downloaded successfully"
    else
        print_error "CRITICAL: Failed to download docker-compose.yml"
        print_error "Installation cannot continue"
        exit 1
    fi

    # Download systemd service file
    print_message "Downloading systemd service file..."
    if curl -fsSL "$RUSTDESK_SERVICE_URL" -o "$RUSTDESK_SERVICE_PATH"; then
        print_message "Service file downloaded successfully"
    else
        print_error "CRITICAL: Failed to download service file"
        print_error "Installation cannot continue"
        exit 1
    fi

    # Reload systemd daemon
    print_message "Reloading systemd daemon..."
    if systemctl daemon-reload; then
        print_message "Systemd daemon reloaded successfully"
    else
        print_error "CRITICAL: Failed to reload systemd daemon"
        print_error "Installation cannot continue"
        exit 1
    fi

    # Enable rustdesk service
    print_message "Enabling rustdesk-compose service..."
    if systemctl enable rustdesk-compose.service; then
        print_message "Service enabled successfully"
    else
        print_error "CRITICAL: Failed to enable rustdesk-compose service"
        print_error "Installation cannot continue"
        exit 1
    fi

    # Check if Docker is installed (needed to start the service)
    if command -v docker &> /dev/null; then
        print_message "Docker found, starting rustdesk-compose service..."
        if systemctl start rustdesk-compose.service; then
            print_message "RustDesk service started successfully"

            # Check service status
            sleep 3
            if systemctl is-active --quiet rustdesk-compose.service; then
                print_message "RustDesk service is running"
            else
                print_warning "RustDesk service is enabled but not running (Docker might not be installed yet)"
                print_message "Service will start automatically after Docker installation"
            fi
        else
            print_warning "Failed to start rustdesk-compose service"
            print_message "Service will start automatically after Docker installation"
        fi
    else
        print_message "Docker not installed yet - RustDesk service will start after Docker is installed"
    fi

    print_message "RustDesk installation completed"
    print_message "Directory: %s" "$RUSTDESK_DIR"

    print_message "Service: rustdesk-compose.service"
    echo ""
else
    print_message "Skipping RustDesk installation (not requested)"
fi

# ============================================
# SET ROOT PASSWORD
# ============================================

if [ "$SET_ROOT_PASSWORD" = "y" ] || [ "$SET_ROOT_PASSWORD" = "Y" ]; then
    print_message "Setting root password..."
    chpasswd << EOF
root:$ROOT_PASSWORD
EOF
    print_message "Root password set successfully"
    echo ""
fi

# ============================================
# CREATE NEW USER (after packages with sudo)
# ============================================

if [ "$CREATE_USER" = "y" ] || [ "$CREATE_USER" = "Y" ]; then
    print_message "Creating new user: %s" "$NEW_USERNAME"

    
    # Create user with home directory
    if adduser --gecos "" --disabled-password "$NEW_USERNAME"; then
        print_message "User %s created successfully" "$NEW_USERNAME"

        
        # Set password
        chpasswd << EOF
$NEW_USERNAME:$NEW_USER_PASSWORD
EOF
        print_message "Password set for %s" "$NEW_USERNAME"

        
        # Add user to sudo group
        gpasswd -a "$NEW_USERNAME" sudo
        print_message "User %s added to sudo group" "$NEW_USERNAME"

    else
        print_error "Failed to create user %s" "$NEW_USERNAME"

        CREATE_USER="n"
    fi
    echo ""
elif [ "$CREATE_USER" = "existing" ]; then
    print_message "Using existing user: %s" "$NEW_USERNAME"

    
    # Ensure user is in sudo group
    if ! groups "$NEW_USERNAME" | grep -q "\bsudo\b"; then
        gpasswd -a "$NEW_USERNAME" sudo
        print_message "User %s added to sudo group" "$NEW_USERNAME"

    else
        print_message "User %s is already in sudo group" "$NEW_USERNAME"

    fi
    echo ""
fi

# ============================================
# CONFIGURE SSH KEY FOR USER
# ============================================

if ( [ "$CONFIGURE_USER_SSH_KEY" = "y" ] || [ "$CONFIGURE_USER_SSH_KEY" = "Y" ] ) && [ ! -z "$NEW_USERNAME" ]; then
    print_message "Configuring SSH key for %s" "$NEW_USERNAME"

    
    USER_HOME=$(getent passwd "$NEW_USERNAME" | cut -d: -f6)
    
    # Create .ssh directory as user
    sudo -u "$NEW_USERNAME" bash << EOF
        mkdir -p "$USER_HOME/.ssh"
        chmod 700 "$USER_HOME/.ssh"
EOF
    
    print_message "Created .ssh directory for %s" "$NEW_USERNAME"

    
    # Add SSH key to authorized_keys (use env vars to avoid heredoc expansion issues)
    USER_SSH_KEY_ESCAPED="$USER_SSH_KEY" USER_HOME_PATH="$USER_HOME" \
    sudo -u "$NEW_USERNAME" -E bash -c '
        echo "$USER_SSH_KEY_ESCAPED" > "$USER_HOME_PATH/.ssh/authorized_keys"
        chmod 600 "$USER_HOME_PATH/.ssh/authorized_keys"
    '
    
    print_message "SSH key added to %s/.ssh/authorized_keys" "$USER_HOME"

    print_message "SSH key configured successfully for %s" "$NEW_USERNAME"

    echo ""
fi

# ============================================
# CONFIGURE REPOSITORIES
# ============================================

# Configure sources.list for Debian
if [ "$OS" = "debian" ] && { [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; }; then
    print_message "Configuring Debian repositories..."
    
    # Backup original sources.list
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d-%H%M%S)~
        print_message "Original sources.list backed up"
    fi
    
    # Use detected or selected codename
    DEBIAN_CODENAME=${VERSION_CODENAME:-bookworm}
    
    # Write new sources.list based on version
    if [ "$VERSION" = "13" ] || [ "$DEBIAN_CODENAME" = "trixie" ]; then
        # Debian 13 (Trixie) configuration - БЕЗ backports (testing не имеет backports)
        cat > /etc/apt/sources.list << EOF
### Основные репозитории Debian ${DEBIAN_CODENAME^}
deb     http://deb.debian.org/debian ${DEBIAN_CODENAME} main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian ${DEBIAN_CODENAME} main contrib non-free non-free-firmware

### Обновления безопасности
deb     http://deb.debian.org/debian-security ${DEBIAN_CODENAME}-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security ${DEBIAN_CODENAME}-security main contrib non-free non-free-firmware

### Обновления релиза
deb     http://deb.debian.org/debian ${DEBIAN_CODENAME}-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian ${DEBIAN_CODENAME}-updates main contrib non-free non-free-firmware
EOF
        print_message "Configured Debian 13 (Trixie) repositories without backports"
    else
        # Debian 12 (Bookworm) and older configuration - С backports
        cat > /etc/apt/sources.list << EOF
### Основные репозитории Debian ${DEBIAN_CODENAME^}
deb     http://deb.debian.org/debian ${DEBIAN_CODENAME} main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian ${DEBIAN_CODENAME} main contrib non-free non-free-firmware

### Обновления безопасности
deb     http://deb.debian.org/debian-security ${DEBIAN_CODENAME}-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security ${DEBIAN_CODENAME}-security main contrib non-free non-free-firmware

### Обновления стабильного релиза
deb     http://deb.debian.org/debian ${DEBIAN_CODENAME}-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian ${DEBIAN_CODENAME}-updates main contrib non-free non-free-firmware

### Backports (новые версии пакетов)
deb     http://deb.debian.org/debian ${DEBIAN_CODENAME}-backports main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian ${DEBIAN_CODENAME}-backports main contrib non-free non-free-firmware
EOF
        print_message "Configured Debian %s (%s) repositories with backports" "${VERSION}" "${DEBIAN_CODENAME^}"

    fi
    
    print_message "Debian repositories configured"
    apt-get update
    echo ""
fi

# Configure sources.list for Ubuntu
if [ "$OS" = "ubuntu" ] && { [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; }; then
    print_message "Configuring Ubuntu repositories..."
    
    # Backup original sources.list if it exists and has content
    if [ -f /etc/apt/sources.list ] && [ -s /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d-%H%M%S)~
        print_message "Original sources.list backed up"
        
        # Clear the main sources.list file
        cat > /etc/apt/sources.list << 'EOF'
# Ubuntu repositories are now managed in /etc/apt/sources.list.d/
# See /etc/apt/sources.list.d/ubuntu.sources for repository configuration
EOF
        print_message "Main sources.list cleared (repositories moved to sources.list.d)"
    fi
    
    # Use detected or selected codename
    UBUNTU_CODENAME=${VERSION_CODENAME:-noble}
    
    # Use ubuntu.sources (new DEB822 format) instead of ubuntu.list
    UBUNTU_SOURCES_FILE="/etc/apt/sources.list.d/ubuntu.sources"
    
    # Backup if exists
    if [ -f "$UBUNTU_SOURCES_FILE" ]; then
        cp "$UBUNTU_SOURCES_FILE" "/etc/apt/sources.list.d/ubuntu.sources.backup.$(date +%Y%m%d-%H%M%S)~"
        print_message "Existing ubuntu.sources backed up"
    fi
    
    # Write new ubuntu.sources in DEB822 format
    cat > "$UBUNTU_SOURCES_FILE" << EOF
## Ubuntu Main Repositories
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: ${UBUNTU_CODENAME} ${UBUNTU_CODENAME}-updates ${UBUNTU_CODENAME}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

## Ubuntu Security Updates
Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: ${UBUNTU_CODENAME}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

## Ubuntu Sources (optional - uncomment to enable)
# Types: deb-src
# URIs: http://archive.ubuntu.com/ubuntu/
# Suites: ${UBUNTU_CODENAME} ${UBUNTU_CODENAME}-updates ${UBUNTU_CODENAME}-backports
# Components: main restricted universe multiverse
# Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

# Types: deb-src
# URIs: http://security.ubuntu.com/ubuntu/
# Suites: ${UBUNTU_CODENAME}-security
# Components: main restricted universe multiverse
# Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    
    print_message "Ubuntu repositories configured in: %s" "$UBUNTU_SOURCES_FILE"

    print_message "Format: DEB822 (ubuntu.sources)"
    print_message "Codename: %s" "${UBUNTU_CODENAME^}"

    print_message "Repositories enabled: main, restricted, universe, multiverse"
    apt-get update
    echo ""
fi

# ============================================
# ADD UBUNTU PPA REPOSITORIES
# ============================================

if [ "$OS" = "ubuntu" ] && { [ "$ADD_UBUNTU_PPAS" = "y" ] || [ "$ADD_UBUNTU_PPAS" = "Y" ]; }; then
    print_message "Adding Ubuntu PPA repositories..."
    echo ""
    
    # Install software-properties-common if not already installed (provides add-apt-repository)
    if ! command -v add-apt-repository &> /dev/null; then
        print_message "Installing software-properties-common..."
        apt-get install -y software-properties-common
    fi
    
    # Add Ondrej Nginx PPA
    if [ "$ADD_PPA_NGINX" = "y" ] || [ "$ADD_PPA_NGINX" = "Y" ]; then
        print_message "Adding ppa:ondrej/nginx..."
        print_warning "Press ENTER when prompted to confirm the PPA addition"
        echo ""
        
        # Use -y flag to auto-accept
        if add-apt-repository -y ppa:ondrej/nginx 2>&1; then
            print_success "Ondrej Nginx PPA added successfully"
        else
            print_warning "Failed to add Ondrej Nginx PPA, continuing..."
        fi
        echo ""
    fi
    
    # Add Git Core PPA
    if [ "$ADD_PPA_GIT" = "y" ] || [ "$ADD_PPA_GIT" = "Y" ]; then
        print_message "Adding ppa:git-core/ppa..."
        print_warning "Press ENTER when prompted to confirm the PPA addition"
        echo ""
        
        # Use -y flag to auto-accept
        if add-apt-repository -y ppa:git-core/ppa 2>&1; then
            print_success "Git Core PPA added successfully"
        else
            print_warning "Failed to add Git Core PPA, continuing..."
        fi
        echo ""
    fi
    
    # Add Ubuntu Toolchain PPA
    if [ "$ADD_PPA_TOOLCHAIN" = "y" ] || [ "$ADD_PPA_TOOLCHAIN" = "Y" ]; then
        print_message "Adding ppa:ubuntu-toolchain-r/test..."
        print_warning "Press ENTER when prompted to confirm the PPA addition"
        echo ""
        
        # Use -y flag to auto-accept
        if add-apt-repository -y ppa:ubuntu-toolchain-r/test 2>&1; then
            print_success "Ubuntu Toolchain PPA added successfully"
        else
            print_warning "Failed to add Ubuntu Toolchain PPA, continuing..."
        fi
        echo ""
    fi
    
    # Update package lists after adding PPAs
    print_message "Updating package lists with new PPA repositories..."
    if apt-get update; then
        print_success "Package lists updated successfully"
        
        # Show added PPAs
        print_message "Added PPA repositories:"
        if [ "$ADD_PPA_NGINX" = "y" ] || [ "$ADD_PPA_NGINX" = "Y" ]; then
            print_message "  ✓ ppa:ondrej/nginx"
        fi
        if [ "$ADD_PPA_GIT" = "y" ] || [ "$ADD_PPA_GIT" = "Y" ]; then
            print_message "  ✓ ppa:git-core/ppa"
        fi
        if [ "$ADD_PPA_TOOLCHAIN" = "y" ] || [ "$ADD_PPA_TOOLCHAIN" = "Y" ]; then
            print_message "  ✓ ppa:ubuntu-toolchain-r/test"
        fi
    else
        print_warning "Failed to update package lists after adding PPAs"
    fi
    
    echo ""
fi

# ============================================
# CONFIGURE TATARANOVICH REPOSITORY (UBUNTU)
# ============================================

if [ "$OS" = "ubuntu" ] && { [ "$ADD_TATARANOVICH_UBUNTU" = "y" ] || [ "$ADD_TATARANOVICH_UBUNTU" = "Y" ]; }; then
    print_message "Configuring Tataranovich repository for Ubuntu..."
    
    # Install required packages if not already installed
    print_message "Installing prerequisites for Tataranovich repository..."
    apt-get install -y curl gnupg software-properties-common
    
    # Download GPG key
    print_message "Downloading Tataranovich GPG key..."
    if curl -fsSL https://www.tataranovich.com/ubuntu/gpg -o /etc/apt/trusted.gpg.d/tataranovich-ubuntu.gpg; then
        print_message "GPG key downloaded successfully"
        chmod 644 /etc/apt/trusted.gpg.d/tataranovich-ubuntu.gpg
    else
        print_error "Failed to download Tataranovich GPG key"
        print_warning "Skipping Tataranovich repository configuration"
        ADD_TATARANOVICH_UBUNTU="n"
    fi
    
    if [ "$ADD_TATARANOVICH_UBUNTU" = "y" ] || [ "$ADD_TATARANOVICH_UBUNTU" = "Y" ]; then
        # Add repository
        print_message "Adding Tataranovich repository..."
        
        # Use detected codename for repository
        TATARANOVICH_UBUNTU_CODENAME=${VERSION_CODENAME:-noble}
        
        # Backup existing file if present
        if [ -f /etc/apt/sources.list.d/tataranovich-ubuntu.list ]; then
            cp /etc/apt/sources.list.d/tataranovich-ubuntu.list /etc/apt/sources.list.d/tataranovich-ubuntu.list.backup.$(date +%Y%m%d-%H%M%S)~
        fi
        
        echo "deb http://www.tataranovich.com/ubuntu ${TATARANOVICH_UBUNTU_CODENAME} main" | tee /etc/apt/sources.list.d/tataranovich-ubuntu.list > /dev/null
        print_message "Tataranovich repository added: /etc/apt/sources.list.d/tataranovich-ubuntu.list"
        
        # Update package lists
        print_message "Updating package lists with Tataranovich repository..."
        if apt-get update; then
            print_success "Package lists updated successfully"
            
            # Install mc from Tataranovich repository
            print_message "Installing Midnight Commander from Tataranovich repository..."
            if apt-get install -y mc; then
                print_success "Midnight Commander installed successfully from Tataranovich repository"
                
                # Verify installation
                MC_VERSION=$(mc --version 2>&1 | head -1)
                print_message "Installed: %s" "$MC_VERSION"

            else
                print_warning "Failed to install mc from Tataranovich repository"
                print_message "Installing mc from standard repositories..."
                apt-get install -y mc || print_warning "Failed to install mc"
            fi
        else
            print_warning "Failed to update package lists with Tataranovich repository"
            print_message "Installing mc from standard repositories..."
            apt-get install -y mc || print_warning "Failed to install mc"
        fi
    fi
    echo ""
fi

# ============================================
# CONFIGURE TATARANOVICH REPOSITORY (DEBIAN 12 ONLY)
# ============================================

if [ "$OS" = "debian" ] && { [ "$ADD_TATARANOVICH_REPO" = "y" ] || [ "$ADD_TATARANOVICH_REPO" = "Y" ]; }; then
    print_message "Configuring Tataranovich repository for Debian 12..."
    
    # Install required packages if not already installed
    print_message "Installing prerequisites for Tataranovich repository..."
    apt-get install -y curl gnupg
    
    # Download GPG key
    print_message "Downloading Tataranovich GPG key..."
    if curl -fsSL https://www.tataranovich.com/debian/gpg -o /etc/apt/trusted.gpg.d/tataranovich.gpg; then
        print_message "GPG key downloaded successfully"
        chmod 644 /etc/apt/trusted.gpg.d/tataranovich.gpg
    else
        print_error "Failed to download Tataranovich GPG key"
        print_warning "Skipping Tataranovich repository configuration"
        ADD_TATARANOVICH_REPO="n"
    fi
    
    if [ "$ADD_TATARANOVICH_REPO" = "y" ] || [ "$ADD_TATARANOVICH_REPO" = "Y" ]; then
        # Add repository
        print_message "Adding Tataranovich repository..."
        
        # Use detected codename for repository
        TATARANOVICH_CODENAME=${VERSION_CODENAME:-bookworm}
        
        # Backup existing file if present
        if [ -f /etc/apt/sources.list.d/tataranovich.list ]; then
            cp /etc/apt/sources.list.d/tataranovich.list /etc/apt/sources.list.d/tataranovich.list.backup.$(date +%Y%m%d-%H%M%S)~
        fi
        
        echo "deb http://www.tataranovich.com/debian ${TATARANOVICH_CODENAME} main" | tee /etc/apt/sources.list.d/tataranovich.list > /dev/null
        print_message "Tataranovich repository added: /etc/apt/sources.list.d/tataranovich.list"
        
        # Update package lists
        print_message "Updating package lists with Tataranovich repository..."
        if apt-get update; then
            print_success "Package lists updated successfully"
            
            # Install mc from Tataranovich repository
            print_message "Installing Midnight Commander from Tataranovich repository..."
            if apt-get install -y mc; then
                print_success "Midnight Commander installed successfully from Tataranovich repository"
                
                # Verify installation
                MC_VERSION=$(mc --version 2>&1 | head -1)
                print_message "Installed: %s" "$MC_VERSION"

            else
                print_warning "Failed to install mc from Tataranovich repository"
                print_message "Installing mc from standard repositories..."
                apt-get install -y mc || print_warning "Failed to install mc"
            fi
        else
            print_warning "Failed to update package lists with Tataranovich repository"
            print_message "Installing mc from standard repositories..."
            apt-get install -y mc || print_warning "Failed to install mc"
        fi
    fi
    echo ""
else
    # Install mc from standard repositories if Tataranovich is not used
    if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        print_message "Installing Midnight Commander from standard repositories..."
        apt-get install -y mc || print_warning "Failed to install mc"
        echo ""
    fi
fi

# ============================================
# INSTALL AND CONFIGURE ZSH FOR USER
# ============================================

if ( [ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ] ) && [ ! -z "$NEW_USERNAME" ]; then
    print_message "Installing Oh My Zsh for %s" "$NEW_USERNAME"

    
    USER_HOME=$(getent passwd "$NEW_USERNAME" | cut -d: -f6)
    
    # Install Oh My Zsh as user
    print_message "Installing Oh My Zsh..."
    sudo -u "$NEW_USERNAME" -i bash << EOF
        export HOME="$USER_HOME"
        export RUNZSH=no
        export CHSH=no
        cd "\$HOME"
        sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
EOF
    
    if [ -d "$USER_HOME/.oh-my-zsh" ]; then
        print_message "Oh My Zsh installed successfully"
        
        # Install zsh plugins
        print_message "Installing zsh plugins..."
        
        sudo -u "$NEW_USERNAME" -i bash << EOF
            export HOME="$USER_HOME"
            cd "\$HOME"
            git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "\${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
            git clone https://github.com/zsh-users/zsh-autosuggestions "\${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
            git clone https://github.com/zsh-users/zsh-history-substring-search "\${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search"
EOF
        
        print_message "Zsh plugins installed successfully"
        
        # Download custom .zshrc
        print_message "Downloading custom .zshrc configuration..."
        if sudo -u "$NEW_USERNAME" curl -fsSL https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/refs/heads/main/config/.zshrc -o "$USER_HOME/.zshrc"; then
            print_message "Custom .zshrc downloaded successfully"
            sudo -u "$NEW_USERNAME" chmod 644 "$USER_HOME/.zshrc"
        else
            print_warning "Failed to download custom .zshrc, using default"
        fi
        
        # Change default shell to zsh
        print_message "Changing default shell to zsh for %s" "$NEW_USERNAME"

        chsh -s $(which zsh) "$NEW_USERNAME"
        print_message "Default shell changed to zsh"
    else
        print_error "Oh My Zsh installation failed"
    fi
    echo ""
fi

# ============================================
# CONFIGURE SYSCTL.CONF
# ============================================

# Configure sysctl.conf
if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    print_message "Configuring system parameters (sysctl.conf)..."
    
    # Backup original sysctl.conf
    if [ -f /etc/sysctl.conf ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d-%H%M%S)~
        print_message "Original sysctl.conf backed up"
    fi
    
    # Preserve only comments and empty lines from original file
    if [ -f /etc/sysctl.conf ]; then
        grep -E '^#|^$' /etc/sysctl.conf > /etc/sysctl.conf.new 2>/dev/null || true
    else
        touch /etc/sysctl.conf.new
    fi
    
    # Add new configuration with proper spacing
    cat >> /etc/sysctl.conf.new << 'EOF'

# Custom Network Optimizations
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.wmem_default = 2097152
net.core.netdev_max_backlog = 10240
net.core.somaxconn = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_max_syn_backlog = 10240
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.udp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 16384 262144 8388608
net.ipv4.tcp_wmem = 32768 524288 16777216
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
fs.inotify.max_user_instances = 8192
net.ipv4.ip_local_port_range = 1024 45000
EOF
    
    mv /etc/sysctl.conf.new /etc/sysctl.conf
    print_message "sysctl.conf configured"
    
    # Apply sysctl settings
    print_message "Applying sysctl settings..."
    sysctl -p || print_warning "Some sysctl parameters may not have been applied"

    # IMPORTANT: After disabling IPv6 via sysctl, IPv6 nameservers in /etc/resolv.conf
    # become unreachable. Clean them up immediately to prevent DNS resolution failures
    # for subsequent network operations (Docker, Go, ipset downloads, etc.)
    RESOLV_FILE="/etc/resolv.conf"
    if [ -f "$RESOLV_FILE" ] && grep -qE "^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F]*:" "$RESOLV_FILE"; then
        print_message "Removing IPv6 nameservers from %s (IPv6 is now disabled)..." "$RESOLV_FILE"
        cp "$RESOLV_FILE" "${RESOLV_FILE}.backup.pre-sysctl.$(date +%Y%m%d-%H%M%S)~"
        TEMP_RESOLV=$(mktemp)
        grep -vE "^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F]*:" "$RESOLV_FILE" > "$TEMP_RESOLV"
        if [ -s "$TEMP_RESOLV" ] && grep -qE "^[[:space:]]*nameserver" "$TEMP_RESOLV"; then
            mv "$TEMP_RESOLV" "$RESOLV_FILE"
            print_success "IPv6 nameservers removed from %s" "$RESOLV_FILE"
        else
            rm -f "$TEMP_RESOLV"
            # No IPv4 nameservers remain — add fallback DNS to maintain connectivity
            print_warning "No IPv4 nameservers found, adding fallback DNS servers..."
            {
                grep -vE "^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F]*:" "$RESOLV_FILE"
                echo "nameserver 8.8.8.8"
                echo "nameserver 1.1.1.1"
            } > "${RESOLV_FILE}.tmp" && mv "${RESOLV_FILE}.tmp" "$RESOLV_FILE"
            print_success "Fallback DNS servers (8.8.8.8, 1.1.1.1) added to %s" "$RESOLV_FILE"
        fi
    fi
else
    print_message "Skipping sysctl configuration (not requested)"
fi

# ============================================
# DISABLE IPv6 VIA GRUB (DEBIAN ONLY)
# ============================================

if [ "$OS" = "debian" ] && { [ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ]; }; then
    print_message "Disabling IPv6 at kernel level via GRUB..."
    
    GRUB_CONFIG="/etc/default/grub"
    
    # Backup original grub config
    if [ -f "$GRUB_CONFIG" ]; then
        cp "$GRUB_CONFIG" "${GRUB_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)~"
        print_message "Original GRUB config backed up"
    else
        print_error "GRUB config file not found: %s" "$GRUB_CONFIG"

        print_warning "Skipping IPv6 GRUB disable"
        DISABLE_IPV6_GRUB="n"
    fi
    
    if [ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ]; then
        # Check if ipv6.disable is already present
        if grep -q "ipv6.disable=1" "$GRUB_CONFIG"; then
            print_warning "IPv6 disable parameter already present in GRUB config"
        else
            # Modify GRUB_CMDLINE_LINUX_DEFAULT
            if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_CONFIG"; then
                # Get current value
                CURRENT_VALUE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_CONFIG" | cut -d'"' -f2)
                
                # Add ipv6.disable=1 to the existing parameters
                if [ -z "$CURRENT_VALUE" ]; then
                    # Empty, just add ipv6.disable=1
                    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1"/' "$GRUB_CONFIG"
                else
                    # Add to existing parameters
                    NEW_VALUE="${CURRENT_VALUE} ipv6.disable=1"
                    sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_VALUE}\"/" "$GRUB_CONFIG"
                fi
                
                print_message "Added ipv6.disable=1 to GRUB_CMDLINE_LINUX_DEFAULT"
            else
                # Line doesn't exist, add it
                echo 'GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1"' >> "$GRUB_CONFIG"
                print_message "Added GRUB_CMDLINE_LINUX_DEFAULT with ipv6.disable=1"
            fi
            
            # Update GRUB
            print_message "Updating GRUB configuration..."
            update-grub 2>&1 | tee /tmp/grub-update.log
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                print_success "GRUB configuration updated successfully"
                print_warning "IPv6 will be disabled at kernel level after reboot"
            else
                print_error "Failed to update GRUB configuration"
                print_warning "Check /tmp/grub-update.log for details"
                
                # Try to restore backup
                print_warning "Attempting to restore GRUB config from backup..."
                LATEST_BACKUP=$(ls -t ${GRUB_CONFIG}.backup.*~ 2>/dev/null | head -1)
                if [ ! -z "$LATEST_BACKUP" ]; then
                    cp "$LATEST_BACKUP" "$GRUB_CONFIG"
                    print_message "GRUB config restored from backup"
                fi
            fi
        fi
        
        # Display current GRUB_CMDLINE_LINUX_DEFAULT
        print_message "Current GRUB_CMDLINE_LINUX_DEFAULT:"
        grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_CONFIG"
    fi
    echo ""
else
    if [ "$OS" = "debian" ]; then
        print_message "Skipping IPv6 GRUB disable (not requested)"
    fi
fi

# ============================================
# COMMENT IPv6 IN /etc/network/interfaces
# ============================================

if [ "$COMMENT_IPV6_INTERFACES" = "y" ] || [ "$COMMENT_IPV6_INTERFACES" = "Y" ]; then
    print_message "Commenting out IPv6 configuration in /etc/network/interfaces..."
    
    INTERFACES_FILE="/etc/network/interfaces"
    
    if [ ! -f "$INTERFACES_FILE" ]; then
        print_warning "File %s not found" "$INTERFACES_FILE"

        print_message "Your system may use netplan or NetworkManager instead"
        print_message "Skipping /etc/network/interfaces IPv6 configuration"
    else
        # Backup original interfaces file
        cp "$INTERFACES_FILE" "${INTERFACES_FILE}.backup.$(date +%Y%m%d-%H%M%S)~"
        print_message "Original %s backed up" "$INTERFACES_FILE"

        
        # Check if there are any inet6 lines
        if grep -q "inet6" "$INTERFACES_FILE"; then
            print_message "Found IPv6 configuration in %s" "$INTERFACES_FILE"

            
            # Create temporary file
            TEMP_FILE=$(mktemp)
            
            # Comment out all lines containing inet6 or related to IPv6
            # This includes iface lines with inet6 and their parameters
            # Also removes IPv6 addresses from dns-nameservers in IPv4 blocks
            awk '
            /^[[:space:]]*iface.*inet6/ {
                # This is an inet6 interface definition
                print "#" $0
                in_inet6_block = 1
                in_inet4_block = 0
                next
            }
            /^[[:space:]]*iface.*inet[[:space:]]/ {
                # This is an inet4 interface definition
                in_inet4_block = 1
                in_inet6_block = 0
                print $0
                next
            }
            in_inet6_block {
                # We are in an inet6 block
                if (/^[[:space:]]*$/ || /^[[:space:]]*#/ || /^[[:space:]]*auto/ || /^[[:space:]]*iface/) {
                    # End of inet6 block
                    in_inet6_block = 0
                    print $0
                } else {
                    # This line is part of inet6 configuration
                    print "#" $0
                }
                next
            }
            in_inet4_block && /^[[:space:]]*dns-nameservers/ {
                # In IPv4 block: remove IPv6 addresses from dns-nameservers
                # Extract leading whitespace
                match($0, /^[[:space:]]*/)
                leading = substr($0, RSTART, RLENGTH)
                # Build new line with only IPv4 addresses (skip anything containing ":")
                result = leading "dns-nameservers"
                has_ipv4 = 0
                for (i = 2; i <= NF; i++) {
                    if ($i !~ /:/) {
                        result = result " " $i
                        has_ipv4 = 1
                    }
                }
                if (has_ipv4) {
                    print result
                }
                # If no IPv4 addresses remain, skip the line entirely
                next
            }
            in_inet4_block {
                # Check if we are leaving the inet4 block
                if (/^[[:space:]]*$/ || /^[[:space:]]*auto/ || /^[[:space:]]*iface/) {
                    in_inet4_block = 0
                }
                print $0
                next
            }
            {
                # Regular line, print as is
                print $0
            }
            ' "$INTERFACES_FILE" > "$TEMP_FILE"
            
            # Verify the temporary file is not empty
            if [ -s "$TEMP_FILE" ]; then
                # Replace original file
                mv "$TEMP_FILE" "$INTERFACES_FILE"
                print_success "IPv6 configuration commented out in %s" "$INTERFACES_FILE"

                
                echo ""
                print_message "Modified %s preview:" "$INTERFACES_FILE"

                print_header "─────────────────────────────────────────────"
                grep -A 2 -B 2 "inet6" "$INTERFACES_FILE" 2>/dev/null || print_message "No IPv6 lines remaining (all commented)"
                print_header "─────────────────────────────────────────────"
                echo ""
                
                # Remove IPv6 nameservers from /etc/resolv.conf
                RESOLV_FILE="/etc/resolv.conf"
                if [ -f "$RESOLV_FILE" ]; then
                    if grep -qE "^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F]*:" "$RESOLV_FILE"; then
                        cp "$RESOLV_FILE" "${RESOLV_FILE}.backup.$(date +%Y%m%d-%H%M%S)~"
                        print_message "Original %s backed up" "$RESOLV_FILE"

                        TEMP_RESOLV=$(mktemp)
                        # Remove lines with IPv6 nameservers (addresses containing ":")
                        grep -vE "^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F]*:" "$RESOLV_FILE" > "$TEMP_RESOLV"
                        if [ -s "$TEMP_RESOLV" ]; then
                            mv "$TEMP_RESOLV" "$RESOLV_FILE"
                            print_success "IPv6 nameservers removed from %s" "$RESOLV_FILE"

                        else
                            rm -f "$TEMP_RESOLV"
                            print_warning "Not modifying %s - would result in empty file" "$RESOLV_FILE"

                        fi
                    else
                        print_message "No IPv6 nameservers found in %s" "$RESOLV_FILE"

                    fi
                fi

                print_warning "Network configuration changed. You may need to restart networking:"
                print_message "  sudo systemctl restart networking"
                print_message "  OR reboot the system"
            else
                print_error "Failed to create modified interfaces file"
                rm -f "$TEMP_FILE"
                # Restore from backup
                LATEST_BACKUP=$(ls -t ${INTERFACES_FILE}.backup.*~ 2>/dev/null | head -1)
                if [ ! -z "$LATEST_BACKUP" ]; then
                    cp "$LATEST_BACKUP" "$INTERFACES_FILE"
                    print_message "Restored from backup"
                fi
            fi
        else
            print_message "No IPv6 configuration found in %s" "$INTERFACES_FILE"

            print_message "File is already without IPv6 or uses different format"
        fi
    fi
    echo ""
else
    print_message "Skipping IPv6 commenting in /etc/network/interfaces (not requested)"
fi

# ============================================
# CONFIGURE SSH
# ============================================

# Configure SSH
if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    print_message "Configuring SSH..."
    
    SSHD_CONFIG="/etc/ssh/sshd_config"
    
    # Backup original sshd_config
    if [ -f "$SSHD_CONFIG" ]; then
        cp "$SSHD_CONFIG" "/etc/ssh/sshd_config.backup.$(date +%Y%m%d-%H%M%S)~"
        print_message "Original sshd_config backed up"
    fi
    
    # Function to set or update SSH parameter
    configure_ssh_parameter() {
        local param_name="$1"
        local param_value="$2"
        local config_file="$3"
        
        # Check if parameter exists (commented or uncommented)
        if grep -q "^#*${param_name} " "$config_file"; then
            # Parameter exists, replace it in place
            # Find the first occurrence and replace it (whether commented or not)
            sed -i "0,/^#*${param_name} .*/{s/^#*${param_name} .*/${param_name} ${param_value}/}" "$config_file"
            
            # Remove any duplicate lines of this parameter (in case there were multiple)
            # Keep only the first occurrence (which we just modified)
            sed -i "0,/^${param_name} ${param_value}/b; /^#*${param_name} /d" "$config_file"
            
            print_message "SSH parameter set: %s %s" "${param_name}" "${param_value}"

        else
            # Parameter doesn't exist, add it at the end
            echo "" >> "$config_file"
            echo "# Custom SSH configuration" >> "$config_file"
            echo "${param_name} ${param_value}" >> "$config_file"
            print_message "SSH parameter added: %s %s" "${param_name}" "${param_value}"

        fi
    }
    
    # Change SSH port
    if [ ! -z "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        # Check if Port line exists (commented or not)
        if grep -q "^#\?Port " "$SSHD_CONFIG"; then
            # First uncomment any commented Port line, then set the value
            # Use a single awk pass to avoid duplication
            awk -v port="$SSH_PORT" '
                /^#?Port / {
                    if (!port_set) { print "Port " port; port_set=1 }
                    next
                }
                { print }
            ' "$SSHD_CONFIG" > "${SSHD_CONFIG}.tmp" && mv "${SSHD_CONFIG}.tmp" "$SSHD_CONFIG"
            print_message "SSH port changed to %s" "$SSH_PORT"

        else
            # Add Port line after Include directive
            sed -i "/^Include \/etc\/ssh\/sshd_config.d\/\*.conf/a Port $SSH_PORT" "$SSHD_CONFIG"
            print_message "SSH port set to %s" "$SSH_PORT"

        fi
    fi
    
    # Configure PubkeyAuthentication
    if [ ! -z "$SSH_PUBKEY_AUTH" ]; then
        configure_ssh_parameter "PubkeyAuthentication" "$SSH_PUBKEY_AUTH" "$SSHD_CONFIG"
    fi
    
    # Configure PasswordAuthentication
    if [ ! -z "$SSH_PASSWORD_AUTH" ]; then
        configure_ssh_parameter "PasswordAuthentication" "$SSH_PASSWORD_AUTH" "$SSHD_CONFIG"
    fi
    
    # Configure PermitEmptyPasswords (ALWAYS no for security)
    if [ ! -z "$SSH_EMPTY_PASSWORDS" ]; then
        configure_ssh_parameter "PermitEmptyPasswords" "$SSH_EMPTY_PASSWORDS" "$SSHD_CONFIG"
        print_warning "PermitEmptyPasswords set to 'no' for security reasons"
    fi
    
    # Configure PermitRootLogin
    if [ ! -z "$SSH_ROOT_LOGIN" ]; then
        configure_ssh_parameter "PermitRootLogin" "$SSH_ROOT_LOGIN" "$SSHD_CONFIG"
    fi
    
    # Add AllowUsers if specified
    if [ ! -z "$SSH_ALLOW_USERS" ]; then
        # Remove existing AllowUsers lines
        sed -i '/^AllowUsers /d' "$SSHD_CONFIG"
        
        # Add AllowUsers at the end of file
        echo "" >> "$SSHD_CONFIG"
        echo "# Allowed users" >> "$SSHD_CONFIG"
        echo "AllowUsers $SSH_ALLOW_USERS" >> "$SSHD_CONFIG"
        print_message "AllowUsers set to: %s" "$SSH_ALLOW_USERS"

    fi
    
    # Test SSH configuration
    print_message "Testing SSH configuration..."
    if sshd -t; then
        print_message "SSH configuration is valid"
        
        # Restart SSH service
        print_message "Restarting SSH service..."
        if systemctl restart sshd 2>/dev/null; then
            print_message "SSH service restarted (sshd)"
        elif systemctl restart ssh 2>/dev/null; then
            print_message "SSH service restarted (ssh)"
        elif service ssh restart 2>/dev/null; then
            print_message "SSH service restarted (service ssh)"
        elif service sshd restart 2>/dev/null; then
            print_message "SSH service restarted (service sshd)"
        else
            print_error "Failed to restart SSH service"
            print_warning "Please restart SSH manually: sudo systemctl restart ssh"
        fi
    else
        print_error "SSH configuration test failed!"
        print_error "Restoring backup..."
        LATEST_BACKUP=$(ls -t /etc/ssh/sshd_config.backup.*~ 2>/dev/null | head -1)
        if [ ! -z "$LATEST_BACKUP" ]; then
            cp "$LATEST_BACKUP" "$SSHD_CONFIG"
            print_error "SSH configuration restored from backup"
        else
            print_error "No backup found to restore"
        fi
    fi
else
    print_message "Skipping SSH configuration (not requested)"
fi

# ============================================
# CONFIGURE UFW
# ============================================

# Configure UFW
if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_message "Configuring UFW firewall..."
    
    # Set default policies
    print_message "Setting UFW default policies..."
    ufw --force default deny incoming || { print_error "Failed to set UFW default policy"; }
    ufw --force default allow outgoing || true
    ufw --force default deny forward || true
    ufw --force default deny routed || true
    print_message "UFW default policies configured"
    
    # Allow SSH (use configured port)
    ufw allow "${SSH_PORT}/tcp" comment 'SSH' || print_error "Failed to add SSH UFW rule"
    print_message "UFW rule added: Allow SSH (port %s)" "${SSH_PORT}"

    
    # Add custom ports if specified
    if [ ! -z "$CUSTOM_PORTS" ]; then
        print_message "Configuring custom ports: %s" "$CUSTOM_PORTS"

        
        # Split ports by comma
        IFS=',' read -ra PORT_ARRAY <<< "$CUSTOM_PORTS"
        
        for PORT_SPEC in "${PORT_ARRAY[@]}"; do
            # Trim whitespace
            PORT_SPEC=$(echo "$PORT_SPEC" | xargs)
            
            # Check if protocol is specified
            if [[ "$PORT_SPEC" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
                # Port with protocol: 8080/tcp or 53/udp
                PORT="${BASH_REMATCH[1]}"
                PROTOCOL="${BASH_REMATCH[2]}"
                
                if [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
                    ufw allow ${PORT}/${PROTOCOL} comment "Custom ${PROTOCOL} port"
                    print_message "UFW rule added: Allow port %s/%s" "${PORT}" "${PROTOCOL}"

                else
                    print_warning "Invalid port number: %s (must be 1-65535). Skipping." "$PORT"

                fi
            elif [[ "$PORT_SPEC" =~ ^[0-9]+$ ]]; then
                # Port without protocol - default to tcp
                PORT="$PORT_SPEC"
                
                if [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
                    ufw allow ${PORT}/tcp comment "Custom tcp port"
                    print_message "UFW rule added: Allow port %s/tcp (default)" "${PORT}"

                else
                    print_warning "Invalid port number: %s (must be 1-65535). Skipping." "$PORT"

                fi
            else
                print_warning "Invalid port format: %s. Expected: PORT or PORT/PROTOCOL. Skipping." "$PORT_SPEC"

            fi
        done
        
        print_message "Custom ports configuration completed"
    fi
    
    # Enable UFW
    print_message "Enabling UFW..."
    echo "y" | ufw enable || print_error "Failed to enable UFW"
    ufw status verbose || true
else
    print_message "Skipping UFW configuration (not requested)"
fi

# Configure ICMP blocking in UFW
if [ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ]; then
    print_message "Configuring ICMP blocking in UFW..."
    
    UFW_BEFORE_RULES="/etc/ufw/before.rules"
    
    # Check if ICMP blocking is already configured
    if grep -q "icmp-type echo-request -j DROP" "$UFW_BEFORE_RULES"; then
        print_warning "ICMP blocking is already configured in before.rules"
        print_message "Skipping ICMP configuration to avoid duplicates"
    else
        # Backup original before.rules
        if [ -f "$UFW_BEFORE_RULES" ]; then
            # Save original permissions (numeric format for chmod)
            ORIGINAL_PERMS=$(stat -c "%a" "$UFW_BEFORE_RULES" 2>/dev/null || \
                            stat -f "%A" "$UFW_BEFORE_RULES" 2>/dev/null | tail -c 4)
            
            cp "$UFW_BEFORE_RULES" "/etc/ufw/before.rules.backup.$(date +%Y%m%d-%H%M%S)~"
            print_message "Original before.rules backed up"
        fi
        
        # Check if the ICMP section exists
        if grep -q "# ok icmp codes for INPUT" "$UFW_BEFORE_RULES"; then
            print_message "Found ICMP section in before.rules"
            
            # Create a temporary file for modifications
            TEMP_FILE=$(mktemp)
            
            # Process the file and replace ICMP rules
            awk '
            /# ok icmp codes for INPUT/ {
                print "# ok icmp codes for INPUT"
                print "-A ufw-before-input -p icmp --icmp-type destination-unreachable -j DROP"
                print "-A ufw-before-input -p icmp --icmp-type source-quench -j DROP"
                print "-A ufw-before-input -p icmp --icmp-type time-exceeded -j DROP"
                print "-A ufw-before-input -p icmp --icmp-type parameter-problem -j DROP"
                print "-A ufw-before-input -p icmp --icmp-type echo-request -j DROP"
                
                # Skip all lines that start with -A ufw-before-input -p icmp
                while (getline > 0) {
                    if ($0 !~ /^-A ufw-before-input -p icmp/) {
                        print
                        break
                    }
                }
                next
            }
            { print }
            ' "$UFW_BEFORE_RULES" > "$TEMP_FILE"
            
            # Verify the temporary file is not empty
            if [ -s "$TEMP_FILE" ]; then
                # Replace original file
                mv "$TEMP_FILE" "$UFW_BEFORE_RULES"
                
                # Restore original permissions
                if [ ! -z "$ORIGINAL_PERMS" ]; then
                    chmod "$ORIGINAL_PERMS" "$UFW_BEFORE_RULES"
                    print_message "Restored original file permissions: %s" "$ORIGINAL_PERMS"

                else
                    # Set default permissions if we couldn't detect them
                    chmod 640 "$UFW_BEFORE_RULES"
                    print_message "Set default file permissions: 640"
                fi
                
                print_message "ICMP blocking configured successfully"
                
                # Reload UFW to apply changes
                print_message "Reloading UFW to apply ICMP blocking..."
                ufw reload || print_warning "Failed to reload UFW"
                print_message "UFW reloaded"
            else
                print_error "Failed to modify before.rules (temporary file is empty)"
                rm -f "$TEMP_FILE"
            fi
        else
            print_warning "ICMP section not found in before.rules"
            print_warning "Skipping ICMP blocking configuration"
        fi
        
        print_message "ICMP (ping) requests are now blocked"
        print_message "Your server will not respond to ping"
    fi
else
    if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
        print_message "ICMP blocking not requested - server will respond to ping"
    fi
fi

# ============================================
# INSTALL DOCKER
# ============================================

# Install Docker if requested
if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
    print_message "Installing Docker..."
    echo ""
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version 2>/dev/null || echo "unknown")
        print_warning "Docker is already installed: %s" "$DOCKER_VERSION"

        read -p "$(t "Do you want to reinstall Docker? (y/N): ")" REINSTALL_DOCKER
        REINSTALL_DOCKER=${REINSTALL_DOCKER:-n}
        
        if [ "$REINSTALL_DOCKER" != "y" ] && [ "$REINSTALL_DOCKER" != "Y" ]; then
            print_message "Skipping Docker installation"
            DOCKER_INSTALLED="yes"
        else
            print_message "Reinstalling Docker..."
            # Use Docker's official installation script
            if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh; then
                if sh /tmp/get-docker.sh; then
                    rm -f /tmp/get-docker.sh
                    print_message "Docker installed successfully"
                    DOCKER_INSTALLED="yes"
                else
                    rm -f /tmp/get-docker.sh
                    print_error "Docker installation script failed (check network/DNS)"
                    DOCKER_INSTALLED="no"
                fi
            else
                print_error "Failed to download Docker installation script"
                DOCKER_INSTALLED="no"
            fi
        fi
    else
        # Install Docker using official script
        print_message "Downloading Docker installation script..."
        if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh; then
            print_message "Running Docker installation script..."
            if sh /tmp/get-docker.sh; then
                rm -f /tmp/get-docker.sh
                print_message "Docker installed successfully"
                DOCKER_INSTALLED="yes"
            else
                rm -f /tmp/get-docker.sh
                print_error "Docker installation script failed (check network/DNS)"
                DOCKER_INSTALLED="no"
            fi

            # Start and enable Docker (only if installed)
            if [ "$DOCKER_INSTALLED" = "yes" ]; then
                systemctl start docker || print_warning "Failed to start Docker"
                systemctl enable docker || print_warning "Failed to enable Docker"
            
            # Ensure docker group exists
            if ! getent group docker > /dev/null 2>&1; then
                print_message "Creating docker group..."
                groupadd docker
            fi
            
            # Add new user to docker group if created
            if [ ! -z "$NEW_USERNAME" ]; then
                usermod -aG docker "$NEW_USERNAME"
                print_message "User %s added to docker group" "$NEW_USERNAME"

                
                # Note about newgrp
                print_message "To activate docker group without logout, user can run: newgrp docker"
            fi
            
            # Add current user to docker group if not root
            if [ ! -z "$SUDO_USER" ] && [ "$SUDO_USER" != "$NEW_USERNAME" ]; then
                usermod -aG docker $SUDO_USER
                print_message "User %s added to docker group" "$SUDO_USER"

            fi
            
            if [ ! -z "$NEW_USERNAME" ] || [ ! -z "$SUDO_USER" ]; then
                print_warning "Users need to log out and log back in (or run 'newgrp docker') for docker group to take effect"
            fi
            fi  # end of DOCKER_INSTALLED=yes block
        else
            print_error "Failed to download Docker installation script"
            DOCKER_INSTALLED="no"
        fi
    fi
    
    # Verify Docker installation
    if [ "$DOCKER_INSTALLED" = "yes" ]; then
        if docker --version &> /dev/null; then
            print_message "Docker version: %s" "$(docker --version)"

            if docker compose version &> /dev/null; then
                print_message "Docker Compose version: %s" "$(docker compose version)"

            fi
        fi
    fi
    
    echo ""
else
    print_message "Skipping Docker installation (not requested)"
    DOCKER_INSTALLED="no"
fi

# Install ufw-docker (independent of Docker installation)
if [ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ]; then
    print_message "Installing ufw-docker..."
    
    if wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker; then
        chmod +x /usr/local/bin/ufw-docker
        print_message "ufw-docker downloaded successfully"
        
        # Run ufw-docker install
        print_message "Configuring ufw-docker..."
        /usr/local/bin/ufw-docker install
        print_message "ufw-docker configured successfully"
        
        if ! command -v docker &> /dev/null; then
            print_warning "Note: Docker is not installed. ufw-docker will be ready when you install Docker."
        fi
    else
        print_error "Failed to download ufw-docker"
    fi
else
    print_message "Skipping ufw-docker installation (not requested)"
fi

# ============================================
# INSTALL GO LANGUAGE
# ============================================

if [ "$INSTALL_GO" = "y" ] || [ "$INSTALL_GO" = "Y" ]; then
    if [ -z "$NEW_USERNAME" ]; then
        print_warning "Cannot install Go: No user was created"
        print_warning "Go installation requires a non-root user"
    else
        print_message "Installing latest version of Go for user %s..." "$NEW_USERNAME"

        echo ""
        
        USER_HOME=$(getent passwd "$NEW_USERNAME" | cut -d: -f6)
        
        # Get the latest Go version from official website
        print_message "Fetching latest Go version..."
        LATEST_GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -1)
        
        if [ -z "$LATEST_GO_VERSION" ]; then
            print_warning "Could not fetch latest Go version, using fallback: go1.23.4"
            LATEST_GO_VERSION="go1.23.4"
        fi
        
        print_message "Latest Go version: %s" "$LATEST_GO_VERSION"


        # Detect system architecture
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)
                GO_ARCH="amd64"
                ;;
            aarch64|arm64)
                GO_ARCH="arm64"
                ;;
            armv6l)
                GO_ARCH="armv6l"
                ;;
            i386|i686)
                GO_ARCH="386"
                ;;
            *)
                print_error "Unsupported architecture: %s" "$ARCH"

                print_error "Go installation skipped"
                GO_ARCH=""
                ;;
        esac

        if [ -z "$GO_ARCH" ]; then
            # Skip Go installation for unsupported architectures
            :
        else
            print_message "Detected architecture: %s (Go architecture: %s)" "$ARCH" "$GO_ARCH"


            # Download Go
            GO_ARCHIVE="${LATEST_GO_VERSION}.linux-${GO_ARCH}.tar.gz"
            GO_URL="https://go.dev/dl/${GO_ARCHIVE}"

            print_message "Downloading Go from: %s" "$GO_URL"

            if wget -q --show-progress "$GO_URL" -O "/tmp/${GO_ARCHIVE}"; then
                print_message "Go downloaded successfully"

                # Remove old Go installation
                if [ -d /usr/local/go ]; then
                    print_message "Removing old Go installation..."
                    rm -rf /usr/local/go
                fi

                # Extract Go
                print_message "Extracting Go..."
                tar -C /usr/local -xzf "/tmp/${GO_ARCHIVE}"
                print_message "Go extracted to /usr/local/go"

                # Cleanup
                rm "/tmp/${GO_ARCHIVE}"

                # Add Go to PATH for the user
                print_message "Configuring Go environment for %s..." "$NEW_USERNAME"


                # Determine which shell config file to use
                if [ -f "$USER_HOME/.zshrc" ]; then
                    SHELL_RC="$USER_HOME/.zshrc"
                elif [ -f "$USER_HOME/.bashrc" ]; then
                    SHELL_RC="$USER_HOME/.bashrc"
                else
                    SHELL_RC="$USER_HOME/.profile"
                fi

                # Add Go to PATH if not already present
                if ! grep -q "export PATH=.*:/usr/local/go/bin" "$SHELL_RC" 2>/dev/null; then
                    sudo -u "$NEW_USERNAME" bash << EOF
                        echo "" >> "$SHELL_RC"
                        echo "# Go language" >> "$SHELL_RC"
                        echo "export PATH=\$PATH:/usr/local/go/bin" >> "$SHELL_RC"
                        echo "export PATH=\$PATH:\$HOME/go/bin" >> "$SHELL_RC"
EOF
                    print_message "Go PATH added to %s" "$SHELL_RC"

                else
                    print_message "Go PATH already configured in %s" "$SHELL_RC"

                fi

                # Verify installation
                if /usr/local/go/bin/go version &> /dev/null; then
                    GO_INSTALLED_VERSION=$(/usr/local/go/bin/go version)
                    print_message "Go installed successfully: %s" "$GO_INSTALLED_VERSION"

                    print_message "Go binary location: /usr/local/go/bin/go"
                    print_message "User %s can use Go after reloading shell or running: source %s" "$NEW_USERNAME" "$SHELL_RC"

                else
                    print_error "Go installation verification failed"
                fi
            else
                print_error "Failed to download Go"
            fi
        fi

        echo ""
    fi
else
    print_message "Skipping Go installation (not requested)"
fi

# ============================================
# BUILD AND INSTALL IPSET
# ============================================

if [ "$INSTALL_IPSET" = "y" ] || [ "$INSTALL_IPSET" = "Y" ]; then
    print_message "Building and installing latest version of ipset..."
    echo ""
    
    # Check if kernel headers are installed
    KERNEL_VERSION=$(uname -r)
    KERNEL_HEADERS_DIR="/lib/modules/${KERNEL_VERSION}/build"
    
    if [ ! -d "$KERNEL_HEADERS_DIR" ]; then
        print_error "Kernel headers not found at: %s" "$KERNEL_HEADERS_DIR"

        print_error "Installing kernel headers..."
        
        if apt-get install -y linux-headers-${KERNEL_VERSION}; then
            print_message "Kernel headers installed successfully"
        else
            print_error "Failed to install kernel headers"
            print_error "ipset compilation requires kernel headers"
            print_message "Try manually: sudo apt-get install linux-headers-%s" "$(uname -r)"

            print_message "Skipping ipset installation"
            INSTALL_IPSET="n"
        fi
    else
        print_message "Kernel headers found: %s" "$KERNEL_HEADERS_DIR"

    fi
    
    if [ "$INSTALL_IPSET" = "y" ] || [ "$INSTALL_IPSET" = "Y" ]; then
        # Get the latest ipset version
        print_message "Fetching latest ipset version..."
        LATEST_IPSET_VERSION=$(curl -s https://ipset.netfilter.org/ | grep -oP 'ipset-\K[0-9]+\.[0-9]+' | head -1)
        
        if [ -z "$LATEST_IPSET_VERSION" ]; then
            print_warning "Could not fetch latest ipset version, using fallback: 7.24"
            LATEST_IPSET_VERSION="7.24"
        fi
        
        print_message "Latest ipset version: %s" "$LATEST_IPSET_VERSION"

        
        # Download ipset
        IPSET_ARCHIVE="ipset-${LATEST_IPSET_VERSION}.tar.bz2"
        IPSET_URL="https://ipset.netfilter.org/${IPSET_ARCHIVE}"
        
        print_message "Downloading ipset from: %s" "$IPSET_URL"

        if wget -q --show-progress "$IPSET_URL" -O "/tmp/${IPSET_ARCHIVE}"; then
            print_message "ipset downloaded successfully"
            
            # Extract and build ipset in a subshell to avoid changing working directory
            print_message "Extracting ipset..."
            (
                cd /tmp
                tar xjf "${IPSET_ARCHIVE}"

                IPSET_DIR="ipset-${LATEST_IPSET_VERSION}"

                if [ -d "/tmp/${IPSET_DIR}" ]; then
                    cd "/tmp/${IPSET_DIR}"

                    # Configure with proper kernel source
                    print_message "Configuring ipset with kernel headers..."
                    if ./configure --prefix=/usr --with-kmod=no; then
                        print_message "Configuration successful"

                        # Build
                        print_message "Building ipset (using %s cores)..." "$(nproc)"

                        if make -j$(nproc); then
                            print_message "Build successful"

                            # Install
                            print_message "Installing ipset..."
                            if make install; then
                                print_message "ipset installed successfully"

                                # Verify installation
                                if ipset --version &> /dev/null; then
                                    IPSET_INSTALLED_VERSION=$(ipset --version)
                                    print_message "ipset version: %s" "$IPSET_INSTALLED_VERSION"

                                else
                                    print_warning "ipset installed but version check failed"
                                fi
                            else
                                print_error "Failed to install ipset"
                            fi
                        else
                            print_error "Failed to build ipset"
                        fi
                    else
                        print_error "Failed to configure ipset"
                        print_error "Check that kernel headers are properly installed"
                    fi
                else
                    print_error "Failed to extract ipset archive contents"
                fi

                # Cleanup
                rm -rf "/tmp/${IPSET_DIR}" "/tmp/${IPSET_ARCHIVE}"
            )
        else
            print_error "Failed to download ipset"
        fi
    fi
    
    echo ""
else
    print_message "Skipping ipset installation (not requested)"
fi

# ============================================
# CREATE PYTHON VIRTUAL ENVIRONMENT
# ============================================

# Create Python virtual environment
if [ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ]; then
    print_message "Creating Python virtual environment..."
    
    # Create directory if it doesn't exist
    VENV_DIR=$(dirname "$VENV_PATH")
    if [ ! -d "$VENV_DIR" ]; then
        mkdir -p "$VENV_DIR"
        print_message "Created directory: %s" "$VENV_DIR"

    fi
    
    # Create virtual environment
    print_message "Creating venv at: %s" "$VENV_PATH"

    if python3 -m venv "$VENV_PATH"; then
        print_message "Virtual environment created successfully"
        
        # Activate virtual environment and install packages
        print_message "Installing Python packages..."
        source "$VENV_PATH/bin/activate"
        
        # Upgrade pip first
        pip install --upgrade pip
        
        # Install packages
        pip install --upgrade \
            requests \
            psutil \
            pytz \
            uvloop \
            ipaddress \
            pathlib \
            python-telegram-bot \
            nest_asyncio \
            aiohttp \
            charset-normalizer \
            maxminddb \
            geoipsets \
            setuptools \
            wheel \
            pip \
            passlib \
            bcrypt \
            tqdm \
            colorama \
            humanize \
            termcolor \
            rich \
            "python-telegram-bot[job-queue]" \
            urllib3 \
            chardet
        
        print_message "Python packages installed successfully"
        print_message "Virtual environment location: %s" "$VENV_PATH"

        print_message "To activate: source %s/bin/activate" "$VENV_PATH"

        
        deactivate
    else
        print_error "Failed to create virtual environment"
    fi
else
    print_message "Skipping Python virtual environment creation (not requested)"
fi

# ============================================
# CONFIGURE CRONTAB
# ============================================

if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
    print_message "Configuring crontab for root..."
    
    # Backup existing crontab
    if crontab -l &>/dev/null; then
        crontab -l > /tmp/crontab.backup.$(date +%Y%m%d-%H%M%S)~
        print_message "Existing crontab backed up"
    fi
    
    # Create new crontab content with environment variables
    CRONTAB_CONTENT="# Crontab environment variables
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOME=/root
MAILTO=\"\"
LANG=en_US.UTF-8
"
    
    # Add custom tasks if provided
    if [ ! -z "$CRONTAB_TASKS" ]; then
        CRONTAB_CONTENT="${CRONTAB_CONTENT}
# Custom cron tasks
${CRONTAB_TASKS}"
    fi
    
    # Install new crontab
    echo "$CRONTAB_CONTENT" | crontab -
    print_message "Crontab configured successfully"
    
    # Display configured crontab
    print_message "Configured crontab:"
    echo "----------------------------------------"
    crontab -l
    echo "----------------------------------------"
    echo ""
else
    print_message "Skipping crontab configuration (not requested)"
fi

# ============================================
# INSTALL CUSTOM MOTD
# ============================================

# Install custom MOTD
if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    print_message "Installing custom MOTD (Message of the Day)..."
    echo ""
    
    MOTD_SCRIPT="/tmp/motd_install.sh"
    
    if [ "$OS" = "debian" ]; then
        MOTD_URL="https://raw.githubusercontent.com/civisrom/motd-ubuntu-debian/refs/heads/main/scripts/debian.sh"
    else
        MOTD_URL="https://raw.githubusercontent.com/civisrom/motd-ubuntu-debian/refs/heads/main/scripts/ubuntu.sh"
    fi
    
    print_message "Downloading MOTD installation script for %s..." "$OS"

    if curl -fsSL "$MOTD_URL" -o "$MOTD_SCRIPT"; then
        chmod +x "$MOTD_SCRIPT"
        print_message "Running MOTD installation script..."
        
        if bash "$MOTD_SCRIPT"; then
            print_message "Custom MOTD installed successfully"
            rm -f "$MOTD_SCRIPT"
            
            # Post-installation fixes for MOTD
            print_message "Applying MOTD post-installation fixes..."
            
            # Initialize SSH restart flag
            SSH_RESTART_NEEDED=false
            
            # 1. Ensure all scripts in /etc/update-motd.d/ are executable
            if [ -d /etc/update-motd.d ]; then
                chmod +x /etc/update-motd.d/* 2>/dev/null
                # Also ensure directory permissions are correct
                chmod 755 /etc/update-motd.d
                print_message "Set executable permissions on MOTD scripts and directory"
            fi
            
            # 2. Check and fix SSH configuration for MOTD
            SSHD_CONFIG="/etc/ssh/sshd_config"
            if [ -f "$SSHD_CONFIG" ]; then
                # Backup SSH config if not already backed up
                if [ ! -f "${SSHD_CONFIG}.backup.motd~" ]; then
                    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.motd~"
                fi
                
                # Check UsePAM parameter (must be yes for MOTD)
                if grep -q "^UsePAM no" "$SSHD_CONFIG"; then
                    sed -i 's/^UsePAM no/UsePAM yes/' "$SSHD_CONFIG"
                    print_message "Enabled UsePAM in SSH config (required for MOTD)"
                    SSH_RESTART_NEEDED=true
                fi
                
                # Check PrintMotd parameter
                if grep -q "^PrintMotd" "$SSHD_CONFIG"; then
                    # Parameter exists, ensure it's set to yes
                    if ! grep -q "^PrintMotd yes" "$SSHD_CONFIG"; then
                        sed -i 's/^PrintMotd.*/PrintMotd yes/' "$SSHD_CONFIG"
                        print_message "Enabled PrintMotd in SSH config"
                        SSH_RESTART_NEEDED=true
                    fi
                else
                    # Parameter doesn't exist, add it
                    echo "" >> "$SSHD_CONFIG"
                    echo "# Enable MOTD" >> "$SSHD_CONFIG"
                    echo "PrintMotd yes" >> "$SSHD_CONFIG"
                    print_message "Added PrintMotd to SSH config"
                    SSH_RESTART_NEEDED=true
                fi
                
                # Ensure PrintLastLog is no (conflicts with custom MOTD)
                if grep -q "^PrintLastLog yes" "$SSHD_CONFIG"; then
                    sed -i 's/^PrintLastLog yes/PrintLastLog no/' "$SSHD_CONFIG"
                    print_message "Disabled PrintLastLog to avoid conflicts"
                    SSH_RESTART_NEEDED=true
                fi
                
                # Restart SSH if needed
                if [ "$SSH_RESTART_NEEDED" = true ]; then
                    print_message "Restarting SSH service for MOTD changes..."
                    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
                        print_success "SSH service restarted successfully"
                    else
                        print_warning "Could not restart SSH automatically, please restart manually"
                    fi
                fi
            fi
            
            # 3. Disable static MOTD file if exists
            if [ -f /etc/motd ]; then
                mv /etc/motd /etc/motd.backup.$(date +%Y%m%d-%H%M%S)~
                touch /etc/motd
                print_message "Disabled static /etc/motd file"
            fi
            
            # 4. Check PAM configuration
            PAM_SSHD="/etc/pam.d/sshd"
            if [ -f "$PAM_SSHD" ]; then
                # Backup PAM config
                if [ ! -f "${PAM_SSHD}.backup.motd~" ]; then
                    cp "$PAM_SSHD" "${PAM_SSHD}.backup.motd~"
                fi
                
                if ! grep -q "pam_motd.so" "$PAM_SSHD"; then
                    print_warning "PAM MOTD module not found in %s" "$PAM_SSHD"

                    print_message "Adding pam_motd.so to PAM configuration..."
                    echo "" >> "$PAM_SSHD"
                    echo "# Display MOTD" >> "$PAM_SSHD"
                    echo "session optional pam_motd.so motd=/run/motd.dynamic" >> "$PAM_SSHD"
                    echo "session optional pam_motd.so noupdate" >> "$PAM_SSHD"
                    print_message "PAM MOTD configuration added"
                else
                    print_message "PAM MOTD module already configured"
                fi
            else
                print_warning "PAM SSH config not found: %s" "$PAM_SSHD"

            fi
            
            # 5. Install run-parts if not available
            if ! command -v run-parts &> /dev/null; then
                print_warning "run-parts not found, installing debianutils..."
                apt-get install -y debianutils || print_warning "Failed to install debianutils"
            fi
            
            # 6. Ensure /run/motd.dynamic can be created (it's a file, not directory)
            # PAM will create this file automatically when needed
            # Just verify /run directory exists (it always does on modern systems)
            if [ ! -d /run ]; then
                print_warning "/run directory does not exist (unusual)"
            else
                # Remove /run/motd.dynamic if it's incorrectly a directory
                if [ -d /run/motd.dynamic ]; then
                    print_warning "/run/motd.dynamic exists as directory, removing..."
                    rm -rf /run/motd.dynamic
                    print_message "Removed incorrect directory /run/motd.dynamic"
                fi
                # Create empty file if it doesn't exist (optional, PAM will create it)
                if [ ! -f /run/motd.dynamic ]; then
                    touch /run/motd.dynamic 2>/dev/null || true
                    print_message "Prepared /run/motd.dynamic file"
                fi
            fi
            
            # 7. Test MOTD generation
            print_message "Testing MOTD generation..."
            if command -v run-parts &> /dev/null; then
                if run-parts /etc/update-motd.d/ > /tmp/motd-test.txt 2>&1; then
                    print_success "MOTD scripts executed successfully"
                    
                    # Check if output was generated
                    if [ -s /tmp/motd-test.txt ]; then
                        print_message "MOTD content generated successfully"
                    else
                        print_warning "MOTD scripts ran but produced no output"
                    fi
                else
                    print_warning "Some MOTD scripts may have errors"
                    print_message "Error details:"
                    cat /tmp/motd-test.txt
                fi
                rm -f /tmp/motd-test.txt
            else
                print_warning "Cannot test MOTD without run-parts"
            fi
            
            # 8. Display current MOTD preview
            echo ""
            print_header "═══════════════════════════════════════════════"
            print_header "   MOTD Preview (will be shown on SSH login)"
            print_header "═══════════════════════════════════════════════"
            echo ""
            
            if command -v run-parts &> /dev/null && [ -d /etc/update-motd.d ]; then
                run-parts /etc/update-motd.d/ 2>/dev/null || echo "MOTD generation failed - please run: run-parts /etc/update-motd.d/"
            else
                print_warning "Cannot display MOTD preview"
            fi
            
            echo ""
            print_header "═══════════════════════════════════════════════"
            echo ""
            
            # Summary of MOTD configuration
            print_success "MOTD configuration completed successfully!"
            print_message "What was configured:"
            print_message "  ✓ MOTD scripts installed in /etc/update-motd.d/"
            print_message "  ✓ SSH configured to display MOTD"
            print_message "  ✓ PAM configured for MOTD"
            print_message "  ✓ Static MOTD file disabled"
            print_message ""
            print_warning "Important: MOTD will be visible on your NEXT SSH login"
            print_message "To test now: exit and reconnect via SSH"
            echo ""
            
            
        else
            print_warning "MOTD installation completed with warnings"
            rm -f "$MOTD_SCRIPT"
        fi
    else
        print_error "Failed to download MOTD installation script"
    fi
    
    echo ""
else
    print_message "Skipping MOTD installation (not requested)"
fi

# ============================================
# INSTALL CUSTOM UFW DOCKER RULES
# ============================================

if [ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ]; then
    print_message "Installing custom UFW Docker rules (v%s)..." "${UFW_RULES_VERSION}"

    echo ""

    UFW_SCRIPT_NAME="ufw-docker-rules-v${UFW_RULES_VERSION}.sh"
    UFW_INSTALL_PATH="/opt/${UFW_SCRIPT_NAME}"

    # Check installation source
    if [ "$UFW_INSTALL_SOURCE" = "2" ]; then
        # Install from public repository
        print_message "Installing from public repository..."
        UFW_REPO_URL="https://raw.githubusercontent.com/civisrom/ufw-rules-docker/refs/heads/main/ufw-docker-rules-v${UFW_RULES_VERSION}.sh"

        print_message "Downloading script from repository..."
        if wget -q --show-progress "$UFW_REPO_URL" -O "$UFW_INSTALL_PATH"; then
            print_message "Script downloaded successfully"

            # Replace SSH port in script if custom port is specified
            if [ -n "$UFW_SSH_PORT" ] && [ "$UFW_SSH_PORT" != "22" ]; then
                print_message "Configuring script to use custom SSH port: %s" "$UFW_SSH_PORT"

                # Replace hardcoded SSH_PORT=22 with custom port
                if sed -i "s/^SSH_PORT=22$/SSH_PORT=$UFW_SSH_PORT/" "$UFW_INSTALL_PATH"; then
                    print_message "SSH port configured successfully in ufw-docker-rules-v%s.sh" "${UFW_RULES_VERSION}"

                fi
                # Also replace SSH_PORT=${SSH_PORT:-22} pattern if exists
                sed -i "s/^SSH_PORT=\${SSH_PORT:-22}$/SSH_PORT=$UFW_SSH_PORT/" "$UFW_INSTALL_PATH"
            fi

            # Set executable permissions
            chmod +x "$UFW_INSTALL_PATH"
            print_message "Script installed with executable permissions"

            # Execute the script
            print_message "Executing custom UFW Docker rules script..."
            if [ -n "$UFW_SSH_PORT" ]; then
                print_message "Using custom SSH port: %s" "$UFW_SSH_PORT"

            fi
            echo ""
            print_header "═══════════════════════════════════════════════════"
            print_header "  Custom UFW Docker Rules Script Output (v%s)" "${UFW_RULES_VERSION}"

            print_header "═══════════════════════════════════════════════════"
            echo ""

            if [ -n "$UFW_SSH_PORT" ]; then
                # Execute with SSH_PORT environment variable
                if SSH_PORT="$UFW_SSH_PORT" bash "$UFW_INSTALL_PATH"; then
                    echo ""
                    print_header "═══════════════════════════════════════════════════"
                    print_message "Custom UFW Docker rules applied successfully"
                else
                    echo ""
                    print_header "═══════════════════════════════════════════════════"
                    print_warning "Custom UFW Docker rules script completed with warnings"
                fi
            else
                # Execute without custom SSH_PORT
                if bash "$UFW_INSTALL_PATH"; then
                    echo ""
                    print_header "═══════════════════════════════════════════════════"
                    print_message "Custom UFW Docker rules applied successfully"
                else
                    echo ""
                    print_header "═══════════════════════════════════════════════════"
                    print_warning "Custom UFW Docker rules script completed with warnings"
                fi
            fi
        else
            print_error "Failed to download script from repository"
            print_error "URL: %s" "$UFW_REPO_URL"

        fi
    else
        # Install from password-protected archive
        print_message "Installing from password-protected archive..."

        # Check if p7zip is installed, install if needed
        if ! command -v 7z &> /dev/null; then
            print_message "Installing p7zip-full for archive extraction..."
            if apt-get install -y p7zip-full; then
                print_message "p7zip-full installed successfully"
            else
                print_error "CRITICAL: Failed to install p7zip-full"
                print_error "Installation cannot continue"
                exit 1
            fi
        fi

        UFW_ARCHIVE_URL="https://github.com/civisrom/debian-ubuntu-setup/raw/refs/heads/main/config/ufw-docker-rules-v4.7z"
        UFW_ARCHIVE_FILE="/tmp/ufw-docker-rules-v4.7z"
        UFW_EXTRACT_DIR="/tmp/ufw-docker-rules"

        print_message "Downloading custom UFW rules archive..."
        if wget -q --show-progress "$UFW_ARCHIVE_URL" -O "$UFW_ARCHIVE_FILE"; then
            print_message "Archive downloaded successfully"

            # Create extraction directory
            mkdir -p "$UFW_EXTRACT_DIR"

            # Extract with password (using temporary password file for security)
            print_message "Extracting archive..."
            UFW_PASS_FILE=$(mktemp)
            chmod 600 "$UFW_PASS_FILE"
            printf "%s" "${UFW_CUSTOM_RULES_PASSWORD}" > "$UFW_PASS_FILE"
            if 7z x "-p$(cat "$UFW_PASS_FILE")" -o"${UFW_EXTRACT_DIR}" "$UFW_ARCHIVE_FILE" -y > /dev/null 2>&1; then
                rm -f "$UFW_PASS_FILE"
                print_message "Archive extracted successfully"

                # Find and install the script file
                SCRIPT_FOUND=false

                # Check in root of extraction
                if [ -f "${UFW_EXTRACT_DIR}/${UFW_SCRIPT_NAME}" ]; then
                    SCRIPT_SOURCE="${UFW_EXTRACT_DIR}/${UFW_SCRIPT_NAME}"
                    SCRIPT_FOUND=true
                # Check in opt folder
                elif [ -f "${UFW_EXTRACT_DIR}/opt/${UFW_SCRIPT_NAME}" ]; then
                    SCRIPT_SOURCE="${UFW_EXTRACT_DIR}/opt/${UFW_SCRIPT_NAME}"
                    SCRIPT_FOUND=true
                # Check in opt/scripts folder
                elif [ -f "${UFW_EXTRACT_DIR}/opt/scripts/${UFW_SCRIPT_NAME}" ]; then
                    SCRIPT_SOURCE="${UFW_EXTRACT_DIR}/opt/scripts/${UFW_SCRIPT_NAME}"
                    SCRIPT_FOUND=true
                fi

                if [ "$SCRIPT_FOUND" = true ]; then
                    print_message "Found script: %s" "$UFW_SCRIPT_NAME"

                    print_message "Installing script to %s..." "${UFW_INSTALL_PATH}"


                    # Copy script to /opt if not already there from archive extraction
                    if [ ! -f "$UFW_INSTALL_PATH" ]; then
                        cp "$SCRIPT_SOURCE" "$UFW_INSTALL_PATH"
                    fi

                    # Set executable permissions
                    chmod +x "$UFW_INSTALL_PATH"
                    print_message "Script installed with executable permissions"

                    # Replace SSH port in script if custom port is specified
                    if [ -n "$UFW_SSH_PORT" ] && [ "$UFW_SSH_PORT" != "22" ]; then
                        print_message "Configuring script to use custom SSH port: %s" "$UFW_SSH_PORT"

                        # Replace hardcoded SSH_PORT=22 with custom port
                        if sed -i "s/^SSH_PORT=22$/SSH_PORT=$UFW_SSH_PORT/" "$UFW_INSTALL_PATH"; then
                            print_message "SSH port configured successfully in ufw-docker-rules-v%s.sh" "${UFW_RULES_VERSION}"

                        fi
                        # Also replace SSH_PORT=${SSH_PORT:-22} pattern if exists
                        sed -i "s/^SSH_PORT=\${SSH_PORT:-22}$/SSH_PORT=$UFW_SSH_PORT/" "$UFW_INSTALL_PATH"
                    fi

                    # Execute the script
                    print_message "Executing custom UFW Docker rules script..."
                    if [ -n "$UFW_SSH_PORT" ]; then
                        print_message "Using custom SSH port: %s" "$UFW_SSH_PORT"

                    fi
                    echo ""
                    print_header "═══════════════════════════════════════════════════"
                    print_header "  Custom UFW Docker Rules Script Output (v%s)" "${UFW_RULES_VERSION}"

                    print_header "═══════════════════════════════════════════════════"
                    echo ""

                    if [ -n "$UFW_SSH_PORT" ]; then
                        # Execute with SSH_PORT environment variable
                        if SSH_PORT="$UFW_SSH_PORT" bash "$UFW_INSTALL_PATH"; then
                            echo ""
                            print_header "═══════════════════════════════════════════════════"
                            print_message "Custom UFW Docker rules applied successfully"
                        else
                            echo ""
                            print_header "═══════════════════════════════════════════════════"
                            print_warning "Custom UFW Docker rules script completed with warnings"
                        fi
                    else
                        # Execute without custom SSH_PORT
                        if bash "$UFW_INSTALL_PATH"; then
                            echo ""
                            print_header "═══════════════════════════════════════════════════"
                            print_message "Custom UFW Docker rules applied successfully"
                        else
                            echo ""
                            print_header "═══════════════════════════════════════════════════"
                            print_warning "Custom UFW Docker rules script completed with warnings"
                        fi
                    fi
                else
                    print_error "Script file not found in archive: %s" "${UFW_SCRIPT_NAME}"

                    print_error "Checked locations:"
                    print_error "  - %s/%s" "${UFW_EXTRACT_DIR}" "${UFW_SCRIPT_NAME}"

                    print_error "  - %s/opt/%s" "${UFW_EXTRACT_DIR}" "${UFW_SCRIPT_NAME}"

                    print_error "  - %s/opt/scripts/%s" "${UFW_EXTRACT_DIR}" "${UFW_SCRIPT_NAME}"

                fi

                # Cleanup extraction directory
                rm -rf "$UFW_EXTRACT_DIR"

                # Delete archive
                rm -f "$UFW_ARCHIVE_FILE"
                print_message "Archive deleted"
            else
                print_error "Failed to extract archive. Check if password is correct."
                print_error "Password authentication failed or archive is corrupted"
                rm -f "$UFW_PASS_FILE"
                rm -f "$UFW_ARCHIVE_FILE"
            fi
        else
            print_error "Failed to download custom UFW rules archive"
        fi
    fi

    echo ""
else
    print_message "Skipping custom UFW Docker rules (not requested)"
fi

# ============================================
# EXTRACT OPT.7Z ARCHIVE TO /OPT
# ============================================

if [ "$EXTRACT_OPT_ARCHIVE" = "y" ] || [ "$EXTRACT_OPT_ARCHIVE" = "Y" ]; then
    echo ""
    print_header "═══════════════════════════════════════════════════"
    print_header "   Extracting opt.7z Archive to /opt"
    print_header "═══════════════════════════════════════════════════"
    echo ""

    # Check if p7zip is installed, install if needed
    if ! command -v 7z &> /dev/null; then
        print_message "Installing p7zip-full for archive extraction..."
        if apt-get install -y p7zip-full; then
            print_message "p7zip-full installed successfully"
        else
            print_error "CRITICAL: Failed to install p7zip-full"
            print_error "Cannot extract opt.7z archive"
        fi
    fi

    # Only proceed if 7z is available
    if command -v 7z &> /dev/null; then
        OPT_ARCHIVE_URL="https://github.com/civisrom/debian-ubuntu-setup/raw/refs/heads/main/config/opt.7z"
        OPT_ARCHIVE_FILE="/tmp/opt.7z"
        OPT_EXTRACT_DIR="/tmp/opt_extract"

        print_message "Downloading opt.7z archive for /opt files..."
        if wget -q --show-progress "$OPT_ARCHIVE_URL" -O "$OPT_ARCHIVE_FILE"; then
            print_message "opt.7z archive downloaded successfully"

            # Create extraction directory
            mkdir -p "$OPT_EXTRACT_DIR"

            # Extract with password (using temporary password file for security)
            print_message "Extracting opt.7z archive..."
            OPT_PASS_FILE=$(mktemp)
            chmod 600 "$OPT_PASS_FILE"
            printf "%s" "${OPT_ARCHIVE_PASSWORD}" > "$OPT_PASS_FILE"
            if 7z x "-p$(cat "$OPT_PASS_FILE")" -o"${OPT_EXTRACT_DIR}" "$OPT_ARCHIVE_FILE" -y > /dev/null 2>&1; then
                rm -f "$OPT_PASS_FILE"
                print_message "opt.7z archive extracted successfully"

                # Copy all contents to /opt
                print_message "Copying files and folders to /opt..."
                if [ "$(ls -A ${OPT_EXTRACT_DIR})" ]; then
                    cp -r "${OPT_EXTRACT_DIR}/"* /opt/
                    print_message "Files copied to /opt successfully"

                    # Make scripts in scripts folder executable (except .ini files)
                    if [ -d "/opt/scripts" ]; then
                        print_message "Setting executable permissions for scripts in /opt/scripts..."

                        # Find all files in scripts directory and make them executable (except .ini)
                        find /opt/scripts -type f ! -name "*.ini" -exec chmod +x {} \;

                        # Count executable files
                        EXEC_COUNT=$(find /opt/scripts -type f ! -name "*.ini" | wc -l)
                        print_message "Made %s file(s) executable in /opt/scripts" "$EXEC_COUNT"

                    fi

                    # List what was copied
                    print_message "Contents copied to /opt:"
                    ls -la /opt/ | grep -v "^total" | tail -n +2 | awk '{print "  - " $NF}'
                else
                    print_warning "opt.7z archive is empty"
                fi

                # Cleanup
                rm -rf "$OPT_EXTRACT_DIR"
                rm -f "$OPT_ARCHIVE_FILE"
                print_message "Temporary files cleaned up"
            else
                print_error "Failed to extract opt.7z archive. Check if password is correct."
                rm -f "$OPT_PASS_FILE"
                rm -f "$OPT_ARCHIVE_FILE"
            fi
        else
            print_error "Failed to download opt.7z archive"
        fi
    fi

    echo ""
else
    print_message "Skipping opt.7z extraction (not requested)"
fi

# ============================================
# RUN BBR NETWORK OPTIMIZER
# ============================================

if [ "$RUN_BBR_OPTIMIZER" = "y" ] || [ "$RUN_BBR_OPTIMIZER" = "Y" ]; then
    echo ""
    print_header "═══════════════════════════════════════════════════"
    print_header "   Running BBR Network Optimizer"
    print_header "═══════════════════════════════════════════════════"
    echo ""
    
    BBR_SCRIPT_URL="https://raw.githubusercontent.com/civisrom/Linux_NetworkOptimizer/refs/heads/main/bbr.sh"
    BBR_SCRIPT_PATH="/tmp/bbr_optimizer.sh"
    
    print_message "Downloading BBR Network Optimizer script..."
    if curl -fsSL "$BBR_SCRIPT_URL" -o "$BBR_SCRIPT_PATH"; then
        print_message "BBR script downloaded successfully"
        chmod +x "$BBR_SCRIPT_PATH"
        
        # Create a modified version of the BBR script with optional functions
        print_message "Configuring BBR script options..."
        
        # Create a wrapper script that will call functions based on user's choices
        cat > /tmp/bbr_wrapper.sh << 'EOFWRAPPER'
#!/bin/bash

# Source the original BBR script
source /tmp/bbr_optimizer.sh

# Run selected functions based on parameters
if [ "$1" = "force_ipv4" ]; then
    force_ipv4_apt
fi

if [ "$2" = "full_update" ]; then
    full_update_upgrade
fi

if [ "$3" = "fix_hosts" ]; then
    fix_etc_hosts
fi

if [ "$4" = "fix_dns" ]; then
    fix_dns
fi

# Always run the main optimization (this is the core BBR functionality)
print_message "Applying BBR network optimizations..."
intelligent_settings
EOFWRAPPER
        
        chmod +x /tmp/bbr_wrapper.sh
        
        # Prepare parameters based on user choices
        PARAM1="skip"
        PARAM2="skip"
        PARAM3="skip"
        PARAM4="skip"
        
        if [ "$BBR_FORCE_IPV4" = "y" ] || [ "$BBR_FORCE_IPV4" = "Y" ]; then
            PARAM1="force_ipv4"
        fi
        
        if [ "$BBR_FULL_UPDATE" = "y" ] || [ "$BBR_FULL_UPDATE" = "Y" ]; then
            PARAM2="full_update"
        fi
        
        if [ "$BBR_FIX_HOSTS" = "y" ] || [ "$BBR_FIX_HOSTS" = "Y" ]; then
            PARAM3="fix_hosts"
        fi
        
        if [ "$BBR_FIX_DNS" = "y" ] || [ "$BBR_FIX_DNS" = "Y" ]; then
            PARAM4="fix_dns"
        fi
        
        print_message "Running BBR Network Optimizer with selected options..."
        print_message "Options: Force IPv4: %s, Full Update: %s, Fix Hosts: %s, Fix DNS: %s" "$PARAM1" "$PARAM2" "$PARAM3" "$PARAM4"

        echo ""
        
        # Run the wrapper script with parameters
        bash /tmp/bbr_wrapper.sh "$PARAM1" "$PARAM2" "$PARAM3" "$PARAM4"
        
        # Cleanup
        rm -f "$BBR_SCRIPT_PATH" /tmp/bbr_wrapper.sh
        
        echo ""
        print_header "═══════════════════════════════════════════════════"
        print_message "BBR Network Optimizer completed"
        print_header "═══════════════════════════════════════════════════"
        echo ""
    else
        print_error "Failed to download BBR Network Optimizer script"
        print_message "You can manually run it later from: %s" "$BBR_SCRIPT_URL"

    fi
else
    print_message "Skipping BBR Network Optimizer (not requested)"
fi

# ============================================
# FINAL MESSAGE
# ============================================

# Final message
echo ""
print_header "═════════════════════════════════════════"
print_message "System setup completed successfully!"
print_header "═════════════════════════════════════════"
print_message "Summary:"
echo -n "- " && print_message "OS: %s %s (%s)" "$OS" "$VERSION" "$VERSION_CODENAME"

print_message "- Packages installed"

if [ "$INSTALL_RUSTDESK" = "y" ] || [ "$INSTALL_RUSTDESK" = "Y" ]; then
    if systemctl is-enabled --quiet rustdesk-compose.service 2>/dev/null; then
        print_message "- RustDesk Server: Installed and enabled"
        print_message "  Directory: /opt/rustdesk"
        print_message "  Service: rustdesk-compose.service"
        if systemctl is-active --quiet rustdesk-compose.service; then
            print_message "  Status: Running"
        else
            print_message "  Status: Enabled (will start with Docker)"
        fi
    else
        print_message "- RustDesk Server: Installation attempted but service not enabled"
    fi
else
    print_message "- RustDesk Server: Not installed"
fi

if [ "$SET_ROOT_PASSWORD" = "y" ] || [ "$SET_ROOT_PASSWORD" = "Y" ]; then
    print_message "- Root password: SET"
else
    print_message "- Root password: NOT SET"
fi

if [ ! -z "$NEW_USERNAME" ]; then
    print_message "- New user created: %s" "$NEW_USERNAME"

    if [ "$CONFIGURE_USER_SSH_KEY" = "y" ] || [ "$CONFIGURE_USER_SSH_KEY" = "Y" ]; then
        print_message "  - SSH key configured"
    fi
    if [ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ]; then
        print_message "  - zsh and Oh My Zsh installed"
    fi
else
    print_message "- New user: NOT CREATED"
fi

if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
    print_message "- Crontab configured for root"
else
    print_message "- Crontab: NOT CONFIGURED"
fi

if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    print_message "- SSH configured (Port: %s, AllowUsers: %s)" "$SSH_PORT" "${SSH_ALLOW_USERS:-not set}"

    if [ ! -z "$SSH_PUBKEY_AUTH" ]; then
        print_message "  - PubkeyAuthentication: %s" "$SSH_PUBKEY_AUTH"

    fi
    if [ ! -z "$SSH_PASSWORD_AUTH" ]; then
        print_message "  - PasswordAuthentication: %s" "$SSH_PASSWORD_AUTH"

    fi
    if [ ! -z "$SSH_EMPTY_PASSWORDS" ]; then
        print_message "  - PermitEmptyPasswords: %s (security enforced)" "$SSH_EMPTY_PASSWORDS"

    fi
    if [ ! -z "$SSH_ROOT_LOGIN" ]; then
        print_message "  - PermitRootLogin: %s" "$SSH_ROOT_LOGIN"

    fi
else
    print_message "- SSH: NOT CONFIGURED"
fi

if [ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ]; then
    print_message "- Python venv created at: %s" "$VENV_PATH"

else
    print_message "- Python venv: NOT CREATED"
fi

if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    print_message "- System parameters optimized (sysctl.conf)"
else
    print_message "- sysctl: SKIPPED"
fi

if [ "$OS" = "debian" ] && { [ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ]; }; then
    print_message "- IPv6 disabled via GRUB (kernel level)"
    print_warning "  Note: Requires reboot to take effect"
fi

if [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; then
    if [ "$OS" = "debian" ]; then
        print_message "- Debian repositories configured"
        if [ "$ADD_TATARANOVICH_REPO" = "y" ] || [ "$ADD_TATARANOVICH_REPO" = "Y" ]; then
            print_message "- Tataranovich repository (Debian): ADDED (custom mc)"
        fi
    else
        print_message "- Ubuntu repositories configured (main, restricted, universe, multiverse)"
        if [ "$ADD_TATARANOVICH_UBUNTU" = "y" ] || [ "$ADD_TATARANOVICH_UBUNTU" = "Y" ]; then
            print_message "- Tataranovich repository (Ubuntu): ADDED (custom mc)"
        fi
        if [ "$ADD_UBUNTU_PPAS" = "y" ] || [ "$ADD_UBUNTU_PPAS" = "Y" ]; then
            print_message "- Ubuntu PPA repositories:"
            if [ "$ADD_PPA_NGINX" = "y" ] || [ "$ADD_PPA_NGINX" = "Y" ]; then
                print_message "  ✓ ppa:ondrej/nginx (Latest Nginx)"
            fi
            if [ "$ADD_PPA_GIT" = "y" ] || [ "$ADD_PPA_GIT" = "Y" ]; then
                print_message "  ✓ ppa:git-core/ppa (Latest Git)"
            fi
            if [ "$ADD_PPA_TOOLCHAIN" = "y" ] || [ "$ADD_PPA_TOOLCHAIN" = "Y" ]; then
                print_message "  ✓ ppa:ubuntu-toolchain-r/test (Latest GCC)"
            fi
        fi
    fi
fi

if [ "$COMMENT_IPV6_INTERFACES" = "y" ] || [ "$COMMENT_IPV6_INTERFACES" = "Y" ]; then
    if [ -f /etc/network/interfaces ]; then
        print_message "- IPv6 commented in /etc/network/interfaces"
        print_warning "  Note: May require network restart or reboot"
    fi
fi

if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_message "- UFW firewall configured and enabled"
    if [ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ]; then
        print_message "- ICMP (ping) blocking: ENABLED"
    else
        print_message "- ICMP (ping) blocking: DISABLED (server responds to ping)"
    fi
    if [ ! -z "$CUSTOM_PORTS" ]; then
        print_message "- Custom UFW ports: %s" "$CUSTOM_PORTS"

    fi
else
    print_message "- UFW: SKIPPED"
fi

if command -v docker &> /dev/null; then
    print_message "- Docker: Installed"
else
    print_message "- Docker: Not installed"
    if [ "$INSTALL_DOCKER" = "y" ] || [ "$INSTALL_DOCKER" = "Y" ]; then
        print_message "- Docker installation may have failed"
    fi
fi

if command -v ufw-docker &> /dev/null; then
    print_message "- ufw-docker: Installed and configured"
else
    if [ "$INSTALL_UFW_DOCKER" = "y" ] || [ "$INSTALL_UFW_DOCKER" = "Y" ]; then
        print_message "- ufw-docker: Installation attempted but not found"
    else
        print_message "- ufw-docker: Not installed"
    fi
fi

if command -v go &> /dev/null || [ -f /usr/local/go/bin/go ]; then
    if [ -f /usr/local/go/bin/go ]; then
        GO_VERSION=$(/usr/local/go/bin/go version 2>/dev/null || echo "unknown")
        print_message "- Go: Installed (%s)" "$GO_VERSION"

        if [ ! -z "$NEW_USERNAME" ]; then
            USER_HOME=$(getent passwd "$NEW_USERNAME" | cut -d: -f6)
            if [ -f "$USER_HOME/.zshrc" ]; then
                print_message "  Configured in: %s/.zshrc" "$USER_HOME"

            elif [ -f "$USER_HOME/.bashrc" ]; then
                print_message "  Configured in: %s/.bashrc" "$USER_HOME"

            fi
        fi
    fi
else
    if [ "$INSTALL_GO" = "y" ] || [ "$INSTALL_GO" = "Y" ]; then
        print_message "- Go: Installation attempted but not found"
    else
        print_message "- Go: Not installed"
    fi
fi

if command -v ipset &> /dev/null; then
    IPSET_VERSION=$(ipset --version 2>/dev/null || echo "unknown")
    print_message "- ipset: Installed (%s)" "$IPSET_VERSION"

else
    if [ "$INSTALL_IPSET" = "y" ] || [ "$INSTALL_IPSET" = "Y" ]; then
        print_message "- ipset: Installation attempted but not found"
    else
        print_message "- ipset: Not installed"
    fi
fi

if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    print_message "- Custom MOTD: Installed"
    print_warning "  Note: MOTD will be visible on next SSH login"
else
    print_message "- Custom MOTD: Not installed"
fi

if [ "$INSTALL_UFW_CUSTOM_RULES" = "y" ] || [ "$INSTALL_UFW_CUSTOM_RULES" = "Y" ]; then
    UFW_SCRIPT_PATH="/opt/ufw-docker-rules-v${UFW_RULES_VERSION}.sh"
    if [ -f "$UFW_SCRIPT_PATH" ]; then
        UFW_SOURCE_TEXT="$([ "$UFW_INSTALL_SOURCE" = "2" ] && echo "from repository" || echo "from archive")"
        print_message "- Custom UFW Docker rules: Installed and executed (v%s, %s)" "${UFW_RULES_VERSION}" "${UFW_SOURCE_TEXT}"

        print_message "  Script location: %s" "$UFW_SCRIPT_PATH"

        # Show custom SSH port if configured
        if [ -n "$UFW_SSH_PORT" ] && [ "$UFW_SSH_PORT" != "22" ]; then
            print_message "  Custom SSH port configured: %s" "$UFW_SSH_PORT"

        fi
        # Show archive extraction info
        if [ "$UFW_INSTALL_SOURCE" = "1" ] && { [ "$EXTRACT_OPT_ARCHIVE" = "y" ] || [ "$EXTRACT_OPT_ARCHIVE" = "Y" ]; }; then
            print_message "  Archive extracted to: /opt"
            if [ -d "/opt/scripts" ]; then
                SCRIPT_COUNT=$(find /opt/scripts -type f ! -name "*.ini" | wc -l)
                print_message "  Executable scripts in /opt/scripts: %s" "$SCRIPT_COUNT"

            fi
        fi
    else
        print_message "- Custom UFW Docker rules: Installation attempted but failed"
    fi
else
    print_message "- Custom UFW Docker rules: Not installed"
fi

if [ "$RUN_BBR_OPTIMIZER" = "y" ] || [ "$RUN_BBR_OPTIMIZER" = "Y" ]; then
    print_message "- BBR Network Optimizer: Executed"
    print_message "  Force IPv4 APT: $([ "$BBR_FORCE_IPV4" = "y" ] || [ "$BBR_FORCE_IPV4" = "Y" ] && t "YES" || t "NO")"
    print_message "  Full Update: $([ "$BBR_FULL_UPDATE" = "y" ] || [ "$BBR_FULL_UPDATE" = "Y" ] && t "YES" || t "NO")"
    print_message "  Fix /etc/hosts: $([ "$BBR_FIX_HOSTS" = "y" ] || [ "$BBR_FIX_HOSTS" = "Y" ] && t "YES" || t "NO")"
    print_message "  Fix DNS: $([ "$BBR_FIX_DNS" = "y" ] || [ "$BBR_FIX_DNS" = "Y" ] && t "YES" || t "NO")"
else
    print_message "- BBR Network Optimizer: Not executed"
fi

print_message ""

if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ] || [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ] || [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ] || [ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ] || [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ] || { [ "$OS" = "debian" ] && { [ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ]; }; }; then
    print_message "Backup files saved with timestamp (format: filename.backup.YYYYMMDD-HHMMSS~):"
    if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
        print_message "- /etc/sysctl.conf.backup.*~"
    fi
    if [ "$CONFIGURE_REPOS" = "y" ] || [ "$CONFIGURE_REPOS" = "Y" ]; then
        if [ "$OS" = "debian" ]; then
            print_message "- /etc/apt/sources.list.backup.*~"
        else
            print_message "- /etc/apt/sources.list.backup.*~"
            print_message "- /etc/apt/sources.list.d/ubuntu.sources.backup.*~"
        fi
    fi
    if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
        print_message "- /etc/ssh/sshd_config.backup.*~"
    fi
    if [ "$BLOCK_ICMP" = "y" ] || [ "$BLOCK_ICMP" = "Y" ]; then
        print_message "- /etc/ufw/before.rules.backup.*~"
    fi
    if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
        print_message "- /tmp/crontab.backup.*~"
    fi
    if [ "$OS" = "debian" ] && { [ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ]; }; then
        print_message "- /etc/default/grub.backup.*~"
    fi
    print_message ""
fi

print_warning "Recommended next steps:"
STEP_NUM=1

if [ ! -z "$NEW_USERNAME" ]; then
    print_warning "%s. Test SSH connection with new user: ssh %s@hostname" "$STEP_NUM" "$NEW_USERNAME"

    if [ "$INSTALL_ZSH" = "y" ] || [ "$INSTALL_ZSH" = "Y" ]; then
        print_warning "   Note: zsh is configured, log in to see Oh My Zsh"
    fi
    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$CONFIGURE_SSH" = "y" ] || [ "$CONFIGURE_SSH" = "Y" ]; then
    if [ "$SSH_PORT" != "22" ]; then
        print_warning "%s. IMPORTANT: SSH port changed to %s" "$STEP_NUM" "$SSH_PORT"

        print_warning "   Make sure to update your SSH client before logging out!"
        print_warning "   Test connection: ssh -p %s user@host" "$SSH_PORT"

        STEP_NUM=$((STEP_NUM + 1))
    fi
fi

if [ "$CONFIGURE_UFW" = "y" ] || [ "$CONFIGURE_UFW" = "Y" ]; then
    print_warning "%s. Review UFW status: sudo ufw status verbose" "$STEP_NUM"

    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$CONFIGURE_SYSCTL" = "y" ] || [ "$CONFIGURE_SYSCTL" = "Y" ]; then
    print_warning "%s. Check sysctl: sysctl net.ipv4.tcp_congestion_control" "$STEP_NUM"

    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$CREATE_VENV" = "y" ] || [ "$CREATE_VENV" = "Y" ]; then
    print_warning "%s. Activate Python venv: source %s/bin/activate" "$STEP_NUM" "$VENV_PATH"

    STEP_NUM=$((STEP_NUM + 1))
fi

if command -v docker &> /dev/null; then
    if [ ! -z "$NEW_USERNAME" ]; then
        print_warning "%s. User %s needs to log out and back in to use Docker without sudo" "$STEP_NUM" "$NEW_USERNAME"

        STEP_NUM=$((STEP_NUM + 1))
    fi
    if [ ! -z "$SUDO_USER" ] && [ "$SUDO_USER" != "$NEW_USERNAME" ]; then
        print_warning "%s. User %s needs to log out and back in to use Docker without sudo" "$STEP_NUM" "$SUDO_USER"

        STEP_NUM=$((STEP_NUM + 1))
    fi
fi

if [ "$CONFIGURE_CRONTAB" = "y" ] || [ "$CONFIGURE_CRONTAB" = "Y" ]; then
    print_warning "%s. Check crontab: sudo crontab -l" "$STEP_NUM"

    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$OS" = "debian" ] && { [ "$DISABLE_IPV6_GRUB" = "y" ] || [ "$DISABLE_IPV6_GRUB" = "Y" ]; }; then
    print_warning "%s. Check GRUB IPv6 disable after reboot: cat /proc/cmdline | grep ipv6" "$STEP_NUM"

    STEP_NUM=$((STEP_NUM + 1))
fi

if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    print_warning "%s. Test MOTD: Reconnect via SSH to see custom MOTD" "$STEP_NUM"

    STEP_NUM=$((STEP_NUM + 1))
fi

print_message ""
print_message "Useful commands:"
print_message "sudo ufw status verbose"
print_message "sudo ufw status numbered"
print_message "sudo nano /etc/sysctl.conf"
print_message "sudo nano /etc/apt/sources.list"
if [ "$OS" = "ubuntu" ]; then
    print_message "sudo nano /etc/apt/sources.list.d/ubuntu.sources"
fi
print_message "sudo nano /etc/ssh/sshd_config"
print_message "sudo crontab -l"
if [ "$OS" = "debian" ]; then
    print_message "sudo nano /etc/default/grub"
    print_message "cat /proc/cmdline"
fi
if [ "$INSTALL_MOTD" = "y" ] || [ "$INSTALL_MOTD" = "Y" ]; then
    print_message "run-parts /etc/update-motd.d/  # Test MOTD"
fi
if [ ! -z "$NEW_USERNAME" ]; then
    print_message "su - %s" "$NEW_USERNAME"

fi
print_warning "%s. Reboot system to apply all changes: sudo reboot" "$STEP_NUM"


exit 0
