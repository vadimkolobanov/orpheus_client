# Документация клиента (Flutter)

## Быстрый старт

### Предусловия
- Flutter SDK (см. `environment` в `pubspec.yaml`)
- Android SDK / Android Studio (если запускаете на Android)

### Установка зависимостей

```powershell
flutter pub get
```

### Запуск

```powershell
flutter run
```

## Тесты и отчёты

См. `QUICK_START_TESTS.md` и `TEST_REPORTS_GUIDE.md`.

- Запуск тестов + отчёт:

```powershell
.\test_runner.ps1
```

- Быстрый прогон (без файлов):

```powershell
.\quick_test.ps1
```

## Процесс изменений (обязательно)

При любых изменениях кода/поведения:
- обновить `CHANGELOG.md` → `## [Unreleased]`
- добавить запись в `AI_WORKLOG.md`
- при необходимости обновить документацию в `docs/`

Чтобы это не забывалось, включите git hooks (см. `scripts/install-hooks.ps1`).

## Версия приложения

В профиле/настройках версия отображается как `version+buildNumber` (из платформы через `package_info_plus`).


