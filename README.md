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

См.:
- `QUICK_START_TESTS.md`
- `TEST_REPORTS_GUIDE.md`

Основные команды:

```powershell
flutter test
```

Или с генерацией отчётов:

```powershell
.\test_runner.ps1
```

## Документация

Основная документация клиента: `docs/README.md`  
Архитектурный обзор: `docs/ARCHITECTURE.md`  
Решения (ADR): `docs/DECISIONS/`

## Процесс изменений (чтобы ИИ не забывал)

При изменениях кода/поведения **всегда**:
- обновить `CHANGELOG.md` (секция `Unreleased`)
- добавить запись в `AI_WORKLOG.md`
- обновить `docs/*` при необходимости

### Cursor
Правила проекта: `.cursor/rules/`  
Команды-шаблоны: `.cursor/commands/` (например: `update-artifacts`, `update-changelog`, `log-work`, `commit-ready`)

### Git hooks (рекомендуется)
Чтобы коммит нельзя было сделать без `CHANGELOG.md` и `AI_WORKLOG.md`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks.ps1
```

