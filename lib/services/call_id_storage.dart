// lib/services/call_id_storage.dart
//
// Синхронизация callId между FCM background isolate и main isolate.
// 
// АРХИТЕКТУРА:
// - FCM background handler работает в ОТДЕЛЬНОМ isolate
// - Он не имеет доступа к CallManager.instance из main isolate
// - SharedPreferences — единственный способ синхронизации
//
// ЛОГИКА ДЕДУПЛИКАЦИИ:
// 1. При получении звонка (FCM или WS) — сохраняем callId + timestamp
// 2. Перед показом CallKit — проверяем, не показан ли уже этот callId
// 3. Если показан И не истёк — пропускаем (дубль)
// 4. После завершения звонка — очищаем

import 'package:shared_preferences/shared_preferences.dart';

/// Хранилище для синхронизации callId между isolates.
/// Работает через SharedPreferences (единственный способ IPC в Flutter).
class CallIdStorage {
  static const String _keyActiveCallId = 'orpheus_active_call_id';
  static const String _keyActiveCallTimestamp = 'orpheus_active_call_ts';
  static const String _keyActiveCallSource = 'orpheus_active_call_source';
  
  /// Время жизни записи (15 секунд) — достаточно для синхронизации FCM/WS,
  /// но не блокирует перезвон после завершения звонка
  static const int _ttlMs = 15 * 1000;
  
  /// Маркеры источника
  static const String sourceWebSocket = 'ws';
  static const String sourceFcm = 'fcm';
  
  /// Попытаться зарегистрировать callId как "активный".
  /// 
  /// Возвращает:
  /// - `true` если callId успешно сохранён (новый звонок или устаревший сброшен)
  /// - `false` если уже есть активный callId (любой, включая тот же)
  /// 
  /// ВАЖНО: Для WebSocket используем этот метод для регистрации.
  /// Для FCM используем tryShowCallKitForFcm — он имеет другую логику.
  static Future<bool> trySetActiveCall({
    required String callId,
    required String source,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Проверяем, есть ли уже активный callId
      final existingCallId = prefs.getString(_keyActiveCallId);
      final existingTs = prefs.getInt(_keyActiveCallTimestamp) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Если есть активный callId и он не устарел
      if (existingCallId != null && existingCallId.isNotEmpty) {
        final age = now - existingTs;
        if (age < _ttlMs) {
          // Тот же callId? → WS хочет обработать звонок который уже зарегистрирован
          // Это нормально — WS может обрабатывать звонок повторно
          if (existingCallId == callId) {
            print("📞 CallIdStorage: callId=$callId уже активен, source=$source (обновляю timestamp)");
            await prefs.setInt(_keyActiveCallTimestamp, now);
            await prefs.setString(_keyActiveCallSource, source);
            return true;
          }
          // Другой callId, но предыдущий ещё активен? → занято
          print("📞 CallIdStorage: уже есть активный звонок $existingCallId, отклоняю новый $callId");
          return false;
        }
        // Устарел — очищаем и продолжаем
        print("📞 CallIdStorage: предыдущий callId устарел (${age}ms), очищаю");
      }
      
      // Сохраняем новый callId
      await prefs.setString(_keyActiveCallId, callId);
      await prefs.setInt(_keyActiveCallTimestamp, now);
      await prefs.setString(_keyActiveCallSource, source);
      
      print("📞 CallIdStorage: сохранён callId=$callId, source=$source");
      return true;
    } catch (e) {
      print("📞 CallIdStorage ERROR: $e");
      // При ошибке разрешаем показать (лучше показать дубль, чем пропустить звонок)
      return true;
    }
  }
  
  /// Проверить, можно ли FCM показать CallKit для этого callId.
  /// 
  /// Возвращает:
  /// - `true` если callId ещё НЕ обрабатывается (можно показать CallKit)
  /// - `false` если callId УЖЕ активен (кто-то уже показал CallKit)
  /// 
  /// В отличие от trySetActiveCall, этот метод НЕ регистрирует callId если он уже есть.
  static Future<bool> tryShowCallKitForFcm({
    required String callId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final existingCallId = prefs.getString(_keyActiveCallId);
      final existingTs = prefs.getInt(_keyActiveCallTimestamp) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Если есть активный callId и он не устарел
      if (existingCallId != null && existingCallId.isNotEmpty) {
        final age = now - existingTs;
        if (age < _ttlMs) {
          // Кто-то уже обрабатывает звонок (неважно какой callId)
          print("📞 CallIdStorage FCM: уже есть активный звонок $existingCallId (age=${age}ms), FCM НЕ показываю");
          return false;
        }
        // Устарел — можно показывать
        print("📞 CallIdStorage FCM: предыдущий callId устарел (${age}ms)");
      }
      
      // Регистрируем callId для FCM
      await prefs.setString(_keyActiveCallId, callId);
      await prefs.setInt(_keyActiveCallTimestamp, now);
      await prefs.setString(_keyActiveCallSource, sourceFcm);
      
      print("📞 CallIdStorage FCM: сохранён callId=$callId");
      return true;
    } catch (e) {
      print("📞 CallIdStorage FCM ERROR: $e");
      // При ошибке разрешаем показать
      return true;
    }
  }
  
