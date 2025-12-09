// lib/services/debug_logger_service.dart

import 'dart:async';

/// Глобальный сервис логирования для отладки на реальных устройствах
/// 
/// Использование:
/// ```dart
/// DebugLogger.log('WS', 'Подключение к серверу');
/// DebugLogger.log('CALL', 'Входящий звонок от ${contactName}');
/// ```
class DebugLogger {
  // Singleton
  static final DebugLogger _instance = DebugLogger._internal();
  factory DebugLogger() => _instance;
  DebugLogger._internal();

  // Максимальное количество хранимых логов
  static const int _maxLogs = 1000;

  // Хранилище логов
  static final List<LogEntry> _logs = [];

  // Stream для уведомления UI об обновлениях
  static final StreamController<void> _updateController = StreamController.broadcast();
  static Stream<void> get onUpdate => _updateController.stream;

  /// Добавить лог
  static void log(String tag, String message, {LogLevel level = LogLevel.info}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
      level: level,
    );
    
    _logs.add(entry);
    
    // Ограничиваем размер
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
    
    // Уведомляем UI
    _updateController.add(null);
    
    // Также выводим в консоль для ADB logcat
    print('[${entry.levelIcon}] [${entry.tag}] ${entry.message}');
  }

  /// Информационный лог
  static void info(String tag, String message) {
    log(tag, message, level: LogLevel.info);
  }

  /// Предупреждение
  static void warn(String tag, String message) {
    log(tag, message, level: LogLevel.warning);
  }

  /// Ошибка
  static void error(String tag, String message) {
    log(tag, message, level: LogLevel.error);
  }

  /// Успех
  static void success(String tag, String message) {
    log(tag, message, level: LogLevel.success);
  }

  /// Получить все логи
  static List<LogEntry> get logs => List.unmodifiable(_logs);

  /// Получить логи по тегу
  static List<LogEntry> getLogsByTag(String tag) {
    return _logs.where((e) => e.tag == tag).toList();
  }

  /// Очистить все логи
  static void clear() {
    _logs.clear();
    _updateController.add(null);
  }

  /// Экспорт логов в текст
  static String exportToText() {
    final buffer = StringBuffer();
    buffer.writeln('=== ORPHEUS DEBUG LOGS ===');
    buffer.writeln('Экспорт: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Всего записей: ${_logs.length}');
    buffer.writeln('');
    
    for (final entry in _logs) {
      buffer.writeln(entry.toFormattedString());
    }
    
    return buffer.toString();
  }
}

/// Уровни логирования
enum LogLevel {
  info,
  warning,
  error,
  success,
}

/// Запись лога
class LogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;
  final LogLevel level;

  LogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    required this.level,
  });

  String get levelIcon {
    switch (level) {
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
      case LogLevel.success:
        return '✅';
    }
  }

  String get timeString {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}.'
           '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  String toFormattedString() {
    return '[$timeString] [$levelIcon $tag] $message';
  }
}

