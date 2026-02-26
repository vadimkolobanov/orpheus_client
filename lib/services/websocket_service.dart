import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/network_monitor_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/pending_actions_service.dart';
import 'package:rxdart/rxdart.dart';

enum ConnectionStatus { Disconnected, Connecting, Connected }

class WebSocketService {
  WebSocketService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  WebSocketChannel? _channel;
  final http.Client _httpClient;

  final _socketResponseController = StreamController<String>.broadcast();
  Stream<String> get stream => _socketResponseController.stream;

  final _statusController = BehaviorSubject<ConnectionStatus>.seeded(ConnectionStatus.Disconnected);
  Stream<ConnectionStatus> get status => _statusController.stream;
  ConnectionStatus get currentStatus => _statusController.value;

  String? _currentPublicKey;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isDisconnectingIntentional = false;

  // Подписка на изменения сети
  StreamSubscription? _networkSubscription;

  // Exponential backoff для реконнекта
  int _reconnectAttempt = 0;
  static const int _minReconnectDelay = 1; // секунды
  static const int _maxReconnectDelay = 30; // секунды

  int _getReconnectDelay() {
    // Экспоненциальный backoff: 1, 2, 4, 8, 16, 30, 30, 30...
    final delay = _minReconnectDelay * (1 << _reconnectAttempt);
    return delay.clamp(_minReconnectDelay, _maxReconnectDelay);
  }

  // === Миграция домена: запоминаем текущий хост и умеем fallback ===
  int _hostIndex = 0;
  String get currentHost => AppConfig.apiHosts[_hostIndex.clamp(0, AppConfig.apiHosts.length - 1)];

  /// Инициализация подписки на изменения сети
  void _initNetworkMonitoring() {
    _networkSubscription?.cancel();
    _networkSubscription = NetworkMonitorService.instance.onNetworkChange.listen((event) {
      DebugLogger.info('WS', '🌐 Network event: ${event.type}');
      
      if (event.type == NetworkChangeType.reconnected || 
          event.type == NetworkChangeType.networkSwitch) {
        // При восстановлении связи или смене сети - мгновенный реконнект
        _forceReconnect(reason: 'Network ${event.type.name}');
      } else if (event.type == NetworkChangeType.disconnected) {
        // При потере связи - не пытаемся переподключаться сразу
        DebugLogger.warn('WS', '📵 Сеть потеряна, ожидание восстановления...');
      }
    });
  }

  /// Принудительное переподключение (при смене сети)
  void _forceReconnect({String? reason}) {
    if (_currentPublicKey == null || _isDisconnectingIntentional) return;
    
    DebugLogger.info('WS', '🔄 Forced reconnect: ${reason ?? "unknown"}');
    
    // Отменяем текущий таймер реконнекта
    _reconnectTimer?.cancel();
    
    // Сбрасываем backoff для быстрого переподключения
    _reconnectAttempt = 0;
    
    // Закрываем текущее соединение
    _stopPingPong();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    
    // Немедленно переподключаемся
    _statusController.add(ConnectionStatus.Connecting);
    _initConnection();
  }

  void connect(String myPublicKey) {
    _currentPublicKey = myPublicKey;
    _isDisconnectingIntentional = false;
    _hostIndex = 0; // всегда начинаем с нового домена
    _reconnectAttempt = 0; // сброс backoff при новом подключении

    // Инициализируем мониторинг сети
    _initNetworkMonitoring();

    if (_statusController.value == ConnectionStatus.Connected ||
        _statusController.value == ConnectionStatus.Connecting) {
      return;
    }

    _initConnection();
  }

