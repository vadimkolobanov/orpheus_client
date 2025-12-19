# AI_WORKLOG

Журнал действий ИИ/агента в этом репозитории (клиент).

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
  - `powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks.ps1`
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
  - Android < 12: `launch_background.xml` теперь масштабирует `@drawable/splash`, чтобы картинка не выходила за границы.
  - Android 12+: добавлены ресурсы `android12splash` и стили `values-v31`.
  - Android splash: `splash.png`/`android12splash.png` обновлены из `assets/images/logo.png` (щит + ORPHEUS).
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

## 2025-12-12
- Time: текущее время
- Task: Исправление кодировки CHANGELOG, анализ Redis, восстановление авто коммита и создание инструкции по постановке задач
- Changes:
  - Исправлена кодировка в `CHANGELOG.md` (была Windows-1251, теперь UTF-8).
  - Исправлена кодировка в `AI_WORKLOG.md` (была Windows-1251, теперь UTF-8).
  - Создан документ `docs/DECISIONS/0002-redis-integration-plan.md` с анализом использования Redis в проекте.
  - Проанализированы узкие места текущей архитектуры (WebSocket соединения в памяти, проверки лицензий через PostgreSQL, офлайн-сообщения).
  - Определены 7 областей где Redis может улучшить проект:
    1. Управление WebSocket соединениями (приоритет: ВЫСОКИЙ)
    2. Кэширование проверок лицензий (приоритет: ВЫСОКИЙ)
    3. Офлайн-сообщения через Redis (приоритет: СРЕДНИЙ)
    4. Кэширование FCM токенов (приоритет: СРЕДНИЙ)
    5. Rate Limiting (приоритет: ВЫСОКИЙ)
    6. Кэширование статусов платежей (приоритет: НИЗКИЙ)
    7. Pub/Sub для масштабирования (приоритет: СРЕДНИЙ)
  - Создан план внедрения в 3 фазы (v1.1.0, v1.2.0, v1.3.0+).
  - Восстановлен скрипт автоматического коммита `scripts/auto-commit.ps1` с проверкой артефактов.
  - Создан документ `docs/COMMIT_PROCESS.md` с описанием процесса коммита и формата сообщений.
  - Создано правило `.cursor/rules/20-auto-commit.md` для автоматического коммита после изменений.
  - Создан документ `docs/HOW_TO_GIVE_TASKS.md` с инструкцией, как ставить задачи ИИ для автоматической работы с документацией.
  - Исправлена проблема с неотслеживаемыми файлами: создано правило `.cursor/rules/15-git-files.md` и обновлены правила для обязательного добавления всех файлов в git через `git add .`.
- Files:
  - `CHANGELOG.md`
  - `AI_WORKLOG.md`
  - `docs/DECISIONS/0002-redis-integration-plan.md`
  - `docs/COMMIT_PROCESS.md`
  - `docs/HOW_TO_GIVE_TASKS.md`
  - `.cursor/rules/20-auto-commit.md`
  - `.cursor/rules/15-git-files.md`
  - `.cursor/rules/10-artifacts.md`
  - `scripts/auto-commit.ps1`
  - `README.md`
- Commands:
  - Анализ кодовой базы (сервер: `main.py`, `payments.py`, клиент: `main.dart`, сервисы)
  - `.\scripts\auto-commit.ps1` - для автоматического создания коммита

