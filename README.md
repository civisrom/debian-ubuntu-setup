# System Setup Script для Debian и Ubuntu

Скрипт для первоначальной настройки системы с установкой необходимых пакетов, оптимизацией параметров ядра и настройкой файрвола.

## Возможности

- ✅ Автоматическое определение ОС (Debian/Ubuntu)
- ✅ Установка необходимых пакетов
- ✅ Настройка репозиториев (для Debian)
- ✅ Оптимизация параметров ядра (sysctl.conf)
- ✅ Настройка UFW файрвола
- ✅ Установка ufw-docker
- ✅ Резервное копирование конфигурационных файлов

## Установка и запуск

### Вариант 1: Прямая загрузка и запуск

```bash
bash <(wget -qO- https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/install.sh)
```

### Вариант 2: Загрузка и локальный запуск

```bash
# Загрузить скрипт
wget https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/refs/heads/main/system-setup.sh

# Сделать исполняемым
chmod +x system-setup.sh

# Запустить
sudo ./system-setup.sh
```

### Вариант 3: С использованием curl

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/install.sh)
```

## Что делает скрипт

### 1. Установка пакетов

**Общие пакеты для всех систем:**
- Системные утилиты: htop, mc, nano, curl, wget, git
- Сетевые утилиты: net-tools, traceroute, iptables, ufw
- Безопасность: auditd, rsyslog, ca-certificates
- Разработка: build-essential, pkg-config, autoconf, automake
- И другие необходимые пакеты

**Специфичные для Debian:**
- openvswitch-switch-dpdk

**Специфичные для Ubuntu:**
- landscape-common
- update-notifier-common
- ubuntu-keyring

### 2. Настройка репозиториев (только Debian)

Для Debian Bookworm настраиваются официальные репозитории:
- Основные репозитории (main, contrib, non-free)
- Обновления безопасности
- Обновления стабильного релиза
- Backports

### 3. Оптимизация системных параметров

Настройка `/etc/sysctl.conf`:
- Отключение IPv6
- Оптимизация TCP/UDP буферов
- Настройка BBR congestion control
- Оптимизация сетевых параметров
- Увеличение лимитов файловой системы

### 4. Настройка файрвола UFW

- Разрешение SSH (порт 22)
- Возможность добавить дополнительный порт
- Установка и настройка ufw-docker

## Безопасность

Скрипт автоматически создает резервные копии всех изменяемых файлов:
- `/etc/sysctl.conf.backup.YYYYMMDD-HHMMSS`
- `/etc/apt/sources.list.backup.YYYYMMDD-HHMMSS` (для Debian)

## Требования

- Debian 12 (Bookworm) или Ubuntu (любая поддерживаемая версия)
- Root права или sudo доступ
- Интернет соединение

## Интерактивные элементы

Скрипт запросит:
1. Дополнительный порт для открытия в UFW (опционально)

## После выполнения

После успешного выполнения скрипта рекомендуется:
1. Проверить статус UFW: `sudo ufw status verbose`
2. Проверить применение sysctl: `sysctl net.ipv4.tcp_congestion_control`
3. Перезагрузить систему для применения всех изменений: `sudo reboot`

## Устранение неполадок

### Скрипт не запускается
```bash
# Проверьте права
ls -l system-setup.sh

# Должно быть: -rwxr-xr-x
chmod +x system-setup.sh
```

### Ошибки при установке пакетов
```bash
# Обновите списки пакетов
sudo apt update

# Попробуйте установить проблемный пакет вручную
sudo apt install package-name
```

### UFW блокирует соединения
```bash
# Проверьте правила
sudo ufw status numbered

# Добавьте нужный порт
sudo ufw allow PORT/tcp
```

## Отмена изменений

### Восстановление sysctl.conf
```bash
sudo cp /etc/sysctl.conf.backup.YYYYMMDD-HHMMSS /etc/sysctl.conf
sudo sysctl -p
```

### Восстановление sources.list (Debian)
```bash
sudo cp /etc/apt/sources.list.backup.YYYYMMDD-HHMMSS /etc/apt/sources.list
sudo apt update
```

### Отключение UFW
```bash
sudo ufw disable
```

## Лицензия

MIT License