  void _initConnection() {
    if (_currentPublicKey == null) return;

    final uri = Uri.parse(AppConfig.webSocketUrl(_currentPublicKey!, host: currentHost));
    _statusController.add(ConnectionStatus.Connecting);
    print("WS: Попытка подключения к $uri...");
    DebugLogger.info('WS', 'Attempting to connect to $uri');

    try {
      WebSocket.connect(uri.toString()).then((ws) {
        ws.pingInterval = const Duration(seconds: 10);

        _channel = IOWebSocketChannel(ws);
        _statusController.add(ConnectionStatus.Connected);
        _reconnectAttempt = 0; // Сброс backoff при успешном подключении
        print("WS: Соединение установлено!");
        DebugLogger.success('WS', 'Соединение установлено!');

        _sendFcmToken();
        _startPingPong();
        
        // Отправляем pending сообщения после восстановления соединения
        _sendPendingMessages();

        _channel!.stream.listen(
              (message) {
            _socketResponseController.add(message);
            // Логируем входящие сообщения (кроме pong)
            try {
              final data = json.decode(message);
              final type = data['type'] ?? 'unknown';
              if (type != 'pong') {
                DebugLogger.info('WS', '📨 IN: $type');
              }
            } catch (_) {}
          },
          onDone: () {
            print("WS: Соединение закрыто (onDone).");
            DebugLogger.warn('WS', 'Соединение закрыто (onDone)');
            _handleDisconnect();
          },
          onError: (error) {
            print("WS ERROR: Socket error: $error");
            DebugLogger.error('WS', 'Socket error: $error');
            _handleDisconnect();
          },
        );
      }).catchError((e) {
        print("WS FATAL: Не удалось подключиться: $e");
        DebugLogger.error('WS', 'FATAL: Не удалось подключиться: $e');
        _rotateHost();
        _handleDisconnect();
      });
    } catch (e) {
      print("WS EXCEPTION: $e");
      DebugLogger.error('WS', 'EXCEPTION: $e');
      _rotateHost();
      _handleDisconnect();
    }
  }

  void _rotateHost() {
    if (AppConfig.apiHosts.isEmpty) return;
    _hostIndex = (_hostIndex + 1) % AppConfig.apiHosts.length;
    DebugLogger.warn('WS', 'Переключение хоста: $currentHost');
  }

  void _sendFcmToken() {
    final token = NotificationService().fcmToken;
    if (token != null) {
      print("WS: Отправка FCM токена на сервер...");
      DebugLogger.info('WS', 'Отправка FCM токена: ${token.substring(0, 20)}...');
      final msg = json.encode({
        "type": "register-fcm",
        "token": token
      });
      _channel?.sink.add(msg);
    } else {
      print("WS WARN: FCM токен не готов, пропускаем отправку.");
      DebugLogger.warn('WS', 'FCM токен не готов, пропускаем отправку');
    }
  }

