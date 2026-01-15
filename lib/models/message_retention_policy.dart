// lib/models/message_retention_policy.dart
// Политика хранения сообщений — автоудаление по времени

/// Политика автоматического удаления сообщений.
/// 
/// Определяет, сколько времени хранятся сообщения перед автоматическим удалением.
/// Интегрируется с SecurityConfig и выполняется при запуске приложения
/// и периодически во время работы.
enum MessageRetentionPolicy {
  /// Хранить все сообщения (без автоудаления)
  all,
  
  /// Хранить сообщения за последние 24 часа
  day,
  
  /// Хранить сообщения за последние 7 дней
  week,
  
  /// Хранить сообщения за последние 30 дней
  month,
}

/// Расширение для MessageRetentionPolicy с утилитами
extension MessageRetentionPolicyExtension on MessageRetentionPolicy {
  /// Получить Duration для расчёта cutoff времени
  Duration? get retentionDuration {
    switch (this) {
      case MessageRetentionPolicy.all:
        return null; // Без ограничений
      case MessageRetentionPolicy.day:
        return const Duration(hours: 24);
      case MessageRetentionPolicy.week:
        return const Duration(days: 7);
      case MessageRetentionPolicy.month:
        return const Duration(days: 30);
    }
  }
  
  /// Рассчитать cutoff timestamp (сообщения старше будут удалены)
  DateTime? getCutoffTime([DateTime? now]) {
    final duration = retentionDuration;
    if (duration == null) return null;
    return (now ?? DateTime.now()).subtract(duration);
  }
  
  /// Человекочитаемое название для UI
  String get displayName {
    switch (this) {
      case MessageRetentionPolicy.all:
        return 'Хранить всегда';
      case MessageRetentionPolicy.day:
        return 'Хранить 24 часа';
      case MessageRetentionPolicy.week:
        return 'Хранить 7 дней';
      case MessageRetentionPolicy.month:
        return 'Хранить 30 дней';
    }
  }
  
  /// Краткое описание для UI
  String get subtitle {
    switch (this) {
      case MessageRetentionPolicy.all:
        return 'Сообщения не удаляются автоматически';
      case MessageRetentionPolicy.day:
        return 'Сообщения старше суток удаляются';
      case MessageRetentionPolicy.week:
        return 'Сообщения старше недели удаляются';
      case MessageRetentionPolicy.month:
        return 'Сообщения старше месяца удаляются';
    }
  }
  
  /// Индекс для сохранения в конфиг (int)
  int get configValue => index;
  
  /// Восстановление из int
  static MessageRetentionPolicy fromConfigValue(int? value) {
    if (value == null || value < 0 || value >= MessageRetentionPolicy.values.length) {
      return MessageRetentionPolicy.all; // По умолчанию — хранить всё
    }
    return MessageRetentionPolicy.values[value];
  }
}
