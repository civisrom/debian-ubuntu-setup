# Быстрый старт для изменений

## Локальная работа

```bash
git clone https://github.com/civisrom/debian-ubuntu-setup.git
cd debian-ubuntu-setup

# Внесите изменения, затем обновите checksum главного скрипта.
./update-checksum.sh

# Минимальные локальные проверки.
bash -n system-setup.sh install.sh install-nft-docker-watch.sh config/*.sh tests/*.sh
sha256sum -c system-setup.sh.sha256
bash tests/regression.sh

git add system-setup.sh system-setup.sh.sha256
git commit -m "Describe the change"
git push
```

Если менялись другие файлы, добавьте их в commit вместе со скриптом и checksum.
Workflow `Quality checks` дополнительно запускает ShellCheck, проверку Compose и
systemd units.

## Редактирование через GitHub

Редактировать файл в браузере можно, но checksum больше не обновляется отдельным
бот-коммитом. Поэтому для изменения `system-setup.sh` рекомендуется создать
branch/PR, открыть его через `github.dev`, обновить оба файла и дождаться CI:

1. Измените `system-setup.sh`.
2. В терминале web-редактора выполните `./update-checksum.sh`.
3. Закоммитьте `system-setup.sh` и `system-setup.sh.sha256` вместе.
4. Убедитесь, что проверки `Verify system-setup.sh checksum` и `Quality checks`
   завершились успешно.

Если checksum забыта, CI завершится с ошибкой. Исправление:

```bash
./update-checksum.sh
git add system-setup.sh system-setup.sh.sha256
git commit -m "Update system setup checksum"
git push
```

## Запуск установки

```bash
sudo bash -c 'if ! command -v curl >/dev/null 2>&1; then apt-get update && apt-get install -y curl ca-certificates; fi; bash <(curl -4fsSL https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/main/install.sh)'
```

`install.sh` один раз разрешает `main` в commit SHA, затем скачивает главный
скрипт и его checksum именно из этого commit. Это исключает рассинхронизацию
двух загрузок при одновременном обновлении ветки. Перед запуском на важном
сервере всё равно просмотрите `install.sh`: checksum из того же репозитория
проверяет согласованность, а не независимую подлинность источника.

## Диагностика

- Ошибка checksum: выполните `./update-checksum.sh` и закоммитьте оба файла.
- Красный `Quality checks`: откройте конкретный job и повторите указанную команду
  локально.
- Документация checksum: [CHECKSUM-README.md](CHECKSUM-README.md).
- Описание CI: [.github/workflows/README.md](.github/workflows/README.md).
