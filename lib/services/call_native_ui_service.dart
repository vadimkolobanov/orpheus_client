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
}


