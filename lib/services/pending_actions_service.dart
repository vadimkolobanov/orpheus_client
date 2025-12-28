// lib/services/pending_actions_service.dart

import 'package:shared_preferences/shared_preferences.dart';

/// Минимальный интерфейс для хранилища pending-actions (для unit-тестов без плагинов).
abstract class PendingActionsPrefs {
  List<String>? getStringList(String key);
  Future<bool> setStringList(String key, List<String> value);
  Future<bool> remove(String key);
}

class SharedPrefsPendingActionsPrefs implements PendingActionsPrefs {
  SharedPrefsPendingActionsPrefs(this._prefs);
  final SharedPreferences _prefs;

  @override
  List<String>? getStringList(String key) => _prefs.getStringList(key);

  @override
  Future<bool> setStringList(String key, List<String> value) => _prefs.setStringList(key, value);

  @override
  Future<bool> remove(String key) => _prefs.remove(key);
}

/// Сервис для хранения и обработки отложенных действий (например, отклонение звонков)
/// когда приложение закрыто и WebSocket не подключен
class PendingActionsService {
  static const String _pendingRejectionsKey = 'pending_call_rejections';

  static Future<PendingActionsPrefs> Function() _prefsProvider =
      () async => SharedPrefsPendingActionsPrefs(await SharedPreferences.getInstance());

  /// В unit-тестах можно подменить хранилище, чтобы проверять ошибки/краевые случаи.
  static void debugSetPrefsProviderForTesting(Future<PendingActionsPrefs> Function()? provider) {
    _prefsProvider = provider ??
        (() async => SharedPrefsPendingActionsPrefs(await SharedPreferences.getInstance()));
  }

  static Future<PendingActionsPrefs> _prefs() => _prefsProvider();
  
  /// Сохранить отклонение звонка для последующей отправки
  static Future<void> addPendingRejection(String callerKey) async {
    try {
      final prefs = await _prefs();
      final existing = prefs.getStringList(_pendingRejectionsKey) ?? [];
      
      // Добавляем только если еще нет
      if (!existing.contains(callerKey)) {
        existing.add(callerKey);
        await prefs.setStringList(_pendingRejectionsKey, existing);
        print("📞 Pending rejection сохранен для: $callerKey");
      }
    } catch (e) {
      print("📞 ERROR: Не удалось сохранить pending rejection: $e");
    }
  }
  
  /// Получить все pending rejections
  static Future<List<String>> getPendingRejections() async {
    try {
      final prefs = await _prefs();
      return prefs.getStringList(_pendingRejectionsKey) ?? [];
    } catch (e) {
      print("📞 ERROR: Не удалось получить pending rejections: $e");
      return [];
    }
  }
  
  /// Удалить pending rejection после отправки
  static Future<void> removePendingRejection(String callerKey) async {
    try {
      final prefs = await _prefs();
      final existing = prefs.getStringList(_pendingRejectionsKey) ?? [];
      existing.remove(callerKey);
      await prefs.setStringList(_pendingRejectionsKey, existing);
      print("📞 Pending rejection удален для: $callerKey");
    } catch (e) {
      print("📞 ERROR: Не удалось удалить pending rejection: $e");
    }
  }
  
  /// Очистить все pending rejections
  static Future<void> clearAllPendingRejections() async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_pendingRejectionsKey);
      print("📞 Все pending rejections очищены");
    } catch (e) {
      print("📞 ERROR: Не удалось очистить pending rejections: $e");
    }
  }
}

