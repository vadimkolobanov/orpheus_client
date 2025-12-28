import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/chat_time_rules.dart';

void main() {
  group('ChatTimeRules (контракты форматирования чата)', () {
    test('isSameMinute: true только если совпадает до минуты', () {
      final a = DateTime(2025, 12, 27, 10, 5, 1);
      final b = DateTime(2025, 12, 27, 10, 5, 59);
      final c = DateTime(2025, 12, 27, 10, 6, 0);
      expect(ChatTimeRules.isSameMinute(a, b), isTrue);
      expect(ChatTimeRules.isSameMinute(a, c), isFalse);
    });

    test('isNewDay: true для первого сообщения и при смене даты', () {
      final a = DateTime(2025, 12, 27, 10, 0);
      final b = DateTime(2025, 12, 27, 23, 59);
      final c = DateTime(2025, 12, 28, 0, 0);
      expect(ChatTimeRules.isNewDay(a, null), isTrue);
      expect(ChatTimeRules.isNewDay(b, a), isFalse);
      expect(ChatTimeRules.isNewDay(c, b), isTrue);
    });

    test('formatMessageTime: Сегодня/Вчера + HH:mm', () {
      final now = DateTime(2025, 12, 27, 12, 0);
      final todayMsg = DateTime(2025, 12, 27, 9, 15);
      final yMsg = DateTime(2025, 12, 26, 22, 40);

      final t = ChatTimeRules.formatMessageTime(todayMsg, now: now);
      expect(t, contains('Сегодня'));
      expect(t, contains(', 09:15'));

      final y = ChatTimeRules.formatMessageTime(yMsg, now: now);
      expect(y, contains('Вчера'));
      expect(y, contains(', 22:40'));
    });

    test('formatMessageTime: timeOnly=true возвращает только HH:mm', () {
      final now = DateTime(2025, 12, 27, 12, 0);
      final msg = DateTime(2025, 12, 26, 22, 40);
      expect(ChatTimeRules.formatMessageTime(msg, now: now, timeOnly: true), equals('22:40'));
    });

    test('formatMessageTime: если сообщения в одну минуту, время скрывается (пустая строка)', () {
      final now = DateTime(2025, 12, 27, 12, 0);
      final prev = DateTime(2025, 12, 27, 9, 15, 10);
      final curr = DateTime(2025, 12, 27, 9, 15, 50);
      expect(
        ChatTimeRules.formatMessageTime(curr, now: now, previousTimestamp: prev, timeOnly: false),
        equals(''),
      );
      // но для timeOnly скрывать нельзя
      expect(
        ChatTimeRules.formatMessageTime(curr, now: now, previousTimestamp: prev, timeOnly: true),
        equals('09:15'),
      );
    });

    test('formatDaySeparator: Сегодня/Вчера', () {
      final now = DateTime(2025, 12, 27, 12, 0);
      expect(ChatTimeRules.formatDaySeparator(DateTime(2025, 12, 27, 1, 0), now: now), equals('Сегодня'));
      expect(ChatTimeRules.formatDaySeparator(DateTime(2025, 12, 26, 23, 0), now: now), equals('Вчера'));
    });
  });
}




