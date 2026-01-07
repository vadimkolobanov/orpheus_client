import 'package:flutter/services.dart';

/// Мост в Android MainActivity для управления поведением во время звонка:
/// - showWhenLocked / turnScreenOn
/// - (опционально) dismiss keyguard
///
/// Важно: best-effort. Отсутствие нативной реализации не должно ломать звонки.
class CallNativeUiService {
  static const MethodChannel _callChannel = MethodChannel('com.example.orpheus_project/call');

  static Future<void> enableCallMode() async {
    try {
      await _callChannel.invokeMethod('enableCallMode');
    } catch (_) {
      // best-effort
    }
  }

  static Future<void> disableCallMode() async {
    try {
      await _callChannel.invokeMethod('disableCallMode');
    } catch (_) {
      // best-effort
    }
  }

  /// Telecom bridge: забрать (и очистить) pending action после Answer/Reject в системном incoming UI.
  /// Возвращает JSON строку или null.
  static Future<String?> getAndClearPendingCall() async {
    try {
      final v = await _callChannel.invokeMethod<dynamic>('getAndClearPendingCall');
      return v as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getAndClearPendingReject() async {
    try {
      final v = await _callChannel.invokeMethod<dynamic>('getAndClearPendingReject');
      return v as String?;
    } catch (_) {
      return null;
    }
  }

  /// Попросить Android поднять Telecom incoming UI (self-managed ConnectionService).
  /// Используется для сценария: call-offer пришёл по WS, но приложение в фоне.
  static Future<bool> showTelecomIncomingCall({
    required String callerKey,
    required String callerName,
    required String offerJson,
    String? callId,
    int? serverTsMs,
  }) async {
    try {
      final ok = await _callChannel.invokeMethod<dynamic>('showTelecomIncomingCall', {
        'caller_key': callerKey,
        'caller_name': callerName,
        'offer_json': offerJson,
        'call_id': callId,
        'server_ts_ms': serverTsMs,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Сброс нативного "active_call" (на случай, когда звонок завершился по signaling,
  /// а Telecom connection не получил явного disconnect).
  static Future<void> clearActiveTelecomCall() async {
    try {
      await _callChannel.invokeMethod('clearActiveTelecomCall');
    } catch (_) {
      // best-effort
    }
  }
}



