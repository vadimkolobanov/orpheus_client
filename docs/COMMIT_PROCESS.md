# Процесс коммита с правилами

## Автоматический коммит

Для автоматического создания коммита с правильным форматом используйте скрипт:

```powershell
.\scripts\auto-commit.ps1
```

Скрипт автоматически:
1. Проверяет, что обновлены `CHANGELOG.md` и `AI_WORKLOG.md`
2. Анализирует изменения и предлагает тип коммита (feat/fix/docs/chore)
3. Создает коммит с сообщением в формате Conventional Commits
4. Показывает итоговый статус

## Формат коммитов (Conventional Commits)

Все коммиты должны следовать формату:
```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

### Типы:
- `feat(client):` - новая функциональность
- `fix(client):` - исправление бага
- `docs(client):` - изменения в документации
- `chore(client):` - технические изменения (зависимости, конфиги)
- `refactor(client):` - рефакторинг без изменения функциональности
- `test(client):` - добавление/изменение тестов

### Примеры:
```
feat(client): добавлен BootReceiver для автозапуска
fix(client): исправлена кодировка в CHANGELOG.md
docs(client): добавлен план интеграции Redis
chore(client): обновлены зависимости Flutter
```

## Ручной процесс

Если нужно сделать коммит вручную:

1. **Проверка артефактов:**
   ```powershell
   # Используйте Cursor команду: update-artifacts
   # Или проверьте вручную:
   git status
   ```

2. **Подготовка коммита:**
   ```powershell
   # Используйте Cursor команду: commit-ready
   # Она покажет предложенное сообщение коммита
   ```

3. **Создание коммита:**
   ```powershell
   git add .
   git commit -m "feat(client): описание изменений"
   ```

## Требования перед коммитом

Git hook (`.githooks/pre-commit`) автоматически проверяет:
- ✅ `CHANGELOG.md` обновлен (секция `[Unreleased]`)
- ✅ `AI_WORKLOG.md` содержит новую запись

Если что-то не обновлено, коммит будет заблокирован.

## Установка hooks

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks.ps1
```

