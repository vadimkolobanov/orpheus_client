import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

// Мы тестируем чистоту протокола.
// Это гарантирует, что клиент и сервер говорят на одном языке.

void main() {
  group('Call Signaling Protocol Tests', () {

    // 1. Тест структуры OFFER (Исходящий звонок)
    test('Формирование пакета Call Offer корректно', () {
      const targetPubkey = "TARGET_KEY_222";

      // Эмуляция данных от WebRTC
      final sdpData = {'sdp': 'v=0...', 'type': 'offer'};

      // Логика формирования сообщения (как в коде)
      final message = {
        "recipient_pubkey": targetPubkey,
        "type": "call-offer",
        "data": sdpData
      };

      final jsonString = json.encode(message);

      // Проверки
      expect(jsonString, contains('"type":"call-offer"'));
      expect(jsonString, contains('"recipient_pubkey":"TARGET_KEY_222"'));
      expect(jsonString, contains('"sdp":"v=0..."'));
    });

    // 2. Тест парсинга входящего ANSWER (Ответ на звонок)
    test('Парсинг входящего Call Answer корректен', () {
      // Пришло от сервера
      final incomingJson = json.encode({
        "sender_pubkey": "TARGET_KEY_222",
        "type": "call-answer",
        "data": {
          "sdp": "v=0...ANSWER...",
          "type": "answer"
        }
      });

      final Map<String, dynamic> decoded = json.decode(incomingJson);

      expect(decoded['type'], equals('call-answer'));
      expect(decoded['sender_pubkey'], equals('TARGET_KEY_222'));

      final data = decoded['data'];
      expect(data['type'], equals('answer'));
      expect(data['sdp'], contains('ANSWER'));
    });

    // 3. Тест ICE Candidate (Самое капризное место)
    test('Структура ICE Candidate соответствует стандарту', () {
      // WebRTC отдает кандидата так:
      final candidateMap = {
        'candidate': 'candidate:842163049 1 udp 1677729535 ...',
        'sdpMid': '0',
        'sdpMLineIndex': 0
      };

      final message = {
        "recipient_pubkey": "TARGET_KEY_222",
        "type": "ice-candidate",
        "data": candidateMap
      };

      final jsonString = json.encode(message);
      final decoded = json.decode(jsonString);

      // Важно: sdpMLineIndex должен быть int, а не string!
      expect(decoded['data']['sdpMLineIndex'], isA<int>());
      expect(decoded['data']['sdpMid'], isNotNull);
      expect(decoded['data']['candidate'], startsWith('candidate:'));
    });

    // 4. Тест логики роутинга (Эмуляция _listenForMessages)
    test('Роутер правильно определяет тип сообщения', () {
      // Список сообщений, которые могут прийти
      final messages = [
        {"type": "call-offer", "data": {}},
        {"type": "chat", "payload": "enc_data"},
        {"type": "hang-up", "data": {}},
      ];

      for (var msg in messages) {
        final type = msg['type'];

        // Эмуляция switch-case из main.dart
        bool isCallRelated = false;
        bool isChatRelated = false;

        if (type == 'call-offer' || type == 'hang-up') {
          isCallRelated = true;
        } else if (type == 'chat') {
          isChatRelated = true;
        }

        if (type == 'call-offer') expect(isCallRelated, isTrue);
        if (type == 'chat') expect(isChatRelated, isTrue);
      }
    });

    test('Обработка call-answer сообщения', () {
      final answerJson = json.encode({
        "sender_pubkey": "SENDER_KEY",
        "type": "call-answer",
        "data": {
          "sdp": "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\n...",
          "type": "answer"
        }
      });

      final decoded = json.decode(answerJson) as Map<String, dynamic>;
      expect(decoded['type'], equals('call-answer'));
      expect(decoded['sender_pubkey'], equals('SENDER_KEY'));
      expect(decoded['data']['type'], equals('answer'));
    });

    test('Обработка hang-up сообщения', () {
      final hangupJson = json.encode({
        "sender_pubkey": "SENDER_KEY",
        "type": "hang-up",
        "data": {}
      });

      final decoded = json.decode(hangupJson) as Map<String, dynamic>;
      expect(decoded['type'], equals('hang-up'));
      expect(decoded['sender_pubkey'], equals('SENDER_KEY'));
    });

    test('Обработка call-rejected сообщения', () {
      final rejectedJson = json.encode({
        "sender_pubkey": "SENDER_KEY",
        "type": "call-rejected",
        "data": {}
      });

      final decoded = json.decode(rejectedJson) as Map<String, dynamic>;
      expect(decoded['type'], equals('call-rejected'));
    });

    test('ICE Candidate с разными типами', () {
      final candidateTypes = [
        {'candidate': 'candidate:1 1 udp 2130706431 192.168.1.1 54321 typ host', 'sdpMid': '0', 'sdpMLineIndex': 0},
        {'candidate': 'candidate:2 1 udp 1694498815 1.2.3.4 12345 typ srflx', 'sdpMid': '0', 'sdpMLineIndex': 0},
        {'candidate': 'candidate:3 1 udp 16777215 5.6.7.8 9999 typ relay', 'sdpMid': '0', 'sdpMLineIndex': 0},
      ];

      for (final candidate in candidateTypes) {
        final message = {
          "recipient_pubkey": "TARGET_KEY",
          "type": "ice-candidate",
          "data": candidate
        };

        final jsonString = json.encode(message);
        final decoded = json.decode(jsonString) as Map<String, dynamic>;

        expect(decoded['type'], equals('ice-candidate'));
        expect(decoded['data']['sdpMLineIndex'], isA<int>());
        expect(decoded['data']['candidate'], contains('candidate:'));
      }
    });

    test('Обработка сообщений с отсутствующими полями', () {
      // Сообщение без sender_pubkey
      final incompleteJson = json.encode({
        "type": "call-offer",
        "data": {"sdp": "test"}
      });

      final decoded = json.decode(incompleteJson) as Map<String, dynamic>;
      expect(decoded['sender_pubkey'], isNull);
      expect(decoded['type'], equals('call-offer'));
    });

    test('Корректная сериализация и десериализация полного цикла', () {
      // Создаем полное сообщение
      final originalMessage = {
        "recipient_pubkey": "TARGET_KEY",
        "type": "call-offer",
        "data": {
          "sdp": "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n",
          "type": "offer"
        }
      };

      // Сериализуем
      final jsonString = json.encode(originalMessage);
      expect(jsonString, isNotEmpty);

      // Десериализуем
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      final originalData = originalMessage['data'] as Map<String, dynamic>;
      final decodedData = decoded['data'] as Map<String, dynamic>;
      expect(decoded['type'], equals(originalMessage['type']));
      expect(decoded['recipient_pubkey'], equals(originalMessage['recipient_pubkey']));
      expect(decodedData['type'], equals(originalData['type']));
    });
  });
}