// lib/models/message_retention_policy.dart
// Message retention policy - auto-delete by time

/// Message auto-delete policy.
/// 
/// Defines how long messages are stored before automatic deletion.
/// Integrates with SecurityConfig and executes at app launch
/// and periodically during operation.
enum MessageRetentionPolicy {
  /// Keep all messages (no auto-delete)
  all,
  
  /// Keep messages for the last 24 hours
  day,
  
  /// Keep messages for the last 7 days
  week,
  
  /// Keep messages for the last 30 days
  month,
}

/// Расширение для MessageRetentionPolicy с утилитами
extension MessageRetentionPolicyExtension on MessageRetentionPolicy {
  /// Get Duration for cutoff time calculation
  Duration? get retentionDuration {
    switch (this) {
      case MessageRetentionPolicy.all:
        return null; // No limit
      case MessageRetentionPolicy.day:
        return const Duration(hours: 24);
      case MessageRetentionPolicy.week:
        return const Duration(days: 7);
      case MessageRetentionPolicy.month:
        return const Duration(days: 30);
    }
  }
  
  /// Calculate cutoff timestamp (messages older will be deleted)
  DateTime? getCutoffTime([DateTime? now]) {
    final duration = retentionDuration;
    if (duration == null) return null;
    return (now ?? DateTime.now()).subtract(duration);
  }
  
  /// Human-readable name for UI
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

  /// Short description for UI
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
  
  /// Index for saving to config (int)
  int get configValue => index;
  
  /// Restore from int
  static MessageRetentionPolicy fromConfigValue(int? value) {
    if (value == null || value < 0 || value >= MessageRetentionPolicy.values.length) {
      return MessageRetentionPolicy.all; // Default - keep all
    }
    return MessageRetentionPolicy.values[value];
  }
}
