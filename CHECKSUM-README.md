# Checksum Update Guide

## Проблема

При запуске `install.sh` возникает ошибка:
```
[ERROR] Integrity check failed!
[ERROR] Expected: e1c854bd2b615dfb73a2f84b92d9d9e5fabeef3ff29427a1e1074733fa48997f
[ERROR] Got:      e7816cecc9bb275172f3836779c19eb160d6cfe6bb63d3f8c3ed359fdc4f69de
```

## Причина

Файл `system-setup.sh` был изменен, но checksum файл не обновлен.

CI не исправляет checksum автоматически: скрипт и checksum должны попасть в
один проверяемый commit.

## Решение

**После ЛЮБОГО редактирования `system-setup.sh` выполните:**

```bash
# Автоматическое обновление checksum
./update-checksum.sh

# Или вручную:
sha256sum system-setup.sh > system-setup.sh.sha256
```

## Рабочий процесс

1. Редактируйте `system-setup.sh`:
   ```bash
   nano system-setup.sh
   # или
   vim system-setup.sh
   ```

2. Обновите checksum:
   ```bash
   ./update-checksum.sh
   ```

3. Закоммитьте оба файла:
   ```bash
   git add system-setup.sh system-setup.sh.sha256
   git commit -m "Update system-setup.sh and checksum"
   git push
   ```

## О RustDesk ключе `-k _`

`-k _` **включает** проверку ключа и усиливает защиту:

- `hbbs` при первом запуске создаёт пару ключей `id_ed25519` и
  `id_ed25519.pub` в `/opt/rustdesk/data/`, `hbbr` читает ту же пару.
- `_` означает «использовать публичный ключ из этой пары». Клиенты без этого
  ключа в поле «Key» получают отказ и на `hbbs`, и на `hbbr` (ретранслятор).
- `hbbs` подписывает приватным ключом ключи клиентов, а клиент сверяет подпись
  с введённым публичным ключом.

Не заменяйте `-k _` на `-k <пароль>`. Строка вместо ключа остаётся проверкой
доступа, но `hbbs` теряет приватный ключ и перестаёт подписывать ключи
клиентов. Сменить ключ, например если публичный ключ попал к посторонним:
`rustdesk-ctl key rotate` (см. README, раздел «RustDesk сервер»).

## Заключение

- Всегда обновляйте checksum после редактирования `system-setup.sh`
- Используйте `./update-checksum.sh` для автоматизации
- `install.sh` скачивает скрипт и checksum из одного commit SHA, поэтому между
  двумя запросами ветка `main` не может незаметно измениться
- Checksum подтверждает согласованность файлов, но не является независимой
  криптографической подписью репозитория
- `-k _` в RustDesk не убирать: он закрывает сервер для клиентов без его ключа
