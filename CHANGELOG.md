# CHANGELOG

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/)  
Версионирование: SemVer (привязка к `pubspec.yaml` при релизе)

## [Unreleased]
### Added
- Процесс: единые артефакты разработки (docs, worklog, hooks).
- Android: добавлен `BootReceiver` (автозапуск после перезагрузки) и ресурсы splash для Android 12+.
- Скрипт: `scripts/auto-commit.ps1` для автоматического создания коммитов с проверкой артефактов.
- Документация: `docs/COMMIT_PROCESS.md` с описанием процесса коммита и формата сообщений.
- Документация: `docs/DECISIONS/0002-redis-integration-plan.md` с планом интеграции Redis.
- Документация: `docs/HOW_TO_GIVE_TASKS.md` с инструкцией, как ставить задачи ИИ.
- Правила: `.cursor/rules/20-auto-commit.md` для автоматического коммита после изменений.

### Changed
- Профиль: строка версии приложения теперь берётся из платформы (реальные `version+buildNumber`), а не только из хардкода.

- Правила: `.cursor/rules/20-auto-commit.md` для автоматического коммита после изменений.
- Правила: `.cursor/rules/15-git-files.md` - обязательное добавление всех файлов в git.

### Fixed
- Правила: исправлена проблема с неотслеживаемыми файлами - теперь все файлы автоматически добавляются в git.

### Removed
