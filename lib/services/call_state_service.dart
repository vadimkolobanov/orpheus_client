// lib/services/call_state_service.dart
// Глобальное состояние звонка, чтобы управление блокировкой было предсказуемым.

import 'package:flutter/foundation.dart';

class CallStateService {
  static final CallStateService instance = CallStateService._();
  CallStateService._();

  /// true, когда открыт `CallScreen` (входящий/исходящий звонок).
  final ValueNotifier<bool> isCallActive = ValueNotifier<bool>(false);

  void setCallActive(bool value) {
    if (isCallActive.value == value) return;
    isCallActive.value = value;
  }
}


