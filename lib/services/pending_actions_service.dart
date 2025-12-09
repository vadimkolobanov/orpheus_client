// lib/services/pending_actions_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Сервис для хранения и обработки отложенных действий (например, отклонение звонков)
/// когда приложение закрыто и WebSocket не подключен
class PendingActionsService {
  static const String _pendingRejectionsKey = 'pending_call_rejections';
  
  /// Сохранить отклонение звонка для последующей отправки
  static Future<void> addPendingRejection(String callerKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_pendingRejectionsKey) ?? [];
    } catch (e) {
      print("📞 ERROR: Не удалось получить pending rejections: $e");
      return [];
    }
  }
  
  /// Удалить pending rejection после отправки
  static Future<void> removePendingRejection(String callerKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingRejectionsKey);
      print("📞 Все pending rejections очищены");
    } catch (e) {
      print("📞 ERROR: Не удалось очистить pending rejections: $e");
    }
  }
}

