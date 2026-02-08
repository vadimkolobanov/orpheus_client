import 'package:intl/intl.dart';

/// Чистые правила форматирования времени/даты сообщений в чате.
///
/// Контракт:
/// - `Сегодня` / `Вчера` для соответствующих дат относительно `now`.
/// - Для текущего года: `d MMMM`, для других лет: `d MMMM yyyy` (locale `ru`).
/// - Если два сообщения в одну минуту и `timeOnly=false`, время скрывается (возвращается пустая строка).
/// - Для звонков/особых случаев можно запросить только время (`timeOnly=true`).
class ChatTimeRules {
  static bool isSameMinute(DateTime d1, DateTime d2) {
    return d1.year == d2.year &&
        d1.month == d2.month &&
        d1.day == d2.day &&
        d1.hour == d2.hour &&
        d1.minute == d2.minute;
  }

  static bool isNewDay(DateTime current, DateTime? previous) {
    if (previous == null) return true;
    final currentDate = DateTime(current.year, current.month, current.day);
    final previousDate = DateTime(previous.year, previous.month, previous.day);
    return currentDate != previousDate;
  }

  static String formatDaySeparator(DateTime timestamp, {required DateTime now}) {
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) return 'Today';
    if (messageDate == yesterday) return 'Yesterday';

    if (messageDate.year == now.year) {
      return DateFormat('d MMMM', 'en').format(timestamp);
    }
    return DateFormat('d MMMM yyyy', 'en').format(timestamp);
  }

  static String formatMessageTime(
    DateTime timestamp, {
    required DateTime now,
    DateTime? previousTimestamp,
    bool timeOnly = false,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    final showTime = previousTimestamp == null || !isSameMinute(timestamp, previousTimestamp);
    if (!showTime && !timeOnly) return '';

    final timeStr = DateFormat('HH:mm').format(timestamp);
    if (timeOnly) return timeStr;

    String dateStr;
    if (messageDate == today) {
      dateStr = 'Today';
    } else if (messageDate == yesterday) {
      dateStr = 'Yesterday';
    } else if (messageDate.year == now.year) {
      dateStr = DateFormat('d MMMM', 'en').format(timestamp);
    } else {
      dateStr = DateFormat('d MMMM yyyy', 'en').format(timestamp);
    }

    return '$dateStr, $timeStr';
  }
}






