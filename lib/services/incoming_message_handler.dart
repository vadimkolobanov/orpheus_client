import 'dart:convert';

import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/incoming_call_buffer.dart';
import 'package:orpheus_project/services/call_native_ui_service.dart';

abstract interface class IncomingMessageCrypto {
  Future<String> decrypt(String senderPublicKeyBase64, String encryptedPayload);
}

abstract interface class IncomingMessageDatabase {
  Future<void> addMessage(ChatMessage message, String contactPublicKey);
  Future<String?> getContactName(String publicKey);
}

abstract interface class IncomingMessageNotifications {
  Future<void> showCallNotification({required String callerName});
  Future<void> hideCallNotification();
  Future<void> showMessageNotification({required String senderName});
}

typedef OpenCallScreen = void Function({
  required String contactPublicKey,
  required Map<String, dynamic> offer,
});

/// Единая точка обработки входящих WS сообщений.
///
/// Цель: чтобы поведение было зафиксировано тестами, а `main.dart` был тонкой обвязкой.
class IncomingMessageHandler {
  IncomingMessageHandler({
    required IncomingMessageCrypto crypto,
    required IncomingMessageDatabase database,
    required IncomingMessageNotifications notifications,
    required IncomingCallBuffer callBuffer,
    required OpenCallScreen openCallScreen,
    required void Function(Map<String, dynamic> msg) emitSignaling,
    required void Function(String senderPublicKey) emitChatUpdate,
    required bool Function() isAppInForeground,
    bool Function()? isCallActive,
    bool Function(String senderPublicKey)? suppressCallNotification,
    Future<bool> Function({
      required String senderPublicKey,
      required String callerName,
      required Map<String, dynamic> offer,
      required int? serverTsMs,
      required String? callId,
    })? tryShowTelecomIncoming,
    int Function()? nowMs,
  })  : _crypto = crypto,
        _db = database,
        _notif = notifications,
        _callBuffer = callBuffer,
        _openCallScreen = openCallScreen,
        _emitSignaling = emitSignaling,
        _emitChatUpdate = emitChatUpdate,
        _isAppInForeground = isAppInForeground,
        _isCallActive = (isCallActive ?? (() => false)),
        _suppressCallNotification = (suppressCallNotification ?? ((_) => false)),
        _tryShowTelecomIncoming = (tryShowTelecomIncoming ??
            ({
              required String senderPublicKey,
              required String callerName,
              required Map<String, dynamic> offer,
              required int? serverTsMs,
              required String? callId,
            }) async =>
                false),
        _nowMs = (nowMs ?? (() => DateTime.now().millisecondsSinceEpoch));

  final IncomingMessageCrypto _crypto;
  final IncomingMessageDatabase _db;
  final IncomingMessageNotifications _notif;
  final IncomingCallBuffer _callBuffer;
  final OpenCallScreen _openCallScreen;
  final void Function(Map<String, dynamic> msg) _emitSignaling;
  final void Function(String senderPublicKey) _emitChatUpdate;
  final bool Function() _isAppInForeground;
  final bool Function() _isCallActive;
  final bool Function(String senderPublicKey) _suppressCallNotification;
  final Future<bool> Function({
    required String senderPublicKey,
    required String callerName,
    required Map<String, dynamic> offer,
    required int? serverTsMs,
    required String? callId,
  }) _tryShowTelecomIncoming;
  final int Function() _nowMs;

  // Анти-спам/анти-дубликаты для call-offer: на некоторых сетях/устройствах возможны повторы.
  final Map<String, int> _lastCallOfferHandledAtMsBySender = {};
  final Map<String, int> _lastCallOfferHandledAtMsByCallId = {};
  static const int _callOfferDebounceMs = 2500;
  static const int _callOfferTtlMs = 60 * 1000;

  // Иногда сервер/сеть доставляют hang-up/call-rejected несколько раз (особенно при реконнекте).
  // Защищаемся, чтобы не дергать UI/очистки многократно.
  final Map<String, int> _lastTerminationHandledAtMsByKey = {};
  static const int _terminationDebounceMs = 2000;

  static const _ignoredTypes = <String>{
    'error',
    'payment-confirmed',
    'license-status',
    'pong',
    'support-reply',
    'presence-state',
    'presence-update',
  };

  Future<void> handleRawMessage(String messageJson) async {
    final dynamic decoded = json.decode(messageJson);
    if (decoded is! Map<String, dynamic>) return;
    await handleDecoded(decoded);
  }

