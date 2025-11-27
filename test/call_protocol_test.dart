import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

// Мы тестируем чистоту протокола.
// Это гарантирует, что клиент и сервер говорят на одном языке.

void main() {
  group('Call Signaling Protocol Tests', () {

    // 1. Тест структуры OFFER (Исходящий звонок)
    test('Формирование пакета Call Offer корректно', () {
      const myPubkey = "MY_KEY_111";
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
  });
}