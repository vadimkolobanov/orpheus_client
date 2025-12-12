# AI_WORKLOG

Журнал действий ИИ/агента в этом репозитории.

Правило: если меняется код/конфиги/поведение — добавляй запись сюда **и** обновляй `CHANGELOG.md` (секция `Unreleased`).

---

## 2025-12-12
- Time: 00:00 local
- Task: Инициализация процесса разработки (Cursor rules/commands, docs, hooks)
- Changes:
  - Добавлены шаблоны документации и журналов.
  - Добавлены правила/команды Cursor для дисциплины артефактов.
  - Добавлен git hook, который не даст забыть обновить `CHANGELOG.md`/`AI_WORKLOG.md`.
- Files:
  - `CHANGELOG.md`
  - `AI_WORKLOG.md`
  - `docs/README.md`
  - `docs/ARCHITECTURE.md`
  - `docs/DECISIONS/0001-ai-process.md`
  - `.cursor/rules/*`
  - `.cursor/commands/*`
  - `.githooks/pre-commit`
  - `scripts/install-hooks.ps1`
  - `.gitignore`
- Commands:
  - `powershell -ExecutionPolicy Bypass -File .\\scripts\\install-hooks.ps1`
  - `flutter pub get`
  - `flutter test` / `.\test_runner.ps1`

## 2025-12-12
- Time: 15:44 local
- Task: Профиль — показывать реальную версию приложения
- Changes:
  - В экране профиля версия теперь берётся из `package_info_plus` (реальные `version+buildNumber`) с fallback на `AppConfig.appVersion`.
  - Обновлён тест версии `AppConfig` (SemVer/`v`-префикс).
- Files:
  - `lib/screens/settings_screen.dart`
  - `CHANGELOG.md`
  - `test/config_test.dart`

## 2025-12-12
- Time: 15:44 local
- Task: Android — splash + BootReceiver
- Changes:
  - Android < 12: `launch_background.xml` переключён на `@drawable/splash`.
  - Android 12+: добавлены ресурсы `android12splash` и стили `values-v31`.
  - Добавлен `BootReceiver` и регистрация в `AndroidManifest.xml` (+ `RECEIVE_BOOT_COMPLETED`).
- Files:
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/src/main/kotlin/com/example/orpheus_project/BootReceiver.kt`
  - `android/app/src/main/res/drawable*/launch_background.xml`
  - `android/app/src/main/res/drawable-*/splash.png`
  - `android/app/src/main/res/drawable-*/android12splash.png`
  - `android/app/src/main/res/values-v31/styles.xml`
  - `android/app/src/main/res/values-night-v31/styles.xml`
  - `docs/README.md`
  - `CHANGELOG.md`


