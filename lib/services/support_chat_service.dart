// lib/services/support_chat_service.dart
// Сервис для чата с разработчиком

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/models/support_message.dart';
import 'package:orpheus_project/main.dart' show cryptoService;
import 'package:orpheus_project/services/debug_logger_service.dart';

class SupportChatService {
  SupportChatService({http.Client? httpClient}) 
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  
  // Кеш сообщений
  final List<SupportMessage> _messages = [];
  List<SupportMessage> get messages => List.unmodifiable(_messages);
  
  // Stream для уведомления UI
  final _messagesController = StreamController<List<SupportMessage>>.broadcast();
  Stream<List<SupportMessage>> get messagesStream => _messagesController.stream;
  
  // Счётчик непрочитанных
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;
  
  final _unreadController = StreamController<int>.broadcast();
  Stream<int> get unreadStream => _unreadController.stream;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  String? _error;
  String? get error => _error;

  /// Получить pubkey пользователя (из глобального cryptoService)
  String? get _pubkey => cryptoService.publicKeyBase64;

  /// HTTP заголовки с pubkey
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-Pubkey': _pubkey ?? '',
  };

  /// Загрузить историю сообщений
  Future<void> loadMessages({int limit = 100}) async {
    if (_pubkey == null) {
      _error = 'Аккаунт не инициализирован';
      return;
    }
    
    _isLoading = true;
    _error = null;
    
    try {
      final url = AppConfig.httpUrl('/api/support/messages?limit=$limit');
      final response = await _httpClient.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final messagesList = data['messages'] as List<dynamic>? ?? [];
        
        _messages.clear();
        for (final msgJson in messagesList) {
          _messages.add(SupportMessage.fromJson(msgJson as Map<String, dynamic>));
        }
        
        // После загрузки сообщения от админа помечаются как прочитанные на сервере
        _unreadCount = 0;
        _unreadController.add(_unreadCount);
        
        _messagesController.add(_messages);
        DebugLogger.info('SUPPORT', 'Загружено ${_messages.length} сообщений');
      } else {
        _error = 'Ошибка загрузки: ${response.statusCode}';
        DebugLogger.error('SUPPORT', 'Ошибка загрузки сообщений: ${response.statusCode}');
      }
    } catch (e) {
      _error = 'Ошибка подключения';
      DebugLogger.error('SUPPORT', 'Ошибка: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// Отправить сообщение
  Future<bool> sendMessage(String text) async {
    if (_pubkey == null || text.trim().isEmpty) return false;
    
    try {
      final url = AppConfig.httpUrl('/api/support/message');
      final response = await _httpClient.post(
        Uri.parse(url),
        headers: _headers,
        body: json.encode({'text': text.trim()}),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final msgId = data['id'] as int?;
        
        // Добавляем локально
        if (msgId != null) {
          _messages.add(SupportMessage(
            id: msgId,
            direction: MessageDirection.user,
            message: text.trim(),
            isRead: true,
            createdAt: DateTime.now(),
          ));
          _messagesController.add(_messages);
        }
        
        DebugLogger.success('SUPPORT', 'Сообщение отправлено');
        return true;
      } else {
        DebugLogger.error('SUPPORT', 'Ошибка отправки: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      DebugLogger.error('SUPPORT', 'Ошибка отправки: $e');
      return false;
    }
  }

  /// Отправить debug-логи
  Future<bool> sendLogs() async {
    if (_pubkey == null) return false;
    
    try {
      final logsData = DebugLogger.exportToText();
      final deviceInfo = await _getDeviceInfo();
      
      final url = AppConfig.httpUrl('/api/support/logs');
      final response = await _httpClient.post(
        Uri.parse(url),
        headers: _headers,
        body: json.encode({
          'logs_data': logsData,
          'app_version': AppConfig.appVersion,
          'device_info': deviceInfo,
        }),
      ).timeout(const Duration(seconds: 30)); // Больше времени для больших логов
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final linesCount = data['lines_count'] as int? ?? 0;
        
        // Добавляем системное сообщение локально
        _messages.add(SupportMessage(
          id: DateTime.now().millisecondsSinceEpoch,
          direction: MessageDirection.user,
          message: '📎 Debug-логи отправлены ($linesCount записей) • ${AppConfig.appVersion}',
          isRead: true,
          createdAt: DateTime.now(),
        ));
        _messagesController.add(_messages);
        
        DebugLogger.success('SUPPORT', 'Логи отправлены: $linesCount записей');
        return true;
      } else {
        DebugLogger.error('SUPPORT', 'Ошибка отправки логов: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      DebugLogger.error('SUPPORT', 'Ошибка отправки логов: $e');
      return false;
    }
  }

  /// Проверить непрочитанные сообщения
  Future<int> checkUnread() async {
    if (_pubkey == null) return 0;
    
    try {
      final url = AppConfig.httpUrl('/api/support/unread');
      final response = await _httpClient.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _unreadCount = data['unread_count'] as int? ?? 0;
        _unreadController.add(_unreadCount);
        return _unreadCount;
      }
    } catch (e) {
      // Молча игнорируем ошибки проверки
    }
    return _unreadCount;
  }

  /// Обработка входящего сообщения от поддержки (через WebSocket)
  void handleIncomingReply(Map<String, dynamic> data) {
    final text = data['text'] as String?;
    final createdAt = data['created_at'] as String?;
    
    if (text != null) {
      _messages.add(SupportMessage(
        id: DateTime.now().millisecondsSinceEpoch,
        direction: MessageDirection.admin,
        message: text,
        isRead: false,
        createdAt: createdAt != null 
            ? DateTime.parse(createdAt) 
            : DateTime.now(),
      ));
      
      _unreadCount++;
      _unreadController.add(_unreadCount);
      _messagesController.add(_messages);
      
      DebugLogger.info('SUPPORT', 'Получен ответ от поддержки');
    }
  }

  /// Получить информацию об устройстве
  Future<String> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return 'Android ${info.version.release} • ${info.manufacturer} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return 'iOS ${info.systemVersion} • ${info.model}';
      }
    } catch (_) {}
    
    return Platform.operatingSystem;
  }

  /// Очистить кеш
  void clear() {
    _messages.clear();
    _unreadCount = 0;
    _error = null;
    _messagesController.add(_messages);
    _unreadController.add(_unreadCount);
  }

  void dispose() {
    _messagesController.close();
    _unreadController.close();
  }
}

