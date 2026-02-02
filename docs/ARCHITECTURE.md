# Архитектура клиента (актуальная)

## Контекст и границы
Эта архитектура описывает **Flutter‑клиент** (`orpheus_client`). Сервер связи и админ‑панель — отдельные компоненты и описываются вне этого репозитория.

## Основные подсистемы (карта)
Ключевые файлы/модули:
- **Запуск приложения и “склейка” сервисов**: `lib/main.dart`
- **Конфиг URL и доменный fallback**: `lib/config.dart`
- **Криптография (ключи + E2E шифрование сообщений)**: `lib/services/crypto_service.dart`
- **Локальное хранение (контакты/сообщения)**: `lib/services/database_service.dart`
- **Сеть и протокол** (WS + HTTP fallback для критичных сигналов): `lib/services/websocket_service.dart`
- **Единая обработка входящих WS‑сообщений**: `lib/services/incoming_message_handler.dart`
- **Звонки**:
  - UI/оркестрация: `lib/call_screen.dart`
  - WebRTC: `lib/services/webrtc_service.dart`
  - Буфер входящих ICE: `lib/services/incoming_call_buffer.dart`
  - Глобальный флаг “звонок активен”: `lib/services/call_state_service.dart`
  - Foreground service на время звонка: `lib/services/background_call_service.dart`
- **Уведомления** (FCM + локальные): `lib/services/notification_service.dart`
- **Безопасность входа/duress/wipe**: `lib/services/auth_service.dart`, ADR: `docs/DECISIONS/0003-security-system.md`
- **Presence (онлайн‑статусы)**: `lib/services/presence_service.dart`
- **Обновления** (check-update + fallback по хостам): `lib/services/update_service.dart`
- **Лицензия/промо‑активация**: `lib/license_screen.dart`
- **Поддержка (чат)**: `lib/services/support_chat_service.dart`

## Структура каталогов
- `lib/` — исходный код приложения
- `test/` — unit/widget тесты (контракты поведения)
- `android/` — Android‑часть (ресурсы/манифесты/gradle)

## Схема запуска (boot sequence)
Текущая последовательность инициализации (см. `lib/main.dart`):
1. Firebase + FCM background handler
2. `NotificationService.init()`
3. `CryptoService.init()` (ключи из secure storage)
4. `AuthService.init()` (security config из secure storage)
5. `PanicWipeService.init()` (наблюдение lifecycle)
6. `NetworkMonitorService.init()` (события сети)
7. `WebSocketService.connect(pubkey)` (если ключи есть)
8. Подписка на WS‑стрим и обработка через `IncomingMessageHandler`
9. `TelemetryService.init()` (полные логи в БД в режиме разработки)

## Телеметрия (режим разработки, временно)
Цель: видеть **полный цикл жизни клиента** и события сервера в БД, включая звонки, WS/HTTP, FCM background.

### Клиент
- Источник событий: `DebugLogger` + перехват `debugPrint` и `FlutterError`.
- Сервис: `lib/services/telemetry_service.dart`
- Транспорт: HTTP батчи на `/api/logs/batch`
- Контекст событий:
  - `pubkey`, `peer_pubkey`, `call_id` (если есть)
  - `app_version`, `device_info`, `os`
  - `network`, `app_state`
- Фоновый FCM handler также отправляет базовую телеметрию (с `recipient_pubkey` из push data).

### Сервер (репозиторий `D:\Programs\orpheus`)
- Таблица: `telemetry_logs`
- Логируются:
  - все HTTP запросы/ответы (middleware),
  - все WS сообщения (raw payload),
  - Redis‑routing события (если включён Redis bridge).
- TTL на очистку: `TELEMETRY_RETENTION_DAYS` (по умолчанию 14)
- Ограничение размера деталей: `TELEMETRY_MAX_DETAILS_SIZE` (по умолчанию 100000)

### Анализ
- По клиенту: `WHERE pubkey = '...'`
- По звонку: `WHERE call_id = '...'`

## Потоки данных (как работает функционал)

### 1) Идентичность и ключи
- **Идентификатор пользователя**: публичный ключ (base64).
- **Хранение ключей**: `flutter_secure_storage` (`CryptoService`).
- **Крипто для сообщений**: ECDH X25519 → общий секрет → ChaCha20‑Poly1305 AEAD (см. `CryptoService.encrypt/decrypt`).

### 2) Чат (сообщения)
**Исходящее сообщение** (`lib/chat_screen.dart` → `WebSocketService.sendChatMessage`):
1. UI пишет текст → сохраняем в SQLite через `DatabaseService.addMessage`.
2. Шифруем через `CryptoService.encrypt(recipientPubKey, text)` (в isolate).
3. Отправляем по WS: `{type:"chat", recipient_pubkey, payload}`.
4. Если WS не подключен — payload кладётся в очередь `PendingActionsService` и отправляется позже при реконнекте.

**Входящее сообщение** (`WebSocketService.stream` → `IncomingMessageHandler`):
1. Получаем `{type:"chat", sender_pubkey, payload}`.
2. Дешифруем payload через `CryptoService.decrypt(senderKey, payload)`.
3. Сохраняем в SQLite как входящее непрочитанное.
4. Если приложение в фоне — показываем уведомление (без текста сообщения), кроме системных “call-status” сообщений.

### 3) Звонки (сигналинг + WebRTC)
**Сигналинг** идёт через WS (и частично через HTTP fallback для критичных сигналов).

Входящий `call-offer`:
1. `IncomingMessageHandler` применяет TTL (если есть server_ts_ms), дедуп по sender и проверку “звонок уже активен”.
2. Поднимается call‑уведомление и открывается `CallScreen`.
3. ICE кандидаты, пришедшие раньше offer, не теряются: они буферизуются `IncomingCallBuffer`.

ICE кандидаты:
- Всегда буферизуются и пробрасываются в `CallScreen`.

Завершение звонка (`hang-up` / `call-rejected`):
- Сначала сигнал пробрасывается в `CallScreen`, затем скрывается уведомление (важный порядок, зафиксирован как контракт).

**WebRTC** (`WebRTCService`):
- Создание peerConnection, сбор local audio stream, создание offer/answer.
- Защита от гонок: очередь remote ICE до установки remote SDP.
- Поддержан ICE restart при смене сети (сигналы `ice-restart`, `ice-restart-answer`).

### 4) Уведомления
`NotificationService`:
- FCM init, получение token и обновления.
- Background handler показывает **локальные уведомления только для data-only** сообщений (чтобы не ломать звук/поведение системного notification payload).
- Приватность: push по сообщениям не содержит текста сообщения (на стороне клиента показывается “Новое сообщение”).

### 5) Домены и fallback (устойчивость)
- `AppConfig.apiHosts` задаёт приоритет: новый домен → legacy.
- `WebSocketService` умеет переключать хост при ошибке подключения.
- `UpdateService` делает HTTP GET с fallback по всем хостам.

### 6) Безопасность приложения (PIN / duress / wipe)
Подробно: `docs/DECISIONS/0003-security-system.md`.
- PIN/duress/wipe code и lockout ladder — `AuthService` + `SecurityConfig`.
- Duress mode влияет на выдачу данных из `DatabaseService` (контакты/сообщения/статистика возвращаются пустыми), при этом входящие сообщения **сохраняются**, чтобы не терять данные.
- Panic wipe реализован как “3 события ухода в фон” (ограничение Flutter; по умолчанию выключено).

## Где фиксировать решения и контракты
- Архитектурные решения: `docs/DECISIONS/`
- Контракты поведения: тесты (см. `docs/testing/README.md` и `docs/TESTING_GAPS.md`)


