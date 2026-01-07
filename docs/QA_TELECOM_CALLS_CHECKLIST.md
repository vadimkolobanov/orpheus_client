# QA чеклист: Android Telecom Incoming Calls (Orpheus)

## Предусловия
- Android 10–14 (минимум один Pixel/чистый AOSP + один OEM: Xiaomi/Huawei/Oppo/Samsung).
- Разрешены уведомления (`POST_NOTIFICATIONS` на 13+), отключены/включены battery optimizations (для проверки).
- Включены настройки:
  - Autostart (OEM)
  - Ignore battery optimizations (best-effort)
  - Full screen intents (Android 14+, best-effort)
- Громкость звонка не на нуле (для проверки рингтона).

## Сценарии (Definition of Done)

1) **Incoming, app foreground**
- Ожидаем: текущий флоу сохраняется (CallScreen по WS `call-offer`), без дублей/вторых экранов.
- Проверить: `CallStateService.isCallActive` корректно выставляется.
- Звук: Flutter `SoundService.playIncomingRingtone()` (или Telecom UI если был поднят).

2) **Incoming, app background**
- Ожидаем: нативный `OrpheusIncomingCallActivity` с Answer/Reject.
- **Звук/вибрация**: системный рингтон (`TYPE_RINGTONE`) + вибрация (паттерн 500ms on/500ms off).
- Accept: поднимается приложение, CallScreen открывается и авто‑accept (после прихода offer).
- Reject: сервер получает `call-rejected` (WS/HTTP fallback), у звонящего корректно завершается.
- **Звук/вибрация останавливаются** при Accept/Reject/закрытии Activity.

3) **Incoming, app killed (swipe away)**
- Ожидаем: нативный `OrpheusIncomingCallActivity`.
- **Звук/вибрация**: как в п.2.
- Accept/Reject: как выше. Никаких "пачек" при восстановлении.

4) **Incoming, lockscreen**
- Ожидаем: нативный входящий UI поверх lockscreen (`showWhenLocked=true`, `turnScreenOn=true`).
- **Звук/вибрация**: как в п.2.
- Экран включается, доступны Answer/Reject.

5) **N=5 оффлайн call-offer**
- Ожидаем: не больше 1 входящего UI (Telecom), устаревшие не показываются (TTL 60s).
- **Звук/вибрация**: только один рингтон (не 5 параллельных).

6) **Дедуп**
- Повторные пуши с тем же `call_id` не создают новый incoming UI.
- Не создают второй рингтон/вибрацию.

7) **Fallback**
- На устройстве/конфигурации, где Telecom не поднимается:
  - показывается текущая call‑нотификация (локальная), звук/вибрация работают
  - нет дублей "Telecom + локальная"

8) **Accept → Соединение (КРИТИЧНО)**
- После Accept в нативном UI:
  - CallScreen открывается с `autoAnswer=true`.
  - Если offer уже есть в pending: сразу accept WebRTC.
  - Если offer ещё нет (FCM data-only): состояние `IncomingWaitingOffer`, ждём `call-offer` по WS.
  - Когда offer приходит: авто‑accept, соединение устанавливается.
- **Проверить в логах**: `TELECOM`, `CALL`, `WS` — корректный флоу.

## Логи/диагностика
- Android logcat тэги: `OrpheusFCM`, `OrpheusCallManager`, `OrpheusConnService`, `OrpheusIncomingCall`, `MainActivity`.
- Flutter логи: `TELECOM`, `CALL`, `MAIN`, `WS`.
- Сервер: категория `FCM` + `DB` offline delivery.

## Известные ограничения OEM
- **Xiaomi**: требуется "Autostart" + "Show on lock screen" в настройках приложения.
- **Huawei/Honor**: "App launch" → Manual → разрешить "Run in background", "Auto-launch".
- **Oppo/Vivo**: аналогично, проверить настройки энергосбережения.
- **Samsung**: "Sleeping apps" — не добавлять Orpheus.


