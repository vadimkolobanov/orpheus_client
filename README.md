# Orpheus Client (Flutter)

Клиентское приложение на Flutter для проекта Orpheus.

## Быстрый старт

### Требования
- Flutter SDK (см. `environment` в `pubspec.yaml`)
- Android SDK / Android Studio (для Android)

### Установка зависимостей
```powershell
flutter pub get
```

### Запуск
```powershell
flutter run
```

## Тесты и отчёты

См. `docs/testing/README.md`.

Основные команды:
```powershell
flutter test
```

Или с генерацией отчётов:
```powershell
.\test_runner.ps1
```

## Документация
- Основная: `docs/README.md`
- Архитектура: `docs/ARCHITECTURE.md`
- Решения (ADR): `docs/DECISIONS/`

## Процесс изменений (чтобы ничего не забыть)
- Обновить `CHANGELOG.md` (секция `Unreleased`)
- Добавить запись в `AI_WORKLOG.md`
- Обновить `docs/*` при необходимости

### Cursor
- Правила: `.cursor/rules/`
- Команды-шаблоны: `.cursor/commands/` (например: `update-artifacts`, `update-changelog`, `log-work`, `commit-ready`)

### Git hooks (рекомендуется)
Чтобы коммит нельзя было сделать без `CHANGELOG.md` и `AI_WORKLOG.md`:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks.ps1
```
