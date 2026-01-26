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

**Вы были правы!** Ключ `-k _` это НЕ ключ шифрования:

- ✅ RustDesk автоматически генерирует ключи шифрования (id_ed25519) в папке `data/`
- ✅ `-k _` означает "без пароля доступа" (публичный режим)
- ✅ Это **безопасно** для приватных серверов в доверенной сети
- ⚠️ Для публичных серверов используйте `-k <пароль>` чтобы ограничить доступ

### Когда менять `-k _`:

- ❌ **НЕ нужно** для приватных серверов (за firewall/VPN)
- ✅ **Нужно** для публичных серверов в интернете
- ✅ **Нужно** если хотите ограничить доступ определенным клиентам

### Как изменить ключ доступа (для публичных серверов):

```bash
# Сгенерировать пароль
PASSWORD=$(openssl rand -hex 16)
echo "Ваш пароль: $PASSWORD"

# Отредактировать docker-compose.yml
sed -i "s/command: hbbs -k _/command: hbbs -k $PASSWORD/" docker-compose.yml
sed -i "s/command: hbbr -k _/command: hbbr -k $PASSWORD/" docker-compose.yml

# Перезапустить сервисы
docker compose restart
```

Клиентам потребуется этот пароль для подключения к вашему серверу.

## Заключение

- Всегда обновляйте checksum после редактирования `system-setup.sh`
- Используйте `./update-checksum.sh` для автоматизации
- `-k _` безопасен для приватных установок RustDesk
