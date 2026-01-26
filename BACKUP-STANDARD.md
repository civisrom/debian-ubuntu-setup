# Стандарт именования файлов бэкапа

## ✅ Правило

Все файлы бэкапов в `system-setup.sh` **ОБЯЗАТЕЛЬНО** заканчиваются на тильду `~`

## 📋 Формат

### Бэкапы с timestamp
```bash
filename.backup.YYYYMMDD-HHMMSS~
```

**Примеры:**
- `/etc/sysctl.conf.backup.20260126-143949~`
- `/etc/ssh/sshd_config.backup.20260126-143949~`
- `/etc/apt/sources.list.backup.20260126-143949~`
- `/etc/default/grub.backup.20260126-143949~`
- `/etc/network/interfaces.backup.20260126-143949~`
- `/etc/ufw/before.rules.backup.20260126-143949~`
- `/etc/motd.backup.20260126-143949~`
- `/tmp/crontab.backup.20260126-143949~`

### Бэкапы специального назначения
```bash
filename.backup.purpose~
```

**Примеры:**
- `/etc/ssh/sshd_config.backup.motd~` (для MOTD конфигурации)
- `/etc/pam.d/sshd.backup.motd~` (для PAM MOTD модуля)

## 🔍 Почему тильда `~`?

### 1. Стандарт Unix/Linux
- Тильда `~` - стандартный суффикс для backup файлов
- Используется редакторами (vim, emacs, nano)
- Признан инструментами (find, ls, rsync)

### 2. Удобство поиска
```bash
# Найти все бэкапы
ls -la *.backup.*~

# Найти бэкапы в директории
find /etc -name "*.backup.*~"

# Исключить бэкапы из grep
grep pattern file.conf  # без ~
```

### 3. Автоматическое игнорирование
Многие инструменты автоматически игнорируют файлы с `~`:
- rsync по умолчанию пропускает
- tar может исключать
- git обычно игнорирует

### 4. Визуальное отличие
```bash
# Легко отличить оригинал от бэкапа
sshd_config                    # оригинал
sshd_config.backup.motd~       # бэкап
```

## 📝 Как создавать бэкапы

### Timestamped backup (рекомендуется)
```bash
# Для файлов конфигурации
if [ -f /etc/sysctl.conf ]; then
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d-%H%M%S)~
fi
```

### Named backup (для специальных случаев)
```bash
# Для одноразовых бэкапов с определенной целью
if [ ! -f /etc/ssh/sshd_config.backup.motd~ ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.motd~
fi
```

## 🚫 Неправильно

```bash
# БЕЗ тильды - НЕПРАВИЛЬНО!
cp file.conf file.conf.backup.20260126-143949
cp file.conf file.conf.bak
cp file.conf file.conf.old
cp file.conf file.conf.backup.motd
```

## ✅ Правильно

```bash
# С тильдой - ПРАВИЛЬНО!
cp file.conf file.conf.backup.20260126-143949~
cp file.conf file.conf.bak~
cp file.conf file.conf.old~
cp file.conf file.conf.backup.motd~
```

## 🔧 Восстановление из бэкапа

### Найти последний бэкап
```bash
LATEST_BACKUP=$(ls -t /etc/ssh/sshd_config.backup.*~ 2>/dev/null | head -1)
```

### Восстановить
```bash
if [ ! -z "$LATEST_BACKUP" ]; then
    cp "$LATEST_BACKUP" /etc/ssh/sshd_config
    echo "Restored from: $LATEST_BACKUP"
fi
```

### Удалить старые бэкапы
```bash
# Оставить только последние 5
ls -t /etc/ssh/sshd_config.backup.*~ | tail -n +6 | xargs rm -f

# Удалить старше 30 дней
find /etc -name "*.backup.*~" -mtime +30 -delete
```

## 📊 Все бэкапы в system-setup.sh

| Файл | Формат | Пример |
|------|--------|--------|
| `/etc/apt/sources.list` | `sources.list.backup.YYYYMMDD-HHMMSS~` | ✅ |
| `/etc/apt/sources.list.d/ubuntu.sources` | `ubuntu.sources.backup.YYYYMMDD-HHMMSS~` | ✅ |
| `/etc/apt/sources.list.d/tataranovich*.list` | `tataranovich*.list.backup.YYYYMMDD-HHMMSS~` | ✅ |
| `/etc/sysctl.conf` | `sysctl.conf.backup.YYYYMMDD-HHMMSS~` | ✅ |
| `/etc/default/grub` | `grub.backup.YYYYMMDD-HHMMSS~` | ✅ |
| `/etc/network/interfaces` | `interfaces.backup.YYYYMMDD-HHMMSS~` | ✅ |
| `/etc/ssh/sshd_config` | `sshd_config.backup.YYYYMMDD-HHMMSS~` | ✅ |
| `/etc/ssh/sshd_config` (MOTD) | `sshd_config.backup.motd~` | ✅ |
| `/etc/pam.d/sshd` (MOTD) | `sshd.backup.motd~` | ✅ |
| `/etc/ufw/before.rules` | `before.rules.backup.YYYYMMDD-HHMMSS~` | ✅ |
| `/etc/motd` | `motd.backup.YYYYMMDD-HHMMSS~` | ✅ |
| `crontab` | `/tmp/crontab.backup.YYYYMMDD-HHMMSS~` | ✅ |

## 🎯 Итого

- ✅ **Все бэкапы** заканчиваются на `~`
- ✅ **Единый стандарт** во всем скрипте
- ✅ **Соответствует** Unix/Linux конвенциям
- ✅ **Удобно** для поиска и управления
- ✅ **Автоматически** игнорируется большинством инструментов

## 📅 История изменений

**26.01.2026** - Исправлено:
- `sshd_config.backup.motd` → `sshd_config.backup.motd~`
- `pam.d/sshd.backup.motd` → `pam.d/sshd.backup.motd~`

Теперь **100%** файлов бэкапов следуют стандарту!
