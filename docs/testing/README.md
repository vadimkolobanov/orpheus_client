# Тестирование (Flutter-клиент Orpheus)

Цель тестов — **зафиксировать правильное поведение** приложения (особенно в сообщениях и звонках), чтобы после любых правок `flutter test` давал уверенность, что критичные сценарии не сломаны.

## Быстрый запуск

### Все тесты
```powershell
flutter test
```

### Быстрый прогон без отчётов
```powershell
.\quick_test.ps1
```

### Прогон с сохранением отчётов
```powershell
.\test_runner.ps1
```

Отчёты сохраняются в `test_reports/`:
- `test_report_YYYY-MM-DD_HH-mm-ss.txt`
- `test_report_YYYY-MM-DD_HH-mm-ss.json`

## Что именно тесты гарантируют (контракты)

### Сообщения (чат)
- Входящий `chat`:
  - расшифровывается через криптосервис
  - сохраняется в БД как входящее непрочитанное (`isSentByMe=false`, `isRead=false`, `status=delivered`)
  - уведомление в фоне показывается **без текста сообщения** (только имя отправителя)
  - системные call-status сообщения (`Исходящий звонок`/`Входящий звонок`/`Пропущен звонок`) **не поднимают** уведомление

### Звонки (сигналинг)
- Входящий `call-offer`:
  - поднимает уведомление о звонке
  - открывает экран звонка
- `ice-candidate`:
  - **буферизуется** (может прийти раньше `call-offer`) и не должен теряться
- `hang-up` / `call-rejected`:
  - в обработчике сначала отправляется сигнал в `CallScreen`, затем скрывается call-уведомление (чтобы скрытие уведомления не блокировало завершение звонка)

### Исходящие пакеты (протокол)
- `sendChatMessage(...)` формирует JSON с `type=chat`, `recipient_pubkey`, `payload`
- `sendSignalingMessage(...)` формирует JSON с `recipient_pubkey`, `type`, `data`
- Для критичных сигналов `hang-up` / `call-rejected` включена гарантия доставки: **WS + HTTP fallback**

## Что пока НЕ покрыто тестами (приоритет)

### Высокий приоритет (критичные сценарии)
- `lib/call_screen.dart`: состояния звонка (Incoming/Dialing/Connecting/Connected), отправка `hang-up`/`call-rejected` при закрытии, системные сообщения в чат
- `lib/chat_screen.dart`: отправка сообщения, очистка истории, поведение при ошибке шифрования/отправки
- `lib/services/webrtc_service.dart`: логика очереди ICE/SDP (частично тестируется косвенно, но не покрыта unit-тестами)
- `lib/services/notification_service.dart`: поведение FCM/local notifications (требует моков Firebase/Notifications)

### Средний приоритет
- `lib/services/auth_service.dart` + PIN/duress/lock/wipe сценарии (часть логики сейчас не закреплена unit-тестами)
- `lib/services/panic_wipe_service.dart`
- `lib/services/pending_actions_service.dart`
- `lib/services/background_call_service.dart`

## Где лежат тесты
- `test/models/` — модели
- `test/services/` — сервисы
- `test/widgets/` — widget-тесты

## Примечание про документацию/логи
- `AI_WORKLOG.md` — **журнал** действий (не “истина” про текущее поведение).
- Актуальная документация проекта — в `docs/` (см. `docs/README.md`).

