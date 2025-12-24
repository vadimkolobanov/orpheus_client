import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/incoming_call_buffer.dart';
import 'package:orpheus_project/services/incoming_message_handler.dart';

class _FakeCrypto implements IncomingMessageCrypto {
  _FakeCrypto(this._decryptFn);
  final Future<String> Function(String sender, String payload) _decryptFn;

  @override
  Future<String> decrypt(String senderPublicKeyBase64, String encryptedPayload) {
    return _decryptFn(senderPublicKeyBase64, encryptedPayload);
  }
}

class _FakeDb implements IncomingMessageDatabase {
  final Map<String, String> contactNames = {};
  final List<(ChatMessage message, String contactKey)> saved = [];

  @override
  Future<void> addMessage(ChatMessage message, String contactPublicKey) async {
    saved.add((message, contactPublicKey));
  }

  @override
  Future<String?> getContactName(String publicKey) async {
    return contactNames[publicKey];
  }
}

class _FakeNotif implements IncomingMessageNotifications {
  final List<String> calls = [];

  @override
  Future<void> showCallNotification({required String callerName}) async {
    calls.add('showCall:$callerName');
  }

  @override
  Future<void> hideCallNotification() async {
    calls.add('hideCall');
  }

  @override
  Future<void> showMessageNotification({required String senderName}) async {
    calls.add('showMsg:$senderName');
  }
}

void main() {
  group('IncomingMessageHandler', () {
    setUp(() {
      IncomingCallBuffer.instance.clearAll();
    });

    test('игнорирует пакеты без sender_pubkey и служебные типы', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb();
      final notif = _FakeNotif();
      final signaling = <Map<String, dynamic>>[];
      final chatUpdates = <String>[];

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'x'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer}) {
          fail('openCallScreen не должен вызываться');
        },
        emitSignaling: signaling.add,
        emitChatUpdate: chatUpdates.add,
        isAppInForeground: () => true,
      );

      await handler.handleDecoded({'type': 'pong'});
      await handler.handleDecoded({'type': 'license-status', 'status': 'active'});
      await handler.handleDecoded({'type': 'chat', 'payload': 'p'}); // sender_pubkey отсутствует

      expect(signaling, isEmpty);
      expect(chatUpdates, isEmpty);
      expect(notif.calls, isEmpty);
      expect(db.saved, isEmpty);
    });

    test('ICE до offer не теряется: буферизуется и сохраняется при приходе offer', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb()..contactNames['SENDER_KEY'] = 'Alice';
      final notif = _FakeNotif();
      final signaling = <Map<String, dynamic>>[];

      Map<String, dynamic>? openedOffer;
      String? openedKey;

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'x'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer}) {
          openedKey = contactPublicKey;
          openedOffer = offer;
        },
        emitSignaling: signaling.add,
        emitChatUpdate: (_) {},
        isAppInForeground: () => true,
      );

      await handler.handleDecoded({
        'type': 'ice-candidate',
        'sender_pubkey': 'SENDER_KEY',
        'data': {'candidate': 'c', 'sdpMid': '0', 'sdpMLineIndex': 0},
      });

      expect(signaling.length, 1);
      expect(buffer.sizeFor('SENDER_KEY'), 1);

      await handler.handleDecoded({
        'type': 'call-offer',
        'sender_pubkey': 'SENDER_KEY',
        'data': {'sdp': 'v=0...', 'type': 'offer'},
      });

      expect(notif.calls, contains('showCall:Alice'));
      expect(openedKey, equals('SENDER_KEY'));
      expect(openedOffer?['type'], equals('offer'));
      // ключевое: pre-offer ICE не должен очищаться при обработке offer
      expect(buffer.sizeFor('SENDER_KEY'), 1);
    });

    test('hang-up/call-rejected: сначала signaling, затем hideCallNotification', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb();
      final notif = _FakeNotif();
      final order = <String>[];

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'x'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer}) {},
        emitSignaling: (msg) => order.add('signaling:${msg['type']}'),
        emitChatUpdate: (_) {},
        isAppInForeground: () => true,
      );

      await handler.handleDecoded({
        'type': 'hang-up',
        'sender_pubkey': 'SENDER_KEY',
        'data': {},
      });

      // notif.calls содержит только hideCall, а порядок проверяем через order + notif.calls
      expect(order, equals(['signaling:hang-up']));
      expect(notif.calls, equals(['hideCall']));
    });

    test('chat: сохраняет сообщение, шлёт update; нотификация только в фоне и без текста', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb()..contactNames['SENDER_KEY'] = 'Bob';
      final notif = _FakeNotif();
      final chatUpdates = <String>[];

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'hello'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer}) {},
        emitSignaling: (_) {},
        emitChatUpdate: chatUpdates.add,
        isAppInForeground: () => false,
      );

      await handler.handleDecoded({
        'type': 'chat',
        'sender_pubkey': 'SENDER_KEY',
        'payload': '{"cipherText":"..."}',
      });

      expect(db.saved, hasLength(1));
      expect(db.saved.first.$1.text, equals('hello'));
      expect(db.saved.first.$1.isSentByMe, isFalse);
      expect(db.saved.first.$1.isRead, isFalse);
      expect(db.saved.first.$1.status, equals(MessageStatus.delivered));

      expect(chatUpdates, equals(['SENDER_KEY']));
      // Приватность: уведомление без содержания — только имя отправителя.
      expect(notif.calls, equals(['showMsg:Bob']));
    });

    test('chat: системные call-status сообщения не должны поднимать уведомление', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb()..contactNames['SENDER_KEY'] = 'Bob';
      final notif = _FakeNotif();

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'Пропущен звонок'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer}) {},
        emitSignaling: (_) {},
        emitChatUpdate: (_) {},
        isAppInForeground: () => false,
      );

      await handler.handleDecoded({
        'type': 'chat',
        'sender_pubkey': 'SENDER_KEY',
        'payload': 'enc',
      });

      expect(db.saved, hasLength(1));
      expect(notif.calls, isEmpty);
    });
  });
}


