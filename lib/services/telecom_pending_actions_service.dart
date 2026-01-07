import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:orpheus_project/services/call_native_ui_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';

/// Хранит pending действия из Android Telecom (Answer/Reject) в памяти,
/// чтобы дальше корректно отработать в существующем signaling флоу.
class TelecomPendingActionsService {
  TelecomPendingActionsService._();
  static final TelecomPendingActionsService instance = TelecomPendingActionsService._();

  String? _pendingAcceptedCallerKey;
  String? _pendingAcceptedCallId;
  int? _pendingAcceptedStoredTsMs;
  Map<String, dynamic>? _pendingAcceptedOffer;
  
  /// Флаг: были ли мы созданы в результате Telecom Accept
  /// (чтобы корректно обрабатывать поздние call-offer)
  bool _waitingForLateOffer = false;

  @visibleForTesting
  void debugReset() {
    _pendingAcceptedCallerKey = null;
    _pendingAcceptedCallId = null;
    _pendingAcceptedStoredTsMs = null;
    _pendingAcceptedOffer = null;
    _waitingForLateOffer = false;
  }

  /// Забрать pending accept из native и сохранить в памяти.
  /// Возвращает true, если что-то было.
  Future<bool> consumeNativePendingAccept() async {
    final jsonStr = await CallNativeUiService.getAndClearPendingCall();
    if (jsonStr == null || jsonStr.trim().isEmpty) {
      DebugLogger.info('TELECOM', 'consumeNativePendingAccept: no pending');
      return false;
    }

    DebugLogger.info('TELECOM', 'consumeNativePendingAccept: got JSON (len=${jsonStr.length})');

    try {
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      final callerKey = decoded['caller_key']?.toString();
      if (callerKey == null || callerKey.isEmpty) {
        DebugLogger.warn('TELECOM', 'consumeNativePendingAccept: no caller_key');
        return false;
      }

      _pendingAcceptedCallerKey = callerKey;
      _pendingAcceptedCallId = decoded['call_id']?.toString();
      _pendingAcceptedStoredTsMs = _tryParseInt(decoded['stored_ts_ms']);
      
      final offerRaw = decoded['offer_data'];
      if (offerRaw != null) {
        try {
          final parsed = json.decode(offerRaw.toString());
          if (parsed is Map<String, dynamic>) {
            _pendingAcceptedOffer = parsed;
            DebugLogger.success('TELECOM', 'consumeNativePendingAccept: offer found for $callerKey');
          }
        } catch (e) {
          DebugLogger.warn('TELECOM', 'consumeNativePendingAccept: offer parse error: $e');
        }
      } else {
        // Offer не был в pending — будем ждать его по WS
        _waitingForLateOffer = true;
        DebugLogger.info('TELECOM', 'consumeNativePendingAccept: no offer, will wait for late call-offer');
      }
      
      DebugLogger.success('TELECOM', 'consumeNativePendingAccept: pending for $callerKey (offer=${_pendingAcceptedOffer != null})');
      return true;
    } catch (e) {
      DebugLogger.error('TELECOM', 'consumeNativePendingAccept: parse error: $e');
      return false;
    }
  }
  
  /// Проверяет, ожидаем ли мы поздний offer (для подавления дублей в handler)
  bool get isWaitingForLateOffer => _waitingForLateOffer && _pendingAcceptedCallerKey != null;

  /// Забрать pending reject из native. Возвращает caller_key, если есть.
  Future<String?> consumeNativePendingRejectCallerKey() async {
    final jsonStr = await CallNativeUiService.getAndClearPendingReject();
    if (jsonStr == null || jsonStr.trim().isEmpty) return null;
    try {
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      final callerKey = decoded['caller_key']?.toString();
      if (callerKey == null || callerKey.isEmpty) return null;
      return callerKey;
    } catch (_) {
      return null;
    }
  }

  bool shouldAutoAnswerForCaller(String callerKey) {
    if (_pendingAcceptedCallerKey == null) return false;
    return _pendingAcceptedCallerKey == callerKey;
  }

  String? peekPendingAcceptedCallerKey() => _pendingAcceptedCallerKey;

  void markAutoAnswerConsumed() {
    DebugLogger.info('TELECOM', 'markAutoAnswerConsumed: clearing pending for $_pendingAcceptedCallerKey');
    _pendingAcceptedCallerKey = null;
    _pendingAcceptedCallId = null;
    _pendingAcceptedStoredTsMs = null;
    _pendingAcceptedOffer = null;
    _waitingForLateOffer = false;
  }

  Map<String, dynamic>? takePendingAcceptedOfferIfMatches(String callerKey) {
    if (_pendingAcceptedCallerKey != callerKey) return null;
    final offer = _pendingAcceptedOffer;
    _pendingAcceptedOffer = null;
    return offer;
  }

  static int? _tryParseInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }
}