  Future<void> handleDecoded(Map<String, dynamic> messageData) async {
    final type = messageData['type'] as String?;
    final senderKey = messageData['sender_pubkey'] as String?;

    // Пропускаем служебные сообщения и любые пакеты без sender_pubkey.
    if (type == null || senderKey == null || _ignoredTypes.contains(type)) return;

    // === ЗВОНКИ ===
    if (type == 'call-offer') {
      final data = messageData['data'];
      if (data is! Map<String, dynamic>) return;

      // 1) TTL (backward-compatible): если сервер прислал server_ts_ms и он слишком старый — игнорируем.
      final now = _nowMs();
      final dynamic tsRaw = messageData['server_ts_ms'] ?? data['server_ts_ms'];
      final int? serverTsMs = tsRaw is int ? tsRaw : int.tryParse(tsRaw?.toString() ?? '');
      if (serverTsMs != null && (now - serverTsMs) > _callOfferTtlMs) {
        return;
      }

      // 1.1) Дедуп по call_id (предпочтительно): защищает от повторной доставки одного и того же offer.
      final dynamic callIdRaw = messageData['call_id'] ?? data['call_id'];
      final String? callId = callIdRaw?.toString().trim().isNotEmpty == true ? callIdRaw.toString() : null;
      if (callId != null) {
        final lastById = _lastCallOfferHandledAtMsByCallId[callId];
        if (lastById != null && (now - lastById) < _callOfferTtlMs) {
          return;
        }
        _lastCallOfferHandledAtMsByCallId[callId] = now;
      }

      // 2) Если уже есть активный звонок/экран — НЕ поднимаем второй входящий UI,
      // но ВАЖНО: call-offer может прийти ПОСЛЕ нажатия Answer в нативном Telecom UI.
      // В этом случае нам нужно доставить offer в уже открытый CallScreen через signaling stream.
      if (_isCallActive()) {
        _emitSignaling(messageData);
        return;
      }
      
      // 2.1) КРИТИЧНО: Если был Telecom Accept и мы ждём поздний offer — пропускаем его в signaling,
      // НЕ открываем новый CallScreen (он уже открыт или будет открыт из pending).
      if (_suppressCallNotification(senderKey)) {
        _emitSignaling(messageData);
        return;
      }

      // 3) Дедуп по sender (короткое окно): защита от дублей при выходе из оффлайна/повторной доставке.
      final last = _lastCallOfferHandledAtMsBySender[senderKey];
      if (last != null && (now - last) < _callOfferDebounceMs) {
        return;
      }
      _lastCallOfferHandledAtMsBySender[senderKey] = now;

      // ВАЖНО: не очищаем уже пришедшие кандидаты (если они пришли раньше offer).
      _callBuffer.ensure(senderKey);

      final contactName = (await _db.getContactName(senderKey))?.trim();
      final displayName = (contactName != null && contactName.isNotEmpty)
          ? contactName
          : senderKey.substring(0, 8);

      // Если приложение в фоне — поднимаем системный Telecom incoming UI (как Telegram),
      // и НЕ открываем CallScreen/локальные нотификации до действия пользователя.
      if (!_isAppInForeground()) {
        final shown = await _tryShowTelecomIncoming(
          senderPublicKey: senderKey,
          callerName: displayName,
          offer: data,
          serverTsMs: serverTsMs,
          callId: callId,
        );
        if (shown) {
          return;
        }
      }

      if (!_suppressCallNotification(senderKey)) {
        await _notif.showCallNotification(callerName: displayName);
      }
      _openCallScreen(contactPublicKey: senderKey, offer: data);
      return;
    }

    if (type == 'ice-candidate') {
      // Всегда буферизуем (кандидаты могут прийти раньше offer).
      _callBuffer.add(senderKey, messageData);
      _emitSignaling(messageData);
      return;
    }

    if (type == 'call-answer') {
      _emitSignaling(messageData);
      return;
    }

    // ICE restart signals - пробрасываем в CallScreen для renegotiation
    if (type == 'ice-restart' || type == 'ice-restart-answer') {
      _emitSignaling(messageData);
      return;
    }

    if (type == 'hang-up' || type == 'call-rejected') {
      // Дедуп повторных "завершений" на коротком окне.
      final now = _nowMs();
      final termKey = '$senderKey:$type';
      final lastTerm = _lastTerminationHandledAtMsByKey[termKey];
      if (lastTerm != null && (now - lastTerm) < _terminationDebounceMs) {
        return;
      }
      _lastTerminationHandledAtMsByKey[termKey] = now;

      _callBuffer.clear(senderKey);
      _lastCallOfferHandledAtMsBySender.remove(senderKey);
      // call_id может не прийти в hang-up, но если пришёл — уберём, чтобы не блокировать следующий звонок.
      final dynamic callIdRaw = messageData['call_id'];
      final String? callId = callIdRaw?.toString().trim().isNotEmpty == true ? callIdRaw.toString() : null;
      if (callId != null) {
        _lastCallOfferHandledAtMsByCallId.remove(callId);
      }

      // КРИТИЧНО: сначала сообщаем в CallScreen, затем пытаемся спрятать уведомление.
      _emitSignaling(messageData);
      await _notif.hideCallNotification();
      // Best-effort: сбрасываем native active-call, чтобы не было ложного active_call_exists
      // при следующем входящем (особенно если Telecom UI был поднят, но завершение пришло по signaling).
      await CallNativeUiService.clearActiveTelecomCall();
      return;
    }

    // === ЧАТ ===
    if (type == 'chat') {
      final payload = messageData['payload'] as String?;
      if (payload == null) return;

      final decryptedMessage = await _crypto.decrypt(senderKey, payload);

      final receivedMessage = ChatMessage(
        text: decryptedMessage,
        isSentByMe: false,
        status: MessageStatus.delivered,
        isRead: false,
      );

      await _db.addMessage(receivedMessage, senderKey);
      _emitChatUpdate(senderKey);

      final isCallStatusMessage = _isCallStatusMessage(decryptedMessage);
      if (!_isAppInForeground() && !isCallStatusMessage) {
        final contactName = (await _db.getContactName(senderKey))?.trim();
        final displayName = (contactName != null && contactName.isNotEmpty)
            ? contactName
            : senderKey.substring(0, 8);
        await _notif.showMessageNotification(senderName: displayName);
      }
    }
  }

  static bool _isCallStatusMessage(String message) {
    const callStatusMessages = [
      'Исходящий звонок',
      'Входящий звонок',
      'Пропущен звонок',
    ];
    return callStatusMessages.contains(message);
  }
}