  /// Проверить, является ли callId дублем (уже обрабатывается).
  static Future<bool> isDuplicate(String callId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final existingCallId = prefs.getString(_keyActiveCallId);
      final existingTs = prefs.getInt(_keyActiveCallTimestamp) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      if (existingCallId == null || existingCallId.isEmpty) {
        return false;
      }
      
      // Устарел?
      if ((now - existingTs) >= _ttlMs) {
        return false;
      }
      
      return existingCallId == callId;
    } catch (e) {
      print("📞 CallIdStorage.isDuplicate ERROR: $e");
      return false;
    }
  }
  
  /// Получить текущий активный callId (если есть и не устарел).
  static Future<String?> getActiveCallId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final callId = prefs.getString(_keyActiveCallId);
      final ts = prefs.getInt(_keyActiveCallTimestamp) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      if (callId == null || callId.isEmpty) {
        return null;
      }
      
      // Устарел?
      if ((now - ts) >= _ttlMs) {
        return null;
      }
      
      return callId;
    } catch (e) {
      print("📞 CallIdStorage.getActiveCallId ERROR: $e");
      return null;
    }
  }
  
  /// Очистить активный callId (звонок завершён).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyActiveCallId);
      await prefs.remove(_keyActiveCallTimestamp);
      await prefs.remove(_keyActiveCallSource);
      print("📞 CallIdStorage: очищено");
    } catch (e) {
      print("📞 CallIdStorage.clear ERROR: $e");
    }
  }
  
  /// Генерирует стабильный fallback callId.
  /// 
  /// КРИТИЧНО: Использует 30-секундное окно для надёжной синхронизации
  /// между FCM (который приходит с задержкой) и WebSocket.
  /// 
  /// Формат: `call-{callerKeyHash}-{timeWindow}`
  static String generateFallbackCallId(String callerKey) {
    final hash = callerKey.hashCode.abs();
    // 30-секундное окно — достаточно для синхронизации FCM и WS
    final timeWindow = DateTime.now().millisecondsSinceEpoch ~/ 30000;
    return 'call-${hash.toRadixString(16).padLeft(8, '0')}-$timeWindow';
  }
  
  /// Извлекает call_id из данных сообщения.
  /// Возвращает call_id от сервера или генерирует fallback.
  static String extractCallId(Map<String, dynamic> data, String callerKey) {
    // Пробуем разные поля где может быть call_id
    final callId = data['call_id'] 
        ?? data['callId'] 
        ?? data['id'];
    
    if (callId != null && callId.toString().isNotEmpty) {
      final id = callId.toString();
      // Проверяем что это не пустая строка и не "null"
      if (id.isNotEmpty && id != 'null') {
        return id;
      }
    }
    
    // Fallback с 30-секундным окном
    return generateFallbackCallId(callerKey);
  }

  /// Получить источник активного звонка (если запись есть и не устарела).
  /// Возвращает `ws` / `fcm` или null.
  static Future<String?> getActiveCallSource() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final callId = prefs.getString(_keyActiveCallId);
      final ts = prefs.getInt(_keyActiveCallTimestamp) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (callId == null || callId.isEmpty) return null;
      if ((now - ts) >= _ttlMs) return null;

      final source = prefs.getString(_keyActiveCallSource);
      if (source == null || source.isEmpty) return null;
      return source;
    } catch (e) {
      print("📞 CallIdStorage.getActiveCallSource ERROR: $e");
      return null;
    }
  }

  /// Получить возраст (в мс) активной записи callId (если есть и не устарела).
  static Future<int?> getActiveCallAgeMs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final callId = prefs.getString(_keyActiveCallId);
      final ts = prefs.getInt(_keyActiveCallTimestamp) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (callId == null || callId.isEmpty) return null;
      final age = now - ts;
      if (age >= _ttlMs) return null;
      return age;
    } catch (e) {
      print("📞 CallIdStorage.getActiveCallAgeMs ERROR: $e");
      return null;
    }
  }
}
