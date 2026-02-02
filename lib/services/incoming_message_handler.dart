import 'dart:convert';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/incoming_call_buffer.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/call_id_storage.dart';

abstract interface class IncomingMessageCrypto {
  Future<String> decrypt(String senderPublicKeyBase64, String encryptedPayload);
}

abstract interface class IncomingMessageDatabase {
  Future<void> addMessage(ChatMessage message, String contactPublicKey);
  Future<String?> getContactName(String publicKey);
}

abstract interface class IncomingMessageNotifications {
  Future<void> showCallNotification({required String callerName, String? payload});
  Future<void> hideCallNotification();
  Future<void> showMessageNotification({required String senderName});
}

typedef OpenCallScreen = void Function({
  required String contactPublicKey,
  required Map<String, dynamic> offer,
  String? callId,
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
  final int Function() _nowMs;

  // Анти-спам/анти-дубликаты для call-offer: на некоторых сетях/устройствах возможны повторы.
  final Map<String, int> _lastCallOfferHandledAtMsBySender = {};
  static const int _callOfferDebounceMs = 2500;
  static const int _callOfferTtlMs = 60 * 1000;

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

      // 2) Если уже есть активный звонок/экран — не поднимаем второй входящий (иначе "пачка" экранов).
      if (_isCallActive()) {
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

      // Единый call_id для корреляции
      final callId = CallIdStorage.extractCallId(data, senderKey);

      // Дедуп по call_id (особенно важно при WS+FCM в фоне)
      final canShow = await CallIdStorage.trySetActiveCall(
        callId: callId,
        source: CallIdStorage.sourceWebSocket,
      );
      if (!canShow) {
        DebugLogger.info('CALL', '📞 call_id уже активен, пропускаю WS звонок',
            context: {'call_id': callId, 'peer_pubkey': senderKey});
        return;
      }

      // Сохраняем данные звонка в буфер (fallback для CallKit)
      _callBuffer.setLastIncomingCall(senderKey, data);
      
      // Если приложение в foreground — открываем CallScreen напрямую
      // Если в background — показываем нативный CallKit UI
      if (_isAppInForeground()) {
        DebugLogger.info('CALL', '📞 Foreground: открываю CallScreen напрямую',
            context: {'call_id': callId, 'peer_pubkey': senderKey});
        _openCallScreen(contactPublicKey: senderKey, offer: data, callId: callId);
      } else {
        DebugLogger.info('CALL', '📞 Background: показываю CallKit UI',
            context: {'call_id': callId, 'peer_pubkey': senderKey});
        // Доп. фолбек: локальное уведомление, если CallKit не покажется
        await _notif.showCallNotification(
          callerName: displayName,
          payload: json.encode({
            'type': 'incoming_call',
            'caller_key': senderKey,
            'caller_name': displayName,
            'offer_data': json.encode(data),
            'call_id': callId,
          }),
        );
        await _showCallKitIncoming(
          callerName: displayName,
          callerKey: senderKey,
          offerData: data,
        );
      }
      return;
    }

    if (type == 'ice-candidate') {
      // Всегда буферизуем (кандидаты могут прийти раньше offer).
      _callBuffer.add(senderKey, messageData);
      final callId = CallIdStorage.extractCallId(
          messageData['data'] is Map<String, dynamic>
              ? (messageData['data'] as Map<String, dynamic>)
              : messageData,
          senderKey);
      DebugLogger.info('CALL', '📥 ICE candidate', context: {
        'call_id': callId,
        'peer_pubkey': senderKey,
      });
      _emitSignaling(messageData);
      return;
    }

    if (type == 'call-answer') {
      final callId = CallIdStorage.extractCallId(
          messageData['data'] is Map<String, dynamic>
              ? (messageData['data'] as Map<String, dynamic>)
              : messageData,
          senderKey);
      DebugLogger.info('CALL', '📥 call-answer', context: {
        'call_id': callId,
        'peer_pubkey': senderKey,
      });
      _emitSignaling(messageData);
      return;
    }

    // ICE restart signals - пробрасываем в CallScreen для renegotiation
    if (type == 'ice-restart' || type == 'ice-restart-answer') {
      final callId = CallIdStorage.extractCallId(
          messageData['data'] is Map<String, dynamic>
              ? (messageData['data'] as Map<String, dynamic>)
              : messageData,
          senderKey);
      DebugLogger.info('CALL', '📥 ICE restart signal', context: {
        'call_id': callId,
        'peer_pubkey': senderKey,
        'type': type,
      });
      _emitSignaling(messageData);
      return;
    }

    if (type == 'hang-up' || type == 'call-rejected') {
      _callBuffer.clear(senderKey);
      _lastCallOfferHandledAtMsBySender.remove(senderKey);
      final callId = CallIdStorage.extractCallId(
          messageData['data'] is Map<String, dynamic>
              ? (messageData['data'] as Map<String, dynamic>)
              : messageData,
          senderKey);
      DebugLogger.info('CALL', '📥 $type', context: {
        'call_id': callId,
        'peer_pubkey': senderKey,
      });

      // КРИТИЧНО: сначала сообщаем в CallScreen, затем пытаемся спрятать уведомления.
      _emitSignaling(messageData);
      await _notif.hideCallNotification();
      
      // Скрываем нативный UI звонка (CallKit) если он был показан
      try {
        await FlutterCallkitIncoming.endAllCalls();
        DebugLogger.info('CALL', 'CallKit UI скрыт (hang-up/rejected)',
            context: {'call_id': callId, 'peer_pubkey': senderKey});
      } catch (e) {
        DebugLogger.warn('CALL', 'Ошибка скрытия CallKit: $e',
            context: {'call_id': callId, 'peer_pubkey': senderKey});
      }
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

  /// Показать нативный CallKit UI для входящего звонка
  /// 
  /// ВАЖНО: Когда приложение свёрнуто, Flutter engine может быть suspended.
  /// Для надёжной работы сервер также отправляет FCM push параллельно.
  Future<void> _showCallKitIncoming({
    required String callerName,
    required String callerKey,
    required Map<String, dynamic> offerData,
  }) async {
    // Используем call_id от сервера если есть, иначе генерируем
    // КРИТИЧНО: сервер передаёт уникальный call_id для каждого звонка!
    final callId = _extractOrGenerateCallId(offerData, callerKey);
    
    // Проверяем, нет ли уже активного звонка
    // ВАЖНО: FCM и WebSocket могут генерировать РАЗНЫЕ callId для одного звонка!
    // Поэтому проверяем по callerKey, а не по callId.
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls is List && activeCalls.isNotEmpty) {
        for (final call in activeCalls) {
          if (call is Map) {
            // Проверяем по callId
            if (call['id'] == callId) {
              DebugLogger.info('CALL', '📞 CallKit с id=$callId уже показан, пропускаю дубликат',
                  context: {'call_id': callId, 'peer_pubkey': callerKey});
              return;
            }
            // Проверяем по callerKey в extra — если тот же caller, значит дубль!
            final extra = call['extra'];
            if (extra is Map && extra['callerKey'] == callerKey) {
              DebugLogger.info('CALL', '📞 CallKit для $callerKey уже показан (FCM?), пропускаю WS дубликат',
                  context: {'call_id': callId, 'peer_pubkey': callerKey});
              return;
            }
          }
        }
        // Есть активный звонок от ДРУГОГО caller — закрываем и показываем новый
        DebugLogger.info('CALL', '📞 Закрываю старые CallKit звонки от другого caller, показываю новый (id=$callId)',
            context: {'call_id': callId, 'peer_pubkey': callerKey});
        await FlutterCallkitIncoming.endAllCalls();
      }
    } catch (e) {
      DebugLogger.warn('CALL', 'Ошибка проверки активных звонков: $e',
          context: {'call_id': callId, 'peer_pubkey': callerKey});
    }
    
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Orpheus',
      handle: callerKey.substring(0, 8), // Короткий ID для отображения
      type: 0, // Audio call
      duration: 45000, // 45 секунд рингтон (больше времени на ответ)
      textAccept: 'Ответить',
      textDecline: 'Отклонить',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Пропущенный звонок',
        callbackText: 'Перезвонить',
      ),
      extra: <String, dynamic>{
        'callerKey': callerKey,
        'offerData': json.encode(offerData),
        'callId': callId,
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0D0D0D',
        actionColor: '#6AD394',
        textColor: '#FFFFFF',
        isShowFullLockedScreen: true,
        // КРИТИЧНО для пробуждения устройства:
        isImportant: true,
        incomingCallNotificationChannelName: 'Входящие звонки',
        missedCallNotificationChannelName: 'Пропущенные звонки',
      ),
    );
    
    await FlutterCallkitIncoming.showCallkitIncoming(params);
    DebugLogger.info('CALL', '📱 CallKit UI показан для $callerName (id=$callId)');
  }
  
  /// Извлекает call_id из данных или генерирует стабильный callId.
  /// 
  /// ПРИОРИТЕТ:
  /// 1. call_id от сервера (уникальный для каждого звонка) — ЛУЧШИЙ вариант
  /// 2. Fallback: генерируем на основе callerKey + timestamp (15 сек окно)
  static String _extractOrGenerateCallId(Map<String, dynamic> data, String callerKey) {
    // 1. Пробуем получить call_id от сервера
    final serverCallId = data['call_id'] ?? data['callId'] ?? data['id'];
    if (serverCallId != null && 
        serverCallId.toString().isNotEmpty && 
        serverCallId.toString().toLowerCase() != 'null') {
      return serverCallId.toString();
    }
    
    // 2. Fallback: генерируем на основе callerKey
    final hash = callerKey.hashCode.abs();
    final timeWindow = DateTime.now().millisecondsSinceEpoch ~/ 15000; // 15 секунд
    return 'call-${hash.toRadixString(16).padLeft(8, '0')}-$timeWindow';
  }
}


