# Android Incoming Calls (Telecom/ConnectionService) — Orpheus

Цель: добавить **нативную Android‑прокладку** для входящих звонков через `Telecom/ConnectionService`, чтобы входящий UI был **системным полноэкранным** (background/lockscreen/killed), как у Telegram.

Ограничения:
- Flutter остаётся основным.
- Без глобальных рефакторингов.
- Дедуп/TTL обязателен (чтобы не было “пачек”).
- Если OEM/OS блокирует — понятный fallback (обычная нотификация), без дублей.

## Таблица (ШАГ 0): сценарии → текущее → желаемое → точка в коде → минимальная правка

| Сценарий | Сейчас | Нужно | Где в коде | Что меняем минимально |
|---|---|---|---|---|
| App foreground, incoming `call-offer` по WS | Открывается `CallScreen`, играет рингтон (`SoundService`), call‑нотификация скрывается | ОК (можно оставить) | `lib/services/incoming_message_handler.dart`, `lib/call_screen.dart` | Не трогаем основной флоу; только добавим анти‑дубликаты с Telecom |
| App background, FCM **notification payload** | Android показывает пуш сам, fullScreenIntent **не гарантирован** (OEM) | Системный incoming UI (Telecom) | `lib/services/notification_service.dart` | Для Telecom нужен **data‑only** push, иначе код не вызовется |
| App background, FCM **data‑only** | Dart background handler показывает локальную call‑нотификацию | Telecom incoming UI | `lib/services/notification_service.dart` | Для звонков введём `native_telecom=1` и тогда **не показываем локальную** call‑нотификацию |
| App killed (swipe away), incoming звонок | `notification` payload может показать обычный пуш, но не “как звонок” | Telecom incoming UI в killed | Android native | Добавляем `ConnectionService` + `FirebaseMessagingService` перехват для `native_telecom=1` |
| Lockscreen (экран заблокирован) | FullScreenIntent может быть заблокирован/не показан | Системный экран звонка с Answer/Reject | Android Telecom | `TelecomManager.addNewIncomingCall(...)` + `PhoneAccount(CAPABILITY_SELF_MANAGED)` |
| N=5 оффлайн/повторы доставки | Flutter уже имеет debounce для `call-offer` | Не больше 1 incoming UI, устаревшие не показывать | Android + Flutter | Kotlin: дедуп по `call_id` + TTL по `server_ts_ms`. Flutter: сохраняем текущую защиту и не создаём вторые нотификации |

## Ключевая реальность доставки

- `notification` payload в фоне часто **не вызывает** обработчик приложения → нельзя “автоподнять Telecom”.
- Для Telecom нужен **data‑only high priority** push для звонков (с TTL ~60s).
- Текущий пуш с `notification` оставляем как fallback/совместимость.

## Протокол payload для звонков (сервер → клиент)

### Базовые поля (в `data`)
- `type`: `incoming_call` (или legacy `call`)
- `caller_key`: публичный ключ звонящего
- `caller_name`: короткое отображаемое имя (best-effort)
- `call_id`: уникальный id звонка (для дедупа)
- `server_ts_ms`: серверный timestamp (для TTL)

### Флаг Telecom режима
- `native_telecom=1`: клиент Android (новый) **пытается** поднять Telecom incoming UI.
  - Если Telecom успешно поднят — Dart handler **не показывает** локальную call‑нотификацию (анти‑дубли).
  - Если Telecom не смог (OEM/permission/ошибка) — сообщение падает в Flutter и срабатывает текущий fallback (локальная нотификация).

## Rollout (обратно‑совместимо)

- Клиент при `register-fcm` по WS дополнительно шлёт:
  - `platform: "android" | "ios" | ...`
  - `android_native_telecom: true/false`
- Сервер хранит это в отдельной таблице `push_tokens_meta` и:
  - для `android_native_telecom=true` шлёт **data-only** push с `native_telecom=1`
  - иначе оставляет legacy `notification + data` пуш (как было)

## Известные OEM ограничения (важно для QA)

- MIUI / EMUI / ColorOS могут ограничивать background delivery и полноэкранные интенты.
- Нужны user‑настройки: автозапуск, исключение из battery optimization, full-screen intents (Android 14+).
- Даже с Telecom возможны “молчаливые” ограничения на конкретных девайсах — поэтому fallback‑нотификация остаётся.


