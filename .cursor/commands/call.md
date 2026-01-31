# Command: call

Работа со звонками (WebRTC, CallKit, сигналинг).

## Ключевые файлы:
- `lib/call_screen.dart` — UI звонка
- `lib/services/webrtc_service.dart` — WebRTC логика
- `lib/services/incoming_message_handler.dart` — обработка входящих
- `lib/services/call_state_service.dart` — состояние звонка
- `lib/services/notification_service.dart` — FCM и уведомления
- `lib/main.dart` — CallKit события

## Backend (если нужно):
- `D:\Programs\orpheus\main.py` — WebSocket сервер

## При изменениях:
- Проверь все 3 сценария: foreground, background, killed
- Обнови AI_WORKLOG.md