## 2025-12-12
- Time: текущее время
- Task: Реализация системы безопасности входа (PIN-код, duress code, panic wipe)
- Changes:
  - Создана модель конфигурации безопасности `SecurityConfig` с поддержкой:
    - PIN-код (6 цифр) с хешированием SHA-256 + соль (10000 итераций)
    - Код принуждения (duress code) для показа пустого профиля
    - Прогрессивная блокировка при неверных попытках
    - Auto-wipe после N неудачных попыток
  - Создан сервис авторизации `AuthService`:
    - Управление PIN (установка/изменение/отключение)
    - Управление duress кодом
    - Проверка PIN с результатами: success/duress/invalid/lockedOut/autoWipe
    - Полный wipe (удаление ключей, БД, конфигурации)
  - Создан экран блокировки `LockScreen`:
    - Красивый UI с анимациями (частицы, пульсация, shake при ошибке)
    - PIN-pad с haptic feedback
    - Поддержка биометрии
    - Отображение времени до разблокировки при превышении попыток
  - Создан экран настройки PIN `PinSetupScreen`:
    - Режимы: установка/изменение/отключение PIN, установка/отключение duress
    - Подтверждение PIN при установке
    - Проверка текущего PIN при изменении/отключении
  - Создан экран настроек безопасности `SecuritySettingsScreen`:
    - Управление PIN-кодом
    - Управление биометрией
    - Управление кодом принуждения
    - Настройка auto-wipe
    - Информация об экстренном удалении
  - Модифицирован `DatabaseService` для duress mode:
    - В duress mode все методы возвращают пустые данные
    - getContacts() → [], getMessagesForContact() → []
    - getProfileStats() → {contacts: 0, messages: 0, sent: 0}
  - Создан сервис `PanicWipeService`:
    - Отслеживание тройного нажатия кнопки питания
    - Мгновенное удаление всех данных при обнаружении паттерна
  - Интегрирована система безопасности в `main.dart`:
    - Инициализация AuthService и PanicWipeService
    - Показ LockScreen при запуске (если PIN включен)
    - Блокировка при сворачивании приложения
    - Обработка duress mode и auto-wipe
  - Добавлен пункт "Безопасность" в настройки профиля
  - Добавлен пакет `crypto` в зависимости
- Files:
  - `lib/models/security_config.dart` (НОВЫЙ)
  - `lib/services/auth_service.dart` (НОВЫЙ)
  - `lib/services/panic_wipe_service.dart` (НОВЫЙ)
  - `lib/screens/lock_screen.dart` (НОВЫЙ)
  - `lib/screens/pin_setup_screen.dart` (НОВЫЙ)
  - `lib/screens/security_settings_screen.dart` (НОВЫЙ)
  - `lib/services/database_service.dart` (изменён - duress mode)
  - `lib/screens/settings_screen.dart` (изменён - пункт Безопасность)
  - `lib/main.dart` (изменён - интеграция безопасности)
  - `pubspec.yaml` (изменён - добавлен crypto)
  - `CHANGELOG.md`
  - `AI_WORKLOG.md`
- Commands:
  - `flutter pub get` - для установки пакета crypto

## 2025-12-12
- Time: (заполнить реальным временем) local
- Task: Доработки по логам/UX: wipe code, жест panic wipe, стабильность UI, экран “Как пользоваться”
- Changes:
  - Исправлен крэш `setState() called after dispose()` в `SettingsScreen` (проверка `mounted`).
  - `PanicWipeService`: теперь детерминированно считает только последние 3 события `paused` и корректно срабатывает.
  - Wipe: разделены причины (wipe code vs auto-wipe) — логика и логи стали понятнее.
  - Добавлен экран `HelpScreen` (“Как пользоваться”) и пункт меню в профиле.
- Files:
  - `lib/screens/settings_screen.dart`
  - `lib/services/panic_wipe_service.dart`
  - `lib/screens/lock_screen.dart`
  - `lib/main.dart`
  - `lib/screens/help_screen.dart`
  - `AI_WORKLOG.md`

## 2025-12-12
- Time: (заполнить реальным временем) local
- Task: Финализация спринта и подготовка релиза v1.1.0
- Changes:
  - Обновлены версии в `pubspec.yaml` и `AppConfig.appVersion`.
  - Встроенная “История обновлений” дополнена записью v1.1.0 (12.12.2025).
  - `CHANGELOG.md`: `[Unreleased]` очищен, добавлена секция релиза `[1.1.0]`.
- Files:
  - `pubspec.yaml`
  - `lib/config.dart`
  - `CHANGELOG.md`
  - `AI_WORKLOG.md`

## 2025-12-17
- Time: текущее время local
- Task: Миграция домена `orpheus.click` — подготовка клиента (fallback) + документация + стабилизация тестов
- Changes:
  - Добавлена схема миграции доменов: `orpheus.click` (сайт), `api.orpheus.click` (API/WS), `update.orpheus.click` (обновления).
  - Клиент: введён список хостов (новый → старый) и безопасный fallback для HTTP/WS.
  - Обновления: запрос `check-update` выполняется с fallback по хостам; `download_url` поддерживает абсолютные ссылки (для `update.orpheus.click`).
  - WebSocket: при ошибках подключения переключаемся на следующий хост; HTTP fallback для критичных сигналов пробует хосты.
  - Стабилизированы тесты: устранены pending timers/флейки в widget-тестах, добавлены проверки для доменной миграции.
