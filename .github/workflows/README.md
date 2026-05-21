# GitHub Actions Workflows

Этот репозиторий использует GitHub Actions для автоматизации задач.

## 🤖 Workflows

### 1. Auto-update checksum (`update-checksum.yml`)

**Цель:** Автоматически обновляет `system-setup.sh.sha256` при изменении `system-setup.sh`

**Когда срабатывает:**
- При коммите, изменяющем `system-setup.sh`
- На ветках: `main` или `claude/**`

**Что делает:**
1. Проверяет, нужно ли обновить checksum
2. Пересчитывает SHA256 checksum
3. Коммитит обновленный файл `.sha256`
4. Пушит изменения обратно в репозиторий

**Особенности:**
- Пропускает коммиты с `[skip-checksum]` в сообщении
- Не создает бесконечный цикл (помечает свои коммиты)
- Показывает подробный summary с старым и новым checksum

**Результат:** Вы можете редактировать `system-setup.sh` через браузер GitHub, и checksum обновится автоматически!

---

### 2. Verify checksum (`verify-checksum.yml`)

**Цель:** Проверяет целостность checksum в Pull Requests

**Когда срабатывает:**
- На Pull Requests, изменяющих `system-setup.sh` или `.sha256`

**Что делает:**
1. Проверяет совпадение checksum
2. Показывает результат проверки
3. Блокирует PR если checksum не совпадает

**Результат:** Защита от случайного забывания обновления checksum в PR.

**Почему не на `push: main`?** Auto-update workflow сам коммитит исправленный
checksum при push в `main` / `claude/**`. Если бы verify тоже запускался на
push, он бы успевал упасть до того, как auto-update успеет починить файл —
это и было причиной красных галок в Actions.

---

## 📝 Примеры использования

### Редактирование через браузер GitHub

1. Откройте `system-setup.sh` на GitHub
2. Нажмите кнопку "Edit" (карандаш)
3. Внесите изменения
4. Нажмите "Commit changes"
5. ✅ **Checksum обновится автоматически через ~30 секунд**

Проверить статус можно в разделе "Actions" на GitHub.

### Редактирование локально

#### Вариант А: Автоматически (рекомендуется)
```bash
# 1. Редактируйте файл
vim system-setup.sh

# 2. Закоммитьте БЕЗ checksum
git add system-setup.sh
git commit -m "Update system-setup.sh"
git push

# 3. GitHub Actions обновит checksum автоматически
# Затем просто сделайте git pull
git pull
```

#### Вариант Б: Вручную (старый способ)
```bash
# 1. Редактируйте файл
vim system-setup.sh

# 2. Обновите checksum вручную
./update-checksum.sh

# 3. Закоммитьте ОБА файла
git add system-setup.sh system-setup.sh.sha256
git commit -m "Update system-setup.sh and checksum"
git push
```

---

## 🔧 Настройка

### Требования

Workflows используют стандартный `GITHUB_TOKEN` - дополнительная настройка не требуется.

### Отключение автообновления

Если нужно временно отключить автообновление, добавьте `[skip-checksum]` в сообщение коммита:

```bash
git commit -m "Update system-setup.sh [skip-checksum]"
```

---

## 🐛 Устранение проблем

### Workflow не запустился

Проверьте:
1. Изменили ли вы именно файл `system-setup.sh`?
2. Находитесь ли на ветке `main` или `claude/**`?
3. Нет ли `[skip-checksum]` в сообщении коммита?

### Checksum не обновился

1. Перейдите в раздел "Actions" на GitHub
2. Найдите последний запуск "Auto-update system-setup.sh checksum"
3. Проверьте логи на наличие ошибок
4. Если нужно, запустите workflow вручную

### Permissions ошибка

Убедитесь, что в настройках репозитория включено:
- Settings → Actions → General → Workflow permissions
- Выберите: "Read and write permissions"

---

## 📊 Мониторинг

Все workflows показывают подробные summaries:
- ✅ Успешное обновление с показом старого/нового checksum
- ❌ Ошибки с рекомендациями по исправлению
- ⚠️ Предупреждения если что-то пропущено

Проверить статус: `https://github.com/civisrom/debian-ubuntu-setup/actions`

---

## 🎯 Преимущества

✅ Редактируйте через браузер - не нужен локальный git
✅ Автоматическое обновление checksum
✅ Нет риска забыть обновить checksum
✅ `install.sh` всегда работает корректно
✅ Проверка в Pull Requests
