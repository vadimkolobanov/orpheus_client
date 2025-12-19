import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
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

  // === Миграция домена: запоминаем текущий хост и умеем fallback ===
  int _hostIndex = 0;
  String get currentHost => AppConfig.apiHosts[_hostIndex.clamp(0, AppConfig.apiHosts.length - 1)];

  void connect(String myPublicKey) {
    _currentPublicKey = myPublicKey;
    _isDisconnectingIntentional = false;
    _hostIndex = 0; // всегда начинаем с нового домена

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
    DebugLogger.info('WS', 'Попытка подключения к $uri');

    try {
      WebSocket.connect(uri.toString()).then((ws) {
        ws.pingInterval = const Duration(seconds: 10);

        _channel = IOWebSocketChannel(ws);
        _statusController.add(ConnectionStatus.Connected);
        print("WS: Соединение установлено!");
        DebugLogger.success('WS', 'Соединение установлено!');

        _sendFcmToken();
        _startPingPong();

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
            print("WS ERROR: Ошибка сокета: $error");
            DebugLogger.error('WS', 'Ошибка сокета: $error');
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
      print("WS: Планирование переподключения через 3 сек...");
      DebugLogger.info('WS', 'Планирование переподключения через 3 сек...');
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        print("WS: Попытка реконнекта...");
        DebugLogger.info('WS', 'Попытка реконнекта...');
        _initConnection();
      });
    }
  }

  void disconnect() {
    _isDisconnectingIntentional = true;
    _reconnectTimer?.cancel();
    _stopPingPong();

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
          print("WS: Ошибка отправки пинга: $e");
        }
      }
    });
  }

  void _stopPingPong() {
    _pingTimer?.cancel();
  }

  void sendChatMessage(String recipientPublicKey, String payload) {
    _sendMessage({"recipient_pubkey": recipientPublicKey, "type": "chat", "payload": payload});
  }

  // --- ОТПРАВКА СИГНАЛОВ С HTTP FALLBACK ---
  void sendSignalingMessage(String recipientPublicKey, String type, Map<String, dynamic> data) {
    final msg = {
      "recipient_pubkey": recipientPublicKey,
      "type": type,
      "data": data
    };
    
    // Важные сигналы (hang-up, call-rejected) - используем HTTP fallback если WS недоступен
    final isImportant = type == 'hang-up' || type == 'call-rejected';
    final statusStr = currentStatus.toString().split('.').last;
    
    if (isImportant) {
      print("📤📞 WS SEND [$type] → ${recipientPublicKey.substring(0, 8)}... | Status: $statusStr | Channel: ${_channel != null ? 'OK' : 'NULL'}");
      DebugLogger.info('SIGNAL', '📤 OUT: $type → ${recipientPublicKey.substring(0, 8)}... | Status: $statusStr | Ch: ${_channel != null ? 'OK' : 'NULL'}');
      
      // Если WebSocket недоступен - сразу HTTP
      if (_channel == null || _statusController.value != ConnectionStatus.Connected) {
        print("⚠️ WS недоступен для [$type] - используем HTTP fallback");
        DebugLogger.warn('SIGNAL', 'WS недоступен для [$type] - используем HTTP fallback');
        _sendSignalViaHttp(recipientPublicKey, type);
        return;
      }
    } else {
      print("📤 WS SEND $type → ${recipientPublicKey.substring(0, 8)}... Size: ${data.toString().length}");
      DebugLogger.info('SIGNAL', '📤 OUT: $type → ${recipientPublicKey.substring(0, 8)}...');
    }
    
    _sendMessage(msg);
    
    // Для важных сигналов ВСЕГДА отправляем также через HTTP как гарантию доставки
    if (isImportant) {
      _sendSignalViaHttp(recipientPublicKey, type);
    }
  }

  /// HTTP fallback для гарантированной доставки hang-up/call-rejected
  Future<void> _sendSignalViaHttp(String recipientPublicKey, String signalType) async {
    DebugLogger.info('HTTP', 'Отправка $signalType через HTTP fallback...');
    try {
      http.Response? response;

      // 1) сначала пробуем текущий хост (если WS уже установлен/пытались подключаться)
      final primaryUrl = AppConfig.httpUrl('/api/signal', host: currentHost);
      response = await _httpClient.post(
        Uri.parse(primaryUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'sender_pubkey': _currentPublicKey,
          'recipient_pubkey': recipientPublicKey,
          'signal_type': signalType,
        }),
      ).timeout(const Duration(seconds: 5));

      // 2) если запрос упал исключением — уйдём в catch и попробуем fallback ниже
      
      if (response.statusCode == 200) {
        print("✅ HTTP: [$signalType] успешно отправлен");
        DebugLogger.success('HTTP', '[$signalType] успешно отправлен (${response.statusCode})');
      } else {
        print("⚠️ HTTP: [$signalType] ошибка ${response.statusCode}");
        DebugLogger.error('HTTP', '[$signalType] ошибка ${response.statusCode}');
      }
    } catch (e) {
      // fallback по всем хостам
      for (final url in AppConfig.httpUrls('/api/signal')) {
        try {
          final response = await _httpClient.post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'sender_pubkey': _currentPublicKey,
              'recipient_pubkey': recipientPublicKey,
              'signal_type': signalType,
            }),
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            print("✅ HTTP: [$signalType] успешно отправлен (fallback)");
            DebugLogger.success('HTTP', '[$signalType] успешно отправлен (fallback) (${response.statusCode})');
            return;
          }
        } catch (_) {
          continue;
        }
      }

      print("❌ HTTP: [$signalType] исключение: $e");
      DebugLogger.error('HTTP', '[$signalType] исключение: $e');
    }
  }

  void sendRawMessage(String jsonString) {
    if (_channel != null) _channel!.sink.add(jsonString);
  }

  void _sendMessage(Map<String, dynamic> map) {
    final type = map['type'] as String?;
    final isImportant = type == 'hang-up' || type == 'call-rejected';
    
    if (_channel == null || _statusController.value != ConnectionStatus.Connected) {
      if (isImportant) {
        print("⚠️ WS ERROR: Не удалось отправить [$type] - нет соединения! Status: ${_statusController.value}");
      } else {
        print("WS ERROR: Нет соединения для отправки сообщения.");
      }
      return;
    }
    
    _channel!.sink.add(json.encode(map));
    
    if (isImportant) {
      print("✅ WS: [$type] успешно отправлен в канал");
    }
  }
}