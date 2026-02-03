// lib/services/ai_assistant_service.dart
// Сервис для общения с AI помощником Orpheus

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/models/ai_message_model.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/database_service.dart';

/// Сервис для взаимодействия с AI помощником через API.
/// 
/// Использует `/api/public/ai/call` endpoint для общения с контекстом диалога.
class AiAssistantService {
  AiAssistantService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final DatabaseService _db = DatabaseService.instance;
  static const int assistantMemoryLimit = 20;

  /// История сообщений в текущей сессии.
  final List<AiMessage> _messages = [];
  List<AiMessage> get messages => List.unmodifiable(_messages);

  /// ID последнего сообщения для контекста диалога на сервере.
  String? _parentMessageId;

  /// Stream для уведомления UI об изменениях.
  final _messagesController = StreamController<List<AiMessage>>.broadcast();
  Stream<List<AiMessage>> get messagesStream => _messagesController.stream;

  /// Флаг загрузки (AI думает).
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  final _loadingController = StreamController<bool>.broadcast();
  Stream<bool> get loadingStream => _loadingController.stream;

  /// Последняя ошибка.
  String? _error;
  String? get error => _error;

  /// Системный промпт для AI (база знаний загружается на сервере из docs/ai_kb/).

  /// Загрузить историю и контекст из локальной БД.
  Future<void> init() async {
    final history = await _db.getAiMessages(assistantLimit: assistantMemoryLimit);
    _messages
      ..clear()
      ..addAll(history);
    _parentMessageId = await _db.getAiParentMessageId();
    _messagesController.add(_messages);
  }

  /// Отправить сообщение AI и получить ответ.
  /// 
  /// Использует `/api/public/ai/call` с контекстом диалога (parent_message_id).
  Future<bool> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return false;

    _error = null;
    _setLoading(true);

    // Добавляем сообщение пользователя сразу (оптимистичный UI).
    final userMessage = AiMessage.user(trimmed);
    _messages.add(userMessage);
    _messagesController.add(_messages);
    await _db.addAiMessage(userMessage, assistantLimit: assistantMemoryLimit);

    try {
      final response = await _callAiEndpoint(trimmed);
      
      if (response != null) {
        final assistantMessage = AiMessage.assistant(response);
        _messages.add(assistantMessage);
        _messagesController.add(_messages);
        await _db.addAiMessage(assistantMessage, assistantLimit: assistantMemoryLimit);
        await _db.setAiParentMessageId(_parentMessageId);
        DebugLogger.success('AI_ASSISTANT', 'Ответ получен');
        return true;
      } else {
        // Ошибка — добавляем сообщение об ошибке.
        _messages.add(AiMessage.error(_error ?? 'Неизвестная ошибка'));
        _messagesController.add(_messages);
        await _db.addAiMessage(_messages.last, assistantLimit: assistantMemoryLimit);
        return false;
      }
    } catch (e) {
      _error = 'Ошибка сети: $e';
      _messages.add(AiMessage.error(_error!));
      _messagesController.add(_messages);
      await _db.addAiMessage(_messages.last, assistantLimit: assistantMemoryLimit);
      DebugLogger.error('AI_ASSISTANT', 'Ошибка: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Вызов /api/public/ai/call endpoint.
  Future<String?> _callAiEndpoint(String message) async {
    final url = AppConfig.httpUrl('/api/public/ai/call');
    
    final body = <String, dynamic>{
      'message': message,
    };
    
    // Добавляем parent_message_id для контекста, если есть.
    if (_parentMessageId != null) {
      body['parent_message_id'] = _parentMessageId;
    }

    try {
      final response = await _httpClient.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        // Извлекаем ответ (разные форматы API).
        final content = data['answer'] ??
            data['message'] ??
            data['response'] ??
            data['result'] ??
            data['content'] ??
            data['data']?['answer'];

        // Сохраняем message_id для контекста следующего запроса.
        final msgId = data['message_id'] ?? data['id'] ?? data['parent_message_id'];
        if (msgId != null) {
          _parentMessageId = msgId.toString();
        }

        if (content != null && content.toString().isNotEmpty) {
          return content.toString();
        } else {
          _error = 'AI вернул пустой ответ';
          DebugLogger.warn('AI_ASSISTANT', 'Пустой ответ от AI');
          return null;
        }
      } else if (response.statusCode == 503) {
        _error = 'AI сервис временно недоступен';
        DebugLogger.error('AI_ASSISTANT', 'Сервис недоступен (503)');
        return null;
      } else {
        // Пытаемся извлечь детали ошибки.
        String errorDetail;
        try {
          final errData = json.decode(response.body) as Map<String, dynamic>;
          errorDetail = errData['detail']?.toString() ?? 
                        errData['message']?.toString() ??
                        'Код ${response.statusCode}';
        } catch (_) {
          errorDetail = 'Код ${response.statusCode}';
        }
        _error = 'Ошибка AI: $errorDetail';
        DebugLogger.error('AI_ASSISTANT', 'Ошибка: $errorDetail');
        return null;
      }
    } on TimeoutException {
      _error = 'Превышено время ожидания ответа';
      DebugLogger.error('AI_ASSISTANT', 'Timeout');
      return null;
    } catch (e) {
      _error = 'Ошибка соединения';
      DebugLogger.error('AI_ASSISTANT', 'Ошибка соединения: $e');
      return null;
    }
  }

  /// Очистить историю чата и начать новый диалог.
  void clearChat() {
    _messages.clear();
    _parentMessageId = null;
    _error = null;
    _messagesController.add(_messages);
    _db.clearAiChat();
    DebugLogger.info('AI_ASSISTANT', 'Чат очищен');
  }

  void _setLoading(bool value) {
    _isLoading = value;
    _loadingController.add(value);
  }

  /// Освободить ресурсы.
  void dispose() {
    _messagesController.close();
    _loadingController.close();
  }
}
