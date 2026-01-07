# Orpheus Client — структура проекта и ответственность файлов

## 1) Верхний уровень репозитория
- **`lib/`**: исходный код Flutter‑клиента (экраны, сервисы, модели, тема).
- **`test/`**: unit/widget тесты, фиксируют “контракты поведения”.
- **`docs/`**: инженерная документация клиента (архитектура, безопасность, тестирование и т.п.).
- **`assets/`**: ассеты клиента (картинки/звуки).
- **`android/`**: Android‑часть проекта (Gradle, манифесты, ресурсы, нативный Kotlin).
- **`scripts/`**: PowerShell‑скрипты процесса (hooks/автокоммит/обновление splash).
- **`pubspec.yaml` / `pubspec.lock`**: зависимости и параметры Flutter‑проекта.
- **`CHANGELOG.md`**: внутренний changelog разработки.
- **`AI_WORKLOG.md`**: журнал работ/изменений (не заменяет документацию).

## 2) `lib/` — карта ответственности

### 2.1 Точки входа и “склейка” приложения
- **`lib/main.dart`**: главный entrypoint; инициализация Firebase/уведомлений/крипто/авторизации/мониторинга сети; подключение WebSocket; подписка на входящие сообщения через `IncomingMessageHandler`; запуск `MyApp`.
- **`lib/main_test.dart`**: вспомогательный entry для тестов (если используется; не точка входа прод‑сборки).
- **`lib/config.dart`**: `AppConfig` — версия приложения, список хостов (primary + legacy fallback), генерация URL, legacy fallback для changelog.

### 2.2 Экраны верхнего уровня (в корне `lib/`)
Это “основные” экраны, исторически лежащие не в `lib/screens/`.
- **`lib/welcome_screen.dart`**: welcome/onboarding экран (первичный вход/пояснения).
- **`lib/contacts_screen.dart`**: список контактов, переход в чат/звонок/добавление контактов.
- **`lib/chat_screen.dart`**: UI чата; отправка сообщений (сохранение в БД → шифрование → отправка по WS).
- **`lib/call_screen.dart`**: UI/оркестрация звонка; сигналинг + WebRTC; реконнекты/ICE restart; управление foreground service.
- **`lib/qr_scan_screen.dart`**: добавление контактов через QR.
- **`lib/updates_screen.dart`**: экран обновлений/информации об обновлениях (UI).
- **`lib/license_screen.dart`**: активация лицензии/промокода и ожидание подтверждения по WS.

### 2.3 `lib/screens/` — вспомогательные и “системные” экраны
- **`lib/screens/home_screen.dart`**: основной контейнер/навигация между ключевыми разделами.
- **`lib/screens/status_screen.dart`**: системный монитор/статусы (сеть/WS/диагностика).
- **`lib/screens/settings_screen.dart`**: настройки приложения и навигация в разделы (безопасность, поддержка и т.п.).
- **`lib/screens/security_settings_screen.dart`**: UI управления PIN/duress/wipe/auto‑wipe/panic gesture.
- **`lib/screens/lock_screen.dart`**: экран блокировки (PIN/duress/wipe code сценарии).
- **`lib/screens/pin_setup_screen.dart`**: настройка/смена PIN.
- **`lib/screens/support_chat_screen.dart`**: UI чата поддержки (клиент ↔ админ/разработчик).
- **`lib/screens/debug_logs_screen.dart`**: просмотр/экспорт debug‑логов (для диагностики).
- **`lib/screens/help_screen.dart`**: справка/инструкции в приложении (если используется).

### 2.4 `lib/services/` — сервисный слой (бизнес‑логика и инфраструктура)
Ключевой принцип: сервисы не должны зависеть от UI напрямую; UI вызывает сервисы и подписывается на их потоки.

#### Безопасность и данные
- **`lib/services/auth_service.dart`**: PIN/duress/wipe code, lockout ladder, auto‑wipe; управление `SecurityConfig`; выполнение wipe (крипто + БД + конфиг).
- **`lib/services/panic_wipe_service.dart`**: panic wipe по “3 ухода в фон” (ограничение Flutter), best‑effort.
- **`lib/services/crypto_service.dart`**: ключи X25519, E2E encrypt/decrypt (через `compute`/isolate), хранение ключей в secure storage.
- **`lib/services/database_service.dart`**: SQLite (контакты/сообщения/статистика); поведение в duress mode (пустые выдачи).