- Files:
  - `docs/DOMAIN_MIGRATION_orpheus.click.md`
  - `lib/config.dart`
  - `lib/services/update_service.dart`
  - `lib/services/websocket_service.dart`
  - `lib/contacts_screen.dart`
  - `lib/welcome_screen.dart`
  - `lib/services/sound_service.dart`
  - `test/config_test.dart`
  - `test/services/update_service_test.dart`
  - `test/widgets/contacts_screen_test.dart`
  - `test/widgets/welcome_screen_test.dart`
  - `pubspec.lock`
  - `CHANGELOG.md`
- Commands:
  - `flutter test`

## 2025-12-19
- Time: текущее время local
- Task: Контрактные тесты для сообщений/звонков + перенос логики из main.dart + уборка документации тестов
- Changes:
  - Вынесена обработка входящих WS сообщений из `main.dart` в тестируемый сервис `IncomingMessageHandler`.
  - Выделен `IncomingCallBuffer` для буферизации сигналов (в первую очередь ICE) и устранения race condition (кандидаты могут прийти раньше offer).
  - Добавлены контрактные тесты для критичных сценариев:
    - входящий `chat`: расшифровка → сохранение → UI update → уведомление в фоне без текста
    - сигналинг звонка: `call-offer`, `ice-candidate`, `call-answer`, `hang-up`, `call-rejected`
    - исходящие пакеты `WebSocketService`: формат JSON и гарантия доставки `hang-up` через WS + HTTP fallback
  - `WebSocketService`: добавлена инъекция `http.Client` и тестовый хук для подключения канала (для детерминированных тестов без сети).
  - Документация: тестовые инструкции/контракты собраны в `docs/testing/README.md`, удалены дублирующие `.md` из корня.
- Files:
  - `lib/services/incoming_message_handler.dart`
  - `lib/services/incoming_call_buffer.dart`
  - `lib/services/websocket_service.dart`
  - `lib/main.dart`
  - `lib/call_screen.dart`
  - `test/services/incoming_message_handler_test.dart`
  - `test/services/websocket_outgoing_protocol_test.dart`
  - `docs/testing/README.md`
  - `docs/README.md`
  - `README.md`
  - `CHANGELOG.md`
  - `AI_WORKLOG.md`
- Commands:
  - `flutter test`

## 2025-12-19
- Time: текущее время local
- Task: История обновлений — переход на публичные release notes из OPHEUS_ADMIN + уточнение процесса
- Changes:
  - Экран “История обновлений” теперь пытается загрузить release notes с публичного API сайта, с fallback на встроенный список при офлайне.
  - Добавлен `ReleaseNotesService` для получения публичных релизов.
  - Документация/процесс: уточнено, что “Что нового” ведём в `OPHEUS_ADMIN` → “Версии” (единый публичный changelog).
- Files:
  - `lib/services/release_notes_service.dart`
  - `lib/updates_screen.dart`
  - `lib/config.dart`
  - `docs/COMMIT_PROCESS.md`
  - `docs/REPORT_SINCE_2025-12-06.md`
  - `docs/HOW_TO_GIVE_TASKS.md`
  - `.cursor/rules/10-artifacts.md`
  - `.cursor/commands/update-artifacts.md`
  - `CHANGELOG.md`
  - `AI_WORKLOG.md`
- Commands:
  - `flutter test`

## 2025-12-19
- Time: 12:54 local
- Task: Клиент — одноразовый дисклеймер о тестовой версии
- Changes:
  - Добавлен дисклеймер, который показывается один раз при входе в приложение и сохраняет флаг “больше не показывать”.
  - Дисклеймер показывается до диалога настройки устройства, чтобы диалоги не накладывались.
  - Добавлены widget-тесты на одноразовый показ/сохранение флага дисклеймера.
- Files:
  - `lib/screens/home_screen.dart`
  - `test/widgets/beta_disclaimer_test.dart`
  - `CHANGELOG.md`
  - `AI_WORKLOG.md`
- Commands:
  - `flutter test`

## 2025-12-19
- Time: 13:18 local
- Task: UI — убрать надпись про “Сквозное шифрование” (визуальный шум)
- Changes:
  - Убран зелёный блок/лейбл “Сквозное шифрование” в списке контактов.
  - Убран баннер “Сквозное шифрование · ChaCha20-Poly1305” вверху чата и подпись в пустом состоянии.
- Files:
  - `lib/contacts_screen.dart`
  - `lib/chat_screen.dart`
  - `AI_WORKLOG.md`
- Commands:
  - (не запускались)
