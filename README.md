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
| **8** | **curated lean**: `nginx` + stream, stream-geoip2, http-upstream-fair, http-subs-filter, http-geoip2, http-echo, http-dav-ext, http-auth-pam (эквивалент дистрибутивного `nginx-full`, готов для x-ui-pro, без «зоопарка» из ~110 модулей) | deb.myguard.nl |
| **7** | **custom** — только перечисленные вами пакеты | любой включённый |

Дополнительно есть поле **Extra packages** — любые пакеты, дописываемые к любому
пресету. Ввод принимается через **пробел или запятую**, например:
`nginx-module-njs, nginx-module-brotli lua-resty`.

> ℹ️ **Пресеты 3 и 4 (nginx.org + модули Blendbyte).** Конфликта по именам пакетов
> нет (наборы не пересекаются), и при совпадающих версиях оба набора пинят один и
> тот же `nginx` (например `1.30.2-1~bookworm`) и спокойно сосуществуют. Привязка
> жёсткая: модули nginx.org требуют `nginx-r<версия>`, модули Blendbyte —
> `nginx (= <версия>)`. Единственный нюанс — **временной рассинхрон** сразу после
> выхода новой stable: nginx.org обновляется мгновенно, сторонний репозиторий может
> отставать (~24ч). В этом окне совместная установка временно неразрешима, а
> `apt upgrade` придержит `nginx` (kept back), пока Blendbyte не догонит. Скрипт
> делает пробный расчёт зависимостей (`apt-get install -s`) перед установкой и при
> рассинхроне выводит понятное объяснение, не ломая систему. Решение: повторить
> позже или ставить модули из одного репозитория.

#### Пресет 7 (custom)

При выборе пресета `7` скрипт печатает **копируемый список доступных пакетов** по
каждому включённому репозиторию (nginx.org core/модули, модули Blendbyte,
метапакеты и `libnginx-mod-*` myguard). Скопируйте нужные имена в приглашение
`Packages to install:` — разделяя их **пробелами или запятыми**.

Полный список модулей myguard (после установки):

```bash
apt-cache search '^libnginx-mod-'
```

### Миграция с nginx из репозиториев Debian/Ubuntu

Если nginx с модулями уже установлен из штатных репозиториев дистрибутива, скрипт
обнаружит его и предложит **безопасную миграцию** на выбранный репозиторий.

Различия раскладки пакетов:

- **nginx.org (пресеты 1–4)** — иная схема: пакет `nginx` имеет
  `Conflicts/Replaces: nginx-common, nginx-core`, нет каталогов
  `sites-enabled`/`modules-enabled`, модули подключаются вручную через
  `load_module`. Это **смена вендора пакетов**, поэтому дистрибутивный стек
  (`nginx-common`, `nginx-core`/`full`/`light`/`extras`, все `libnginx-mod-*`)
  удаляется.
- **deb.myguard.nl (пресеты 5–6)** — Debian-style раскладка (те же имена
  `nginx-full`/`nginx-extras`, `libnginx-mod-*`), поэтому обновляется почти
  **на месте** за счёт pin-приоритета.

Что делает скрипт при миграции (по шагам, безопасно):

1. **Бэкап** `/etc/nginx` → `/var/backups/nginx-migration-<дата>/etc-nginx.tar.gz`
   и список пакетов (`packages.txt`, `nginx-version.txt`) — **до любых изменений**.
2. **Останавливает** сервис nginx.
3. Для nginx.org — **удаляет** дистрибутивный стек (перечисляется через
   `dpkg-query`, удаляются только реально установленные пакеты) и переносит
   `modules-enabled/*.conf` в бэкап (они ссылаются на удалённые `.so`).
4. **Устанавливает** пакеты выбранного пресета, сохраняя ваши конфиги
   (`--force-confold`/`--force-confdef`; новые конфиги пакета — как `*.dpkg-dist`).
5. **Проверяет** `nginx -t` и запускает nginx **только если тест прошёл** — иначе
   сервис не стартует (чтобы не отдавать сломанный конфиг), и выводится путь к бэкапу.

> ⚠️ Без подтверждения миграции при уже установленном nginx скрипт **не трогает**
> его и пропускает установку. В неинтерактивном режиме миграция по умолчанию
> выключена. Ваши site-конфиги в `/etc/nginx` сохраняются; для nginx.org
> добавьте нужные `load_module` вручную (см. ниже).
>
> 💡 Откат: остановить nginx, распаковать
> `tar xzf /var/backups/nginx-migration-<дата>/etc-nginx.tar.gz -C /` и
> переустановить пакеты из `packages.txt`.

### Полное удаление nginx

Если nginx уже установлен, скрипт **первым делом** предлагает его полностью удалить
(пункт взаимоисключающий с установкой). При подтверждении выполняется:

1. **Бэкап** `/etc/nginx` → `/var/backups/nginx-removal-<дата>/etc-nginx.tar.gz`
   + список пакетов (`packages.txt`).
2. Остановка и отключение службы (`systemctl stop/disable`, `pkill`).
3. **Purge** всех пакетов `nginx*` и `libnginx-mod-*` (только реально установленных,
   определяются через `dpkg-query`).
4. `apt-get autoremove --purge` — удаление ненужных больше зависимостей.
5. Удаление остатков: бинарников (`/usr/sbin/nginx`, `/usr/bin/nginx`), каталогов
   (`/etc/nginx`, `/usr/share/nginx`, `/usr/lib/nginx`, `/var/log/nginx`,
   `/var/lib/nginx`), systemd-юнитов и symlink-ов.
6. Удаление добавленных скриптом репозиториев, пинов и ключей (nginx.org,
   deb.myguard.nl, Blendbyte).
7. `systemctl daemon-reload`, сброс хэша шелла и проверка, что бинаря не осталось.

> ⚠️ Операция деструктивная, по умолчанию выключена (в т.ч. в неинтерактивном
> режиме). Бэкап `/etc/nginx` делается **до** любых изменений. Откат:
> `sudo tar xzf /var/backups/nginx-removal-<дата>/etc-nginx.tar.gz -C /` и
> переустановка пакетов из `packages.txt`.

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
