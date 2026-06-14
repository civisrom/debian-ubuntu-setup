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
- 🌐 Nginx из upstream-репозиториев (nginx.org / deb.myguard.nl / nginx-modules.com) с гибким выбором модулей
- 🔐 Проверка целостности (SHA256)
- 🤖 Автоматическое обновление checksum через GitHub Actions

## 📥 Установка

### Вариант 1: Прямая загрузка и запуск (рекомендуется)
```bash
if ! command -v curl >/dev/null 2>&1; then apt-get update && apt-get install -y curl ca-certificates; fi && bash <(curl -4fsSL https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/install.sh)
```

Или с помощью wget:
```bash
bash <(wget -4 -qO- https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/install.sh)
```

> Если в минимальной системе нет ни `curl`, ни `wget`, используйте первый вариант: он сначала установит `curl`, затем запустит installer. Команда `bash <(curl ...)` не может запустить `install.sh`, если локальный `curl` отсутствует.

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

## 🌐 Nginx: репозитории и установка

Скрипт умеет подключать upstream-репозитории Nginx (для Debian и Ubuntu) и
опционально устанавливать Nginx с выбранным набором модулей. Все вопросы
задаются в интерактивном режиме после блока настройки репозиториев.

### Доступные репозитории

| # | Репозиторий | Что даёт | Пиннинг |
|---|-------------|----------|---------|
| 1 | **nginx.org** | Официальный пакет `nginx` (стандартные модули вкомпилированы) + отдельные динамические модули `nginx-module-*` | `99nginx`, priority **900** |
| 2 | **deb.myguard.nl** | Сборки в стиле дистрибутива: `nginx-full`, `nginx-extras`, `nginx-core` … + ~130 пакетов `libnginx-mod-*` | `99myguard`, priority **901** |
| 3 | **nginx-modules.com** (Blendbyte) | Только динамические модули `nginx-module-*` (brotli, modsecurity, headers-more, zstd, geoip2 …) под официальную сборку nginx.org | `99blendbyte`, priority **900** |

> ⚠️ Выбирайте **только один** источник самого пакета `nginx` (1 **или** 2).
> Вариант 3 добавляет только модули и предназначен для совместного использования
> с nginx.org. Если включены и 1, и 2 — пакет `nginx` возьмётся из deb.myguard.nl
> (выше pin-приоритет).

#### Защита от подмены версии

Все репозитории пинятся в безопасном диапазоне `500 < priority < 1000`:

- **> 500** — upstream-пакет всегда выигрывает у дистрибутивного (priority 500),
  поэтому `apt update && apt upgrade` **не переключит** Nginx обратно на сборку
  дистрибутива, независимо от номера версии в дистрибутиве.
- **< 1000** — запрещён принудительный downgrade: apt перейдёт только на **более
  новую** версию из того же репозитория (security-обновления), но не подменит
  пакет другим вариантом.

После подключения скрипт выводит `apt-cache policy nginx` — по строке
`Candidate` видно, из какого репозитория установится/обновится Nginx.

### Пресеты установки

Если выбрана установка Nginx, предлагаются пресеты (показываются только те, что
подходят под включённые репозитории):

| Пресет | Что ставит | Требует |
|--------|-----------|---------|
| **1** | `nginx` (только стандартные встроенные модули) | nginx.org |
| **2** | `nginx` + официальные динамические модули (njs, geoip, image-filter, xslt, perl, otel, acme) | nginx.org |
| **3** | `nginx` + **ВСЕ** модули Blendbyte (brotli, modsecurity, headers-more, zstd, geoip2 …) | nginx.org + nginx-modules.com |
| **4** | **ВСЁ**: `nginx` + официальные модули + все модули Blendbyte | nginx.org + nginx-modules.com |
| **5** | `nginx-full` | deb.myguard.nl |
| **6** | `nginx-extras` (максимальный набор) | deb.myguard.nl |
| **7** | **custom** — только перечисленные вами пакеты | любой включённый |

Дополнительно есть поле **Extra packages** — любые пакеты, дописываемые к любому
пресету. Ввод принимается через **пробел или запятую**, например:
`nginx-module-njs, nginx-module-brotli lua-resty`.

#### Пресет 7 (custom)

При выборе пресета `7` скрипт печатает **копируемый список доступных пакетов** по
каждому включённому репозиторию (nginx.org core/модули, модули Blendbyte,
метапакеты и `libnginx-mod-*` myguard). Скопируйте нужные имена в приглашение
`Packages to install:` — разделяя их **пробелами или запятыми**.

Полный список модулей myguard (после установки):

```bash
apt-cache search '^libnginx-mod-'
```

### Включение динамических модулей

Динамические модули устанавливаются как `.so`, но **не включаются автоматически**.
Добавьте в начало `/etc/nginx/nginx.conf` строки вида:

```nginx
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_headers_more_filter_module.so;
```

Файлы `.so` лежат в `/etc/nginx/modules/` или `/usr/lib/nginx/modules/`. После
правки проверьте и перезагрузите конфигурацию:

```bash
nginx -t && systemctl reload nginx
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
