import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/models/chat_message_model.dart';

void main() {
  group('ChatMessage Model Tests', () {
    test('Создание сообщения с дефолтными значениями', () {
      final message = ChatMessage(
        text: 'Тестовое сообщение',
        isSentByMe: true,
      );

      expect(message.text, equals('Тестовое сообщение'));
      expect(message.isSentByMe, isTrue);
      expect(message.status, equals(MessageStatus.sent));
      expect(message.isRead, isTrue);
      expect(message.timestamp, isA<DateTime>());
    });

    test('Создание сообщения с кастомным timestamp', () {
      final customTime = DateTime(2025, 1, 1, 12, 0);
      final message = ChatMessage(
        text: 'Сообщение',
        isSentByMe: false,
        timestamp: customTime,
      );

      expect(message.timestamp, equals(customTime));
    });

    test('Создание входящего непрочитанного сообщения', () {
      final message = ChatMessage(
        text: 'Новое сообщение',
        isSentByMe: false,
        status: MessageStatus.delivered,
        isRead: false,
      );

      expect(message.isSentByMe, isFalse);
      expect(message.status, equals(MessageStatus.delivered));
      expect(message.isRead, isFalse);
    });

    test('Конвертация в Map для БД', () {
      final message = ChatMessage(
        id: 1,
        text: 'Тест',
        isSentByMe: true,
        timestamp: DateTime(2025, 1, 1, 12, 0),
        status: MessageStatus.sent,
        isRead: true,
      );

      final map = message.toMap('CONTACT_KEY_123');

      expect(map['contactPublicKey'], equals('CONTACT_KEY_123'));
      expect(map['text'], equals('Тест'));
      expect(map['isSentByMe'], equals(1));
      expect(map['isRead'], equals(1));
      expect(map['status'], equals(MessageStatus.sent.index));
      expect(map['timestamp'], equals(DateTime(2025, 1, 1, 12, 0).millisecondsSinceEpoch));
    });

    test('Все статусы сообщений корректно конвертируются', () {
      for (final status in MessageStatus.values) {
        final message = ChatMessage(
          text: 'Тест',
          isSentByMe: true,
          status: status,
        );

        final map = message.toMap('KEY');
        expect(map['status'], equals(status.index));
      }
    });

    test('Пустое сообщение создается корректно', () {
      final message = ChatMessage(
        text: '',
        isSentByMe: true,
      );

      expect(message.text, isEmpty);
      expect(message.toMap('KEY')['text'], isEmpty);
    });

    test('Длинное сообщение обрабатывается корректно', () {
      final longText = 'A' * 10000;
      final message = ChatMessage(
        text: longText,
        isSentByMe: true,
      );

      expect(message.text.length, equals(10000));
      expect(message.toMap('KEY')['text'], equals(longText));
    });
  });
}







