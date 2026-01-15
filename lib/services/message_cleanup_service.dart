// lib/services/message_cleanup_service.dart
// Сервис автоматической очистки сообщений по политике retention

import 'dart:async';
import 'package:orpheus_project/models/message_retention_policy.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';

/// Сервис автоматической очистки сообщений.
/// 
/// Реализует гибридную стратегию очистки:
/// 1. При запуске приложения (после unlock)
/// 2. Периодически во время работы (по таймеру)
/// 3. При изменении политики retention
/// 
/// Оптимизации:
/// - Не чистит чаще чем раз в час (lastMessageCleanupAt)
/// - Асинхронная операция, не блокирует UI
/// - В duress mode очистка не выполняется
class MessageCleanupService {
  static final MessageCleanupService instance = MessageCleanupService._();
  
  MessageCleanupService._();
  
  /// Для тестов: создать экземпляр с кастомными зависимостями
  static MessageCleanupService createForTesting({
    required AuthService authService,
    required DatabaseService databaseService,
    DateTime Function()? now,
  }) {
    return MessageCleanupService._forTesting(
      authService: authService,
      databaseService: databaseService,
      now: now,
    );
  }
  
  MessageCleanupService._forTesting({
    required AuthService authService,
    required DatabaseService databaseService,
    DateTime Function()? now,
  })  : _authService = authService,
        _databaseService = databaseService,
        _now = now ?? DateTime.now;
  
  AuthService? _authService;
  DatabaseService? _databaseService;
  DateTime Function() _now = DateTime.now;
  
  AuthService get _auth => _authService ?? AuthService.instance;
  DatabaseService get _db => _databaseService ?? DatabaseService.instance;
  
  /// Таймер для периодической проверки
  Timer? _periodicTimer;
  
  /// Интервал периодической проверки (2 часа)
  static const _checkInterval = Duration(hours: 2);
  
  /// Флаг: идёт ли сейчас очистка
  bool _isRunning = false;
  
  /// Инициализация сервиса — вызывать после AuthService.init()
  Future<void> init() async {
    DebugLogger.info('CLEANUP', 'MessageCleanupService инициализирован');
    
    // Запустить первую проверку
    await performCleanupIfNeeded();
    
    // Запустить периодический таймер
    _startPeriodicTimer();
  }
  
  /// Остановить сервис (при выходе из приложения)
  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    DebugLogger.info('CLEANUP', 'MessageCleanupService остановлен');
  }
  
  /// Запустить периодический таймер
  void _startPeriodicTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_checkInterval, (_) {
      performCleanupIfNeeded();
    });
  }
  
  /// Выполнить очистку, если она необходима.
  /// 
  /// Проверяет shouldRunMessageCleanup и выполняет удаление.
  /// Безопасен для вызова из любого места — не блокирует UI.
  Future<CleanupResult> performCleanupIfNeeded() async {
    // Проверяем, нужна ли очистка
    if (!_auth.shouldRunMessageCleanup) {
      return CleanupResult.skipped(reason: 'Очистка не требуется');
    }
    
    // Предотвращаем параллельный запуск
    if (_isRunning) {
      return CleanupResult.skipped(reason: 'Очистка уже выполняется');
    }
    
    return await performCleanup();
  }
  
  /// Принудительно выполнить очистку (игнорирует интервал).
  /// 
  /// Используется при изменении политики retention.
  Future<CleanupResult> performCleanup() async {
    if (_isRunning) {
      return CleanupResult.skipped(reason: 'Очистка уже выполняется');
    }
    
    _isRunning = true;
    
    try {
      final policy = _auth.messageRetention;
      
      // Если политика "all" — нечего удалять
      if (policy == MessageRetentionPolicy.all) {
        await _auth.updateLastMessageCleanup(_now());
        return CleanupResult.skipped(reason: 'Политика: хранить всё');
      }
      
      // Вычисляем cutoff время
      final cutoff = policy.getCutoffTime(_now());
      if (cutoff == null) {
        return CleanupResult.skipped(reason: 'Не удалось вычислить cutoff');
      }
      
      DebugLogger.info('CLEANUP', 'Запуск очистки. Политика: ${policy.displayName}, cutoff: ${cutoff.toIso8601String()}');
      
      // Выполняем удаление
      final deletedCount = await _db.deleteMessagesOlderThan(cutoff);
      
      // Обновляем время последней очистки
      await _auth.updateLastMessageCleanup(_now());
      
      DebugLogger.info('CLEANUP', 'Очистка завершена. Удалено сообщений: $deletedCount');
      
      return CleanupResult.success(deletedCount: deletedCount);
    } catch (e) {
      DebugLogger.error('CLEANUP', 'Ошибка очистки: $e');
      return CleanupResult.error(message: e.toString());
    } finally {
      _isRunning = false;
    }
  }
  
  /// Получить preview: сколько сообщений будет удалено при данной политике.
  /// 
  /// Используется в UI для предупреждения пользователя.
  Future<int> getCleanupPreview(MessageRetentionPolicy policy) async {
    if (policy == MessageRetentionPolicy.all) {
      return 0;
    }
    
    final cutoff = policy.getCutoffTime(_now());
    if (cutoff == null) return 0;
    
    return await _db.countMessagesOlderThan(cutoff);
  }
  
  /// Вызывается при возвращении приложения в foreground.
  /// 
  /// Триггерит проверку очистки если прошло достаточно времени.
  Future<void> onAppResumed() async {
    await performCleanupIfNeeded();
  }
  
  /// Вызывается при изменении политики retention.
  /// 
  /// Немедленно выполняет очистку по новой политике.
  Future<CleanupResult> onRetentionPolicyChanged(MessageRetentionPolicy newPolicy) async {
    DebugLogger.info('CLEANUP', 'Политика retention изменена на: ${newPolicy.displayName}');
    return await performCleanup();
  }
}

/// Результат операции очистки
class CleanupResult {
  final CleanupStatus status;
  final int deletedCount;
  final String? message;
  
  const CleanupResult._({
    required this.status,
    this.deletedCount = 0,
    this.message,
  });
  
  factory CleanupResult.success({required int deletedCount}) {
    return CleanupResult._(
      status: CleanupStatus.success,
      deletedCount: deletedCount,
    );
  }
  
  factory CleanupResult.skipped({required String reason}) {
    return CleanupResult._(
      status: CleanupStatus.skipped,
      message: reason,
    );
  }
  
  factory CleanupResult.error({required String message}) {
    return CleanupResult._(
      status: CleanupStatus.error,
      message: message,
    );
  }
  
  bool get isSuccess => status == CleanupStatus.success;
  
  @override
  String toString() {
    switch (status) {
      case CleanupStatus.success:
        return 'CleanupResult.success(deleted: $deletedCount)';
      case CleanupStatus.skipped:
        return 'CleanupResult.skipped($message)';
      case CleanupStatus.error:
        return 'CleanupResult.error($message)';
    }
  }
}

enum CleanupStatus { success, skipped, error }
