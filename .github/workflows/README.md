# GitHub Actions workflows

В репозитории используются две обязательные проверки. Они ничего не коммитят и
не требуют write-доступа к репозиторию.

## Verify system-setup.sh checksum

Файл: `verify-checksum.yml`.

Запускается для Pull Request, push в `main` и вручную. Команда
`sha256sum -c system-setup.sh.sha256` гарантирует, что главный скрипт и checksum
попали в один commit. Несовпадение завершает workflow с ошибкой.

После каждого изменения главного скрипта выполните:

```bash
./update-checksum.sh
git add system-setup.sh system-setup.sh.sha256
```

## Quality checks

Файл: `quality.yml`.

Проверяет:

- синтаксис всех shell-скриптов через `bash -n`;
- ShellCheck;
- итоговую Docker Compose конфигурацию RustDesk;
- синтаксис systemd units;
- checksum главного скрипта;
- локальные regression-тесты из `tests/regression.sh`.

Workflow запускается для Pull Request, push в `main` и вручную. Если проверка
падает, откройте соответствующий step: его команда пригодна для локального
повторения.

## Почему нет автоматического обновления checksum

Бот-коммит после push создавал окно, в котором ветка содержала новый скрипт и
старый checksum. Кроме того, первоначальный commit выглядел успешным до
появления исправляющего commit. Теперь несогласованное изменение отклоняется CI,
а оба файла проходят ревью и попадают в историю атомарно.
