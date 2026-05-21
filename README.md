# Debian/Ubuntu System Setup

Автоматизированный скрипт для настройки и hardening серверов Debian/Ubuntu.

## Поддерживаемые системы

- Debian 12, 13
- Ubuntu 24.04 LTS, 25.10, 26.04 LTS

## ✨ Особенности

- ✅ Автоматическая установка и настройка пакетов
- 🔒 Hardening системы и SSH
- 🐳 Docker и Docker Compose
- 🖥️ RustDesk сервер (опционально)
- 🔥 Настройка UFW firewall
- 🔐 Проверка целостности (SHA256)
- 🤖 Автоматическое обновление checksum через GitHub Actions

## 📥 Установка

### Вариант 1: Прямая загрузка и запуск (рекомендуется)
```bash
bash <(wget -qO- https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/install.sh)
```

Или с помощью curl:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/install.sh)
```

**Что делает install.sh:**
- Скачивает `system-setup.sh`
- Проверяет SHA256 checksum для безопасности
- Запускает скрипт
- Удаляет временные файлы

### Вариант 2: Загрузка и локальный запуск
```bash
# Загрузить скрипт
wget https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/system-setup.sh

# Сделать исполняемым
chmod +x system-setup.sh

# Запустить
sudo ./system-setup.sh
```

## 👨‍💻 Для разработчиков

### 🚀 Редактирование через браузер GitHub

**Теперь вы можете редактировать `system-setup.sh` прямо в браузере!**

1. Откройте файл на GitHub
2. Нажмите кнопку "Edit" (карандаш)
3. Внесите изменения
4. Закоммитьте

✨ **Checksum обновится автоматически через GitHub Actions!**

Никаких ручных действий не требуется.

**📖 Подробная инструкция:** [QUICKSTART.md](QUICKSTART.md)

### Редактирование локально

После редактирования `system-setup.sh`:

```bash
# Автоматическое обновление checksum
./update-checksum.sh

# Или вручную
sha256sum system-setup.sh > system-setup.sh.sha256

# Коммит обоих файлов
git add system-setup.sh system-setup.sh.sha256
git commit -m "Update system-setup.sh and checksum"
git push
```

**Или просто пушьте без checksum** - GitHub Actions обновит его автоматически!

### GitHub Actions

Репозиторий использует автоматизацию:

- 🤖 **Auto-update checksum** - автоматически обновляет `.sha256` при изменении скрипта
- ✅ **Verify checksum** - проверяет целостность в Pull Requests

Подробности: [.github/workflows/README.md](.github/workflows/README.md)

## 📚 Документация

- **[QUICKSTART.md](QUICKSTART.md)** - 🚀 Быстрый старт: редактирование через браузер
- [CHECKSUM-README.md](CHECKSUM-README.md) - Руководство по checksum
- [.github/workflows/README.md](.github/workflows/README.md) - Документация GitHub Actions
- [update-checksum.sh](update-checksum.sh) - Утилита обновления checksum

## 🔐 Безопасность

- Все загрузки проверяются SHA256 checksum
- Checksum обновляется автоматически при изменениях
- SSH hardening и firewall настройки
- Пароли передаются безопасно (heredoc, временные файлы)
