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

## Android splash / иконки (важно для одинакового результата на разных ПК)

- Android < 12: используется `android/app/src/main/res/drawable*/launch_background.xml`, который показывает `@drawable/splash`.
- Android 12+ (API 31+): используется `android/app/src/main/res/values*-v31/styles.xml` и иконка `@drawable/android12splash`.

Чтобы на другом компьютере было так же, **эти файлы должны быть в git**. Если после обновления всё равно видите старый splash:

```powershell
flutter clean
flutter pub get
```


