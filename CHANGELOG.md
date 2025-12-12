# CHANGELOG

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/)  
Версионирование: SemVer (привязка к `pubspec.yaml` при релизе)

## [Unreleased]
### Added
- Процесс: единые артефакты разработки (docs, worklog, hooks).

### Changed
- Профиль: строка версии приложения теперь берётся из платформы (реальные `version+buildNumber`), а не только из хардкода.

### Added
- Android: добавлен `BootReceiver` (автозапуск после перезагрузки) и ресурсы splash для Android 12+.

### Fixed
- Android splash (до Android 12): `launch_background.xml` теперь масштабирует картинку, чтобы она не “вылазила” за экран.

### Removed


