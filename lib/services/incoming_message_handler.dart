import 'dart:convert';

import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/incoming_call_buffer.dart';

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
  })  : _crypto = crypto,
        _db = database,
        _notif = notifications,
        _callBuffer = callBuffer,
        _openCallScreen = openCallScreen,
        _emitSignaling = emitSignaling,
        _emitChatUpdate = emitChatUpdate,
        _isAppInForeground = isAppInForeground;

  final IncomingMessageCrypto _crypto;
  final IncomingMessageDatabase _db;
  final IncomingMessageNotifications _notif;
  final IncomingCallBuffer _callBuffer;
  final OpenCallScreen _openCallScreen;
  final void Function(Map<String, dynamic> msg) _emitSignaling;
  final void Function(String senderPublicKey) _emitChatUpdate;
  final bool Function() _isAppInForeground;

  static const _ignoredTypes = <String>{
    'error',
    'payment-confirmed',
    'license-status',
    'pong',
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

      // ВАЖНО: не очищаем уже пришедшие кандидаты (если они пришли раньше offer).
      _callBuffer.ensure(senderKey);

      final contactName = (await _db.getContactName(senderKey))?.trim();
      final displayName = (contactName != null && contactName.isNotEmpty)
          ? contactName
          : senderKey.substring(0, 8);

      await _notif.showCallNotification(callerName: displayName);
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
      _callBuffer.clear(senderKey);

      // КРИТИЧНО: сначала сообщаем в CallScreen, затем пытаемся спрятать уведомление.
      _emitSignaling(messageData);
      await _notif.hideCallNotification();
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