  void _handleDisconnect() {
    if (_statusController.value != ConnectionStatus.Disconnected) {
      _statusController.add(ConnectionStatus.Disconnected);
      DebugLogger.warn('WS', 'Статус изменён на Disconnected');
    }

    _stopPingPong();

    if (!_isDisconnectingIntentional) {
      final delay = _getReconnectDelay();
      _reconnectAttempt++;
      print("WS: Планирование переподключения через $delay сек (попытка $_reconnectAttempt)...");
      DebugLogger.info('WS', 'Планирование переподключения через $delay сек (попытка $_reconnectAttempt)...');
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: delay), () {
        print("WS: Попытка реконнекта #$_reconnectAttempt...");
        DebugLogger.info('WS', 'Попытка реконнекта #$_reconnectAttempt...');
        _initConnection();
      });
    }
  }

  void disconnect() {
    _isDisconnectingIntentional = true;
    _reconnectTimer?.cancel();
    _stopPingPong();
    _networkSubscription?.cancel();
    _networkSubscription = null;

    if (_channel != null) {
      print("WS: Отключение...");
      _channel!.sink.close();
      _channel = null;
    }
    _statusController.add(ConnectionStatus.Disconnected);
  }

  @visibleForTesting
  void debugAttachConnectedChannel(WebSocketChannel channel, {String? currentPublicKey}) {
    _channel = channel;
    if (currentPublicKey != null) _currentPublicKey = currentPublicKey;
    _statusController.add(ConnectionStatus.Connected);
  }

  void _startPingPong() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_channel != null && _statusController.value == ConnectionStatus.Connected) {
        try {
          _channel!.sink.add(json.encode({"type": "ping"}));
        } catch (e) {
          print("WS: Ping send error: $e");
        }
      }
    });
  }

  void _stopPingPong() {
    _pingTimer?.cancel();
  }

  void sendChatMessage(String recipientPublicKey, String payload) {
    final msg = {"recipient_pubkey": recipientPublicKey, "type": "chat", "payload": payload};
    
    // Если нет соединения - сохраняем в очередь
    if (_channel == null || _statusController.value != ConnectionStatus.Connected) {
      DebugLogger.warn('WS', '📵 Нет соединения, сообщение сохранено в очередь');
      PendingActionsService.addPendingMessage(
        recipientKey: recipientPublicKey,
        encryptedPayload: payload,
      );
      return;
    }
    
    _sendMessage(msg);
  }
  
  /// Отправить все pending сообщения после восстановления соединения.
  /// Удаляет из очереди ТОЛЬКО те, что реально ушли в канал.
  Future<void> _sendPendingMessages() async {
    final pending = await PendingActionsService.getPendingMessages();
    if (pending.isEmpty) return;

    DebugLogger.info('WS', '📤 Отправка ${pending.length} pending сообщений...');

    var sentCount = 0;
    for (final msg in pending) {
      if (_channel == null || _statusController.value != ConnectionStatus.Connected) {
        DebugLogger.warn('WS', 'Соединение потеряно при отправке pending сообщений, отправлено $sentCount из ${pending.length}');
        break;
      }

      _sendMessage({
        "recipient_pubkey": msg.recipientKey,
        "type": "chat",
        "payload": msg.encryptedPayload,
      });
      sentCount++;

      // Небольшая задержка между сообщениями
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (sentCount == pending.length) {
      await PendingActionsService.clearPendingMessages();
      DebugLogger.success('WS', 'Все $sentCount pending сообщений отправлены');
    } else if (sentCount > 0) {
      await PendingActionsService.removeFirstMessages(sentCount);
      DebugLogger.warn('WS', 'Отправлено $sentCount из ${pending.length}, остальные остались в очереди');
    }
  }

  // --- ОТПРАВКА СИГНАЛОВ С HTTP FALLBACK ---
  void sendSignalingMessage(String recipientPublicKey, String type, Map<String, dynamic> data) {
    final callId = data['call_id'] ?? data['callId'] ?? data['id'];
    final signalContext = <String, dynamic>{
      'call_id': callId,
      'peer_pubkey': recipientPublicKey,
      'signal_type': type,
    };
    final msg = {
      "recipient_pubkey": recipientPublicKey,
      "type": type,
      "data": data
    };
    
    // Важные сигналы - используем HTTP fallback для гарантии доставки
    // КРИТИЧНО: Все call-related сигналы должны быть здесь!
    // Когда app в background, WebSocket может быть отключён,
    // но call-answer/call-offer ДОЛЖНЫ доставляться через HTTP.
    final isImportant = type == 'hang-up' || type == 'call-rejected' || 
                        type == 'call-offer' || type == 'call-answer' ||
                        type == 'ice-candidate' ||
                        type == 'ice-restart' || type == 'ice-restart-answer';
    final statusStr = currentStatus.toString().split('.').last;
    
    if (isImportant) {
      print("📤📞 WS SEND [$type] → ${recipientPublicKey.substring(0, 8)}... | Status: $statusStr | Channel: ${_channel != null ? 'OK' : 'NULL'}");
      DebugLogger.info(
        'SIGNAL',
        '📤 OUT: $type → ${recipientPublicKey.substring(0, 8)}... | Status: $statusStr | Ch: ${_channel != null ? 'OK' : 'NULL'}',
        context: signalContext,
      );
      
      // Если WebSocket недоступен - сразу HTTP
      if (_channel == null || _statusController.value != ConnectionStatus.Connected) {
        print("⚠️ WS недоступен для [$type] - используем HTTP fallback");
        DebugLogger.warn('SIGNAL', 'WS недоступен для [$type] - используем HTTP fallback', context: signalContext);
        _sendSignalViaHttpWithData(recipientPublicKey, type, data);
        return;
      }
    } else {
      print("📤 WS SEND $type → ${recipientPublicKey.substring(0, 8)}... Size: ${data.toString().length}");
      DebugLogger.info('SIGNAL', '📤 OUT: $type → ${recipientPublicKey.substring(0, 8)}...', context: signalContext);
    }
    
    _sendMessage(msg);
    
    // Для важных сигналов ВСЕГДА отправляем также через HTTP как гарантию доставки
    // на ВСЕ хосты, чтобы доставить сигнал даже если получатель на другом сервере
    if (isImportant) {
      _sendSignalViaHttpWithData(recipientPublicKey, type, data);
    }
  }

  /// HTTP fallback для гарантированной доставки hang-up/call-rejected (без данных)
  Future<void> _sendSignalViaHttp(String recipientPublicKey, String signalType) async {
    await _sendSignalViaHttpWithData(recipientPublicKey, signalType, {});
  }

  /// HTTP fallback для гарантированной доставки сигналов с данными (ice-restart, etc)
  /// Отправляет на ВСЕ хосты параллельно для гарантии доставки
  Future<void> _sendSignalViaHttpWithData(String recipientPublicKey, String signalType, Map<String, dynamic> data) async {
    final callId = data['call_id'] ?? data['callId'] ?? data['id'];
    final signalContext = <String, dynamic>{
      'call_id': callId,
      'peer_pubkey': recipientPublicKey,
      'signal_type': signalType,
    };
    DebugLogger.info('HTTP', 'Отправка $signalType через HTTP fallback на все хосты...', context: signalContext);
    
    final body = json.encode({
      'sender_pubkey': _currentPublicKey,
      'recipient_pubkey': recipientPublicKey,
      'signal_type': signalType,
      'data': data,
    });

    // Отправляем на ВСЕ хосты параллельно
    // Это гарантирует доставку даже если получатель на другом сервере
    final futures = <Future<bool>>[];
    
    for (final url in AppConfig.httpUrls('/api/signal')) {
      futures.add(_trySendSignalToHost(url, signalType, body));
    }

    try {
      final results = await Future.wait(futures);
      final successCount = results.where((r) => r).length;
      
      if (successCount > 0) {
        print("✅ HTTP: [$signalType] доставлен на $successCount/${futures.length} хостов");
        DebugLogger.success('HTTP', '[$signalType] доставлен на $successCount/${futures.length} хостов', context: signalContext);
      } else {
        print("❌ HTTP: [$signalType] не удалось доставить ни на один хост");
        DebugLogger.error('HTTP', '[$signalType] не удалось доставить ни на один хост', context: signalContext);
      }
    } catch (e) {
      print("❌ HTTP: [$signalType] исключение: $e");
      DebugLogger.error('HTTP', '[$signalType] исключение: $e', context: signalContext);
    }
  }

  Future<bool> _trySendSignalToHost(String url, String signalType, String body) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        DebugLogger.info('HTTP', '[$signalType] → $url: OK');
        return true;
      } else {
        DebugLogger.warn('HTTP', '[$signalType] → $url: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      DebugLogger.warn('HTTP', '[$signalType] → $url: $e');
      return false;
    }
  }

  void sendRawMessage(String jsonString) {
    if (_channel != null) _channel!.sink.add(jsonString);
  }

  void _sendMessage(Map<String, dynamic> map) {
    final type = map['type'] as String?;
    final data = map['data'];
    final callId = data is Map ? data['call_id'] ?? data['callId'] ?? data['id'] : null;
    final signalContext = <String, dynamic>{
      'call_id': callId,
      'peer_pubkey': map['recipient_pubkey'],
      'signal_type': type,
    };
    // Все call-related сигналы считаются важными
    final isImportant = type == 'hang-up' || type == 'call-rejected' ||
                        type == 'call-offer' || type == 'call-answer' ||
                        type == 'ice-candidate' ||
                        type == 'ice-restart' || type == 'ice-restart-answer';
    
    if (_channel == null || _statusController.value != ConnectionStatus.Connected) {
      if (isImportant) {
        print("⚠️ WS ERROR: Не удалось отправить [$type] - нет соединения! Status: ${_statusController.value}");
        DebugLogger.error('SIGNAL', 'WS ERROR: нет соединения для [$type]', context: signalContext);
      } else {
        print("WS ERROR: Нет соединения для отправки сообщения.");
      }
      return;
    }
    
    _channel!.sink.add(json.encode(map));
    
    if (isImportant) {
      print("✅ WS: [$type] успешно отправлен в канал");
      DebugLogger.success('SIGNAL', '✅ WS: [$type] отправлен', context: signalContext);
    }
  }
}