#### Сеть и протокол
- **`lib/services/websocket_service.dart`**: WebSocket подключение, реконнект/backoff, ping/pong, смена хоста (fallback), отправка сообщений и сигналов; HTTP fallback для критичных сигналов.
- **`lib/services/incoming_message_handler.dart`**: единая точка обработки входящих WS сообщений (чат/звонки); TTL/дедуп для call-offer; порядок “сначала в CallScreen, потом hide notification”.
- **`lib/services/network_monitor_service.dart`**: монитор сети (события network switch/reconnect/disconnect), триггеры реконнекта.
- **`lib/services/presence_service.dart`**: online‑статусы; subscribe/unsubscribe на pubkeys; resubscribe при реконнекте WS.

#### Звонки и медиа
- **`lib/services/webrtc_service.dart`**: WebRTC peer connection, offer/answer, очередь ICE до remote SDP, ICE restart.
- **`lib/services/webrtc_candidate_queue.dart`**: чистая очередь кандидатов (контракт гонок, тестируемая отдельно).
- **`lib/services/incoming_call_buffer.dart`**: буфер входящих сигналов звонка (ICE кандидаты могут прийти раньше offer).
- **`lib/services/call_state_service.dart`**: глобальный флаг “звонок активен”, чтобы автолок не мешал.
- **`lib/services/background_call_service.dart`**: foreground service на время звонка (Android), best‑effort.
- **`lib/services/call_session_controller.dart`**: вынесенная из UI контрактная логика жизненного цикла звонка (если используется в текущем UI/тестах).

#### Уведомления, релизы, поддержка
- **`lib/services/notification_service.dart`**: FCM init/token, обработка background сообщений, локальные уведомления (privacy‑safe), каналы.
- **`lib/services/update_service.dart`**: проверка обновлений `/api/check-update` с fallback по хостам; открытие download URL.
- **`lib/services/release_notes_service.dart`**: загрузка/кеширование release notes (по текущей реализации).
- **`lib/services/support_chat_service.dart`**: API поддержки (messages/send/logs/unread), экспорт логов и device info.
- **`lib/services/debug_logger_service.dart`**: in‑app логирование и экспорт логов.
- **`lib/services/pending_actions_service.dart`**: очередь offline‑действий (pending messages/rejections) в `SharedPreferences`.
- **`lib/services/device_settings_service.dart`**: локальные настройки устройства/приложения (по текущей реализации).
- **`lib/services/sound_service.dart`**: звуки (best‑effort).
- **`lib/services/badge_service.dart`**: загрузка/кеш бейджей пользователей с fallback по хостам.
- **`lib/services/chat_session_controller.dart`**: контрактная логика чата (отправка/очистка/статусы) вне UI (если используется в текущем UI/тестах).
- **`lib/services/chat_time_rules.dart`**: правила форматирования даты/времени сообщений (вынесено для тестируемости).

### 2.5 `lib/models/` — модели данных
- **`lib/models/contact_model.dart`**: модель контакта + маппинг (DB/UI).
- **`lib/models/chat_message_model.dart`**: модель сообщения + статусы доставки/прочтения.
- **`lib/models/security_config.dart`**: конфигурация безопасности (PIN/duress/wipe, lockout ladder, auto‑wipe).
- **`lib/models/support_message.dart`**: модель сообщения поддержки (user/admin, read/unread).

### 2.6 UI‑слой: `lib/theme/` и `lib/widgets/`
- **`lib/theme/app_theme.dart`**: тема/цвета/стили.
- **`lib/widgets/badge_widget.dart`**: UI бейджа.
- **`lib/widgets/call/background_painters.dart`**: painter’ы фона экрана звонка.
- **`lib/widgets/call/control_panel.dart`**: панель управления звонком (кнопки/состояния/коллбеки).

## 3) `android/` — нативные компоненты (что за что отвечает)
- **`android/app/src/main/kotlin/.../MainActivity.kt`**: основной Android activity.
- **`android/app/src/main/kotlin/.../BootReceiver.kt`**: ресивер автозапуска/системных событий (если включено процессом проекта).
- **`android/app/src/main/res/drawable/ic_stat_orpheus.xml`**: small icon для уведомлений (важно для корректного отображения на Android).
- **`android/app/src/main/AndroidManifest.xml`**: разрешения/компоненты Android.

## 4) `scripts/` — процессные скрипты
- **`scripts/auto-commit.ps1`**: автокоммит с проверками артефактов и Conventional Commits.
- **`scripts/install-hooks.ps1`**: установка git hooks.
- **`scripts/update-android-splash.ps1`**: обновление android splash/ресурсов.

## 5) `test/` — как читать тесты
- **`test/services/*`**: unit‑тесты сервисов (контракты поведения).
- **`test/widgets/*`**: widget‑тесты UI.
- **`test/models/*`**: unit‑тесты моделей.
- **`test/*_test.dart`** в корне: протокол/конфиг/интеграционные контракты.




