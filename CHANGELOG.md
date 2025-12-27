# CHANGELOG

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/)  
Версионирование: SemVer (привязка к `pubspec.yaml` при релизе)

## [Unreleased]
### Added
-

### Changed
-

### Fixed
-

### Removed
-

## [1.1.0] - 2025-12-12
### Added
- Безопасность: PIN (6 цифр), duress PIN и wipe/auto-wipe (опционально), экран блокировки (биометрия — опционально).
- UI: экран “Как пользоваться”, улучшения чата (карточки событий звонков).
- Android: `BootReceiver` (автозапуск после перезагрузки) + splash ресурсы для Android 12+.
- Стабильность/сеть: fallback по хостам для WebSocket (переезд на `api.orpheus.click`).
- Процесс/документация: восстановлены `.cursor/rules`/`.cursor/commands`/`.githooks`, добавлены docs и скрипты авто-коммита; release notes ведём в `OPHEUS_ADMIN` → “Версии”.

### Changed
- Профиль: версия берётся из платформы (`version+buildNumber`), а не из хардкода.
- `main.dart`: входящие WS-сообщения обработаны через `IncomingMessageHandler` (тонкая обвязка).

### Fixed
- Тесты/стабильность: убраны pending timers и флейки в widget-тестах.
- Звонки: ICE candidate не теряется (даже если приходит до `call-offer`), порядок действий для `hang-up`/`call-rejected` стабилизирован.
- Настройки: устранён `setState() called after dispose()`, автолок не мешает активному звонку.

### Removed
- UI: убраны баннеры/надписи про “Сквозное шифрование” в списке контактов и чате (меньше визуального шума).
- Процесс: убраны дублирующие документы по тестам (перенос в `docs/testing/README.md`).
