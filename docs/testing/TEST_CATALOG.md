# Каталог тестов (Orpheus Client)

Этот файл — “витрина” для быстрого понимания **объёма тестирования**: что именно зафиксировано тестами и какие правила поведения приложения защищены от регрессий.

> Источник истины по пробелам и приоритетам: `docs/TESTING_GAPS.md`

## Services (Unit)

- **`test/services/auth_service_test.dart`** — правила безопасности: PIN/duress/wipeCode/autoWipe, lockout, безопасный старт при битом конфиге, storage roundtrip.
- **`test/services/panic_wipe_service_test.dart`** — panic wipe: 3 ухода в фон в окне → wipe; разрывы ломают паттерн; защита от повторного срабатывания; manual trigger.
- **`test/services/pending_actions_service_test.dart`** — очередь отложенных отклонений звонков: дедупликация, порядок, remove/clear, best‑effort при сбоях хранилища.
- **`test/services/incoming_call_buffer_test.dart`** — буфер сигналинга звонка: pre‑offer ICE хранится, FIFO `takeAll`, изоляция по sender, точечная очистка.
- **`test/services/call_state_service_test.dart`** — глобальный флаг “активен звонок”: уведомления слушателей только при изменении значения.
- **`test/services/background_call_service_test.dart`** — foreground service во время звонка: идемпотентная инициализация, start/stop по необходимости, payload updateNotification, best‑effort при ошибках backend.
- **`test/services/call_session_controller_test.dart`** — lifecycle звонка (вынесен из CallScreen): callActive flag, start/stop background, hide call‑notification, hang‑up/reject сигналы и системные call‑status сообщения.
- **`test/services/incoming_message_handler_test.dart`** — правила обработки входящих сообщений: ignored types, pre‑offer ICE buffer, порядок “signaling→hide notification”, приватность push (без текста), системные сообщения звонка без уведомления.
- **`test/services/chat_session_controller_test.dart`** — контракт отправки/очистки чата: сохраняет локально (sending), отправляет через crypto+WS, проставляет status sent/failed и шлёт update.
- **`test/services/websocket_outgoing_protocol_test.dart`** — исходящий протокол WS + гарантия доставки `hang-up` через HTTP fallback.
- **`test/services/websocket_service_test.dart`** — базовые контракты WebSocket сервиса: поведение отправки без соединения и т.п.
- **`test/services/presence_service_test.dart`** — presence: subscribe/unsubscribe diff, resubscribe, chunking, обработка апдейтов/ошибок.
- **`test/services/database_service_test.dart`** — работа с БД на уровне сервиса: добавление/чтение сообщений, базовые сценарии.
- **`test/services/update_service_test.dart`** — update: базовые контракты обновлений/версий (по текущей реализации).
- **`test/services/sound_service_test.dart`** — звуки: методы не должны падать (best‑effort).

## WebRTC (Unit, гонки)

- **`test/services/webrtc_candidate_queue_test.dart`** — контракт очереди remote ICE до установки remote SDP (FIFO, best‑effort, reset).
- **`test/services/webrtc_service_queue_integration_test.dart`** — интеграция очереди с `WebRTCService`: ICE до/после SDP, reset на `hangUp`.

## Models (Unit)

- **`test/models/security_config_test.dart`** — `SecurityConfig`: сериализация, requiresUnlock, lockout ladder по ADR 0003, shouldAutoWipe.
- **`test/models/chat_message_model_test.dart`** — `ChatMessage`: дефолты/статусы/маппинг в БД.
- **`test/models/contact_model_test.dart`** — `Contact`: валидация/маппинг.

## Protocol / Core (Unit)

- **`test/services/chat_time_rules_test.dart`** — контракт форматирования времени/даты сообщений: Сегодня/Вчера, скрытие времени для сообщений в одну минуту, day-separator.
- **`test/call_protocol_test.dart`** — формат и базовая совместимость call‑signaling JSON.
- **`test/config_test.dart`** — `AppConfig`: генерация URL, наличие changelog данных.
- **`test/crypto_service_test.dart`** — криптография: генерация ключей, encrypt/decrypt, ошибки.
- **`test/database_test.dart`** — логика БД: CRUD контактов/сообщений.

## Widgets (UI)

- **`test/widgets/contacts_screen_test.dart`** — UI контактов: заголовок/пустое состояние/список/диалог добавления.
- **`test/widgets/welcome_screen_test.dart`** — welcome flow: базовые UI-сценарии.
- **`test/widgets/beta_disclaimer_test.dart`** — beta disclaimer: показывается один раз и сохраняет флаг.
- **`test/widgets/chat_screen_test.dart`** — чат: day-separator (Сегодня), скрытие времени в одну минуту, отправка сообщения (UI + in-memory DB).
- **`test/widgets/call_control_panel_test.dart`** — панель управления звонком: incoming/outgoing UI + callbacks.
- **`test/widgets/call_background_painters_test.dart`** — звонок: smoke-отрисовка фоновых painter’ов.
- **`test/widgets/call_screen_smoke_test.dart`** — CallScreen: smoke для входящего/исходящего + подстановка имени контакта из БД (без падений на desktop/test).
- **`test/widgets/lock_screen_test.dart`** — экран блокировки: PIN success/invalid, duress, wipe-confirm (hold).
- **`test/widgets/pin_setup_screen_test.dart`** — настройка PIN: setPin (mismatch/success), changePin (invalid current PIN).
- **`test/widgets/security_settings_screen_test.dart`** — настройки безопасности: ветки “PIN выключен/включен” (кнопки и секции duress/wipe).
- **`test/widgets/settings_screen_test.dart`** — профиль/настройки: smoke, переход в “Безопасность”, секретный вход в “DEBUG LOGS”.
- **`test/widgets/qr_scan_screen_test.dart`** — QR-сканер: smoke UI + возврат результата (через подмену камеры в тестах).


