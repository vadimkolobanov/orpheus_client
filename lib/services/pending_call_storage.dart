import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';

/// Persistent storage для pending call данных.
/// 
/// ПРОБЛЕМА: Когда пользователь принимает звонок через CallKit из background,
/// Android может полностью перезапустить Flutter Engine. При этом:
/// 1. Все данные в RAM (включая _pendingCall) теряются
/// 2. FlutterCallkitIncoming.activeCalls() часто возвращает 0 (CallKit уже завершил)
/// 3. Listener событий ещё не установлен когда accept происходит
/// 
/// РЕШЕНИЕ: Сохраняем pending call в SharedPreferences сразу при accept,
/// и загружаем при старте приложения.
class PendingCallStorage {
  static const _keyCallerKey = 'pending_call_caller_key';
  static const _keyOfferData = 'pending_call_offer_data';
  static const _keyTimestamp = 'pending_call_timestamp';
  static const _keyAutoAnswer = 'pending_call_auto_answer';
  static const _keyCallId = 'pending_call_call_id';
  
  /// Максимальное время жизни pending call (30 секунд)
  static const int maxAgeSeconds = 30;
  
  PendingCallStorage._();
  static final instance = PendingCallStorage._();
  
  SharedPreferences? _prefs;
  
  Future<SharedPreferences> get _getPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }
  
  /// Сохранить pending call для обработки после перезапуска
  Future<void> save({
    required String callerKey,
    Map<String, dynamic>? offerData,
    bool autoAnswer = true,
    String? callId,
  }) async {
    try {
      final prefs = await _getPrefs;
      
      await prefs.setString(_keyCallerKey, callerKey);
      await prefs.setInt(_keyTimestamp, DateTime.now().millisecondsSinceEpoch);
      await prefs.setBool(_keyAutoAnswer, autoAnswer);
      if (callId != null && callId.isNotEmpty) {
        await prefs.setString(_keyCallId, callId);
      } else {
        await prefs.remove(_keyCallId);
      }
      
      if (offerData != null) {
        await prefs.setString(_keyOfferData, json.encode(offerData));
      } else {
        await prefs.remove(_keyOfferData);
      }
      
      DebugLogger.info('PENDING_CALL', '💾 Сохранено: $callerKey, autoAnswer=$autoAnswer');
    } catch (e) {
      DebugLogger.error('PENDING_CALL', 'Ошибка сохранения: $e');
    }
  }
  
  /// Загрузить и очистить pending call (если есть и не устарел)
  Future<PendingCallData?> loadAndClear() async {
    try {
      final prefs = await _getPrefs;
      
      final callerKey = prefs.getString(_keyCallerKey);
      if (callerKey == null) {
        DebugLogger.info('PENDING_CALL', '📭 Нет ожидающего звонка в хранилище');
        return null;
      }
      
      final timestamp = prefs.getInt(_keyTimestamp) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      final ageSeconds = age ~/ 1000;
      
      // Проверяем что звонок не устарел
      if (ageSeconds > maxAgeSeconds) {
        DebugLogger.warn('PENDING_CALL', '⏰ Звонок устарел (${ageSeconds}s > ${maxAgeSeconds}s)');
        await clear();
        return null;
      }
      
      final autoAnswer = prefs.getBool(_keyAutoAnswer) ?? true;
      final offerDataStr = prefs.getString(_keyOfferData);
      final callId = prefs.getString(_keyCallId);
      
      Map<String, dynamic>? offerData;
      if (offerDataStr != null) {
        try {
          offerData = json.decode(offerDataStr) as Map<String, dynamic>;
        } catch (e) {
          DebugLogger.warn('PENDING_CALL', 'Ошибка парсинга offerData: $e');
        }
      }
      
      // Очищаем сразу после загрузки
      await clear();
      
      DebugLogger.info('PENDING_CALL', '📬 Загружено из хранилища: $callerKey, возраст=${ageSeconds}s');
      
      return PendingCallData(
        callerKey: callerKey,
        offerData: offerData,
        autoAnswer: autoAnswer,
        callId: callId,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
    } catch (e) {
      DebugLogger.error('PENDING_CALL', 'Ошибка загрузки: $e');
      return null;
    }
  }
  
  /// Очистить pending call
  Future<void> clear() async {
    try {
      final prefs = await _getPrefs;
      await prefs.remove(_keyCallerKey);
      await prefs.remove(_keyOfferData);
      await prefs.remove(_keyTimestamp);
      await prefs.remove(_keyAutoAnswer);
      await prefs.remove(_keyCallId);
      DebugLogger.info('PENDING_CALL', '🗑️ Хранилище очищено');
    } catch (e) {
      DebugLogger.error('PENDING_CALL', 'Ошибка очистки: $e');
    }
  }
  
  /// Проверить есть ли валидный pending call (без загрузки)
  Future<bool> hasPendingCall() async {
    try {
      final prefs = await _getPrefs;
      final callerKey = prefs.getString(_keyCallerKey);
      if (callerKey == null) return false;
      
      final timestamp = prefs.getInt(_keyTimestamp) ?? 0;
      final ageSeconds = (DateTime.now().millisecondsSinceEpoch - timestamp) ~/ 1000;
      
      return ageSeconds <= maxAgeSeconds;
    } catch (e) {
      return false;
    }
  }
}

/// Данные pending call (используется и в RAM и для storage)
class PendingCallData {
  final String callerKey;
  final Map<String, dynamic>? offerData;
  final DateTime timestamp;
  final bool autoAnswer;
  final String? callId;
  
  PendingCallData({
    required this.callerKey,
    this.offerData,
    this.autoAnswer = true,
    this.callId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  /// Проверка что звонок ещё актуален
  bool get isValid => DateTime.now().difference(timestamp).inSeconds < PendingCallStorage.maxAgeSeconds;
}
