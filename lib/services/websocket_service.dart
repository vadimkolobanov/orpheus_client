import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/pending_actions_service.dart';
import 'package:rxdart/rxdart.dart';

enum ConnectionStatus { Disconnected, Connecting, Connected }

class WebSocketService {
  WebSocketChannel? _channel;

  final _socketResponseController = StreamController<String>.broadcast();
  Stream<String> get stream => _socketResponseController.stream;

  final _statusController = BehaviorSubject<ConnectionStatus>.seeded(ConnectionStatus.Disconnected);
  Stream<ConnectionStatus> get status => _statusController.stream;
  
  /// Получить текущее значение статуса соединения
  ConnectionStatus get currentStatus => _statusController.value;

  String? _currentPublicKey;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isDisconnectingIntentional = false;

  void connect(String myPublicKey) {
    _currentPublicKey = myPublicKey;
    _isDisconnectingIntentional = false;

    if (_statusController.value == ConnectionStatus.Connected ||
        _statusController.value == ConnectionStatus.Connecting) {
      return;
    }

    _initConnection();
  }

  void _initConnection() {
    if (_currentPublicKey == null) return;

    final uri = Uri.parse(AppConfig.webSocketUrl(_currentPublicKey!));
    _statusController.add(ConnectionStatus.Connecting);
    print("WS: Попытка подключения к $uri...");

    try {
      WebSocket.connect(uri.toString()).then((ws) {
        ws.pingInterval = const Duration(seconds: 10);

        _channel = IOWebSocketChannel(ws);
        _statusController.add(ConnectionStatus.Connected);
        print("WS: Соединение установлено!");

        _sendFcmToken();
        _sendPendingRejections();
        _startPingPong();

        _channel!.stream.listen(
              (message) {
            _socketResponseController.add(message);
          },
          onDone: () {
            print("WS: Соединение закрыто (onDone).");
            _handleDisconnect();
          },
          onError: (error) {
            print("WS ERROR: Ошибка сокета: $error");
            _handleDisconnect();
          },
        );
      }).catchError((e) {
        print("WS FATAL: Не удалось подключиться: $e");
        _handleDisconnect();
      });
    } catch (e) {
      print("WS EXCEPTION: $e");
      _handleDisconnect();
    }
  }

  void _sendFcmToken() {
    sendFcmToken();
  }

  /// Публичный метод для отправки FCM токена (можно вызвать извне при обновлении токена)
  void sendFcmToken() {
    final token = NotificationService().fcmToken;
    if (token != null && _channel != null && _statusController.value == ConnectionStatus.Connected) {
      print("WS: Отправка FCM токена на сервер...");
      final msg = json.encode({
        "type": "register-fcm",
        "token": token
      });
      _channel!.sink.add(msg);
    } else {
      if (token == null) {
        print("WS WARN: FCM токен не готов, пропускаем отправку.");
      } else if (_statusController.value != ConnectionStatus.Connected) {
        print("WS WARN: WebSocket не подключен, токен будет отправлен при следующем подключении.");
      }
    }
  }

  /// Отправка всех pending rejections при подключении
  Future<void> _sendPendingRejections() async {
    if (_channel == null || _statusController.value != ConnectionStatus.Connected) {
      return;
    }

    try {
      final pendingRejections = await PendingActionsService.getPendingRejections();
      if (pendingRejections.isEmpty) {
        return;
      }

      print("WS: Отправка ${pendingRejections.length} pending rejections...");
      
      for (final callerKey in pendingRejections) {
        try {
          sendSignalingMessage(callerKey, 'call-rejected', {});
          await PendingActionsService.removePendingRejection(callerKey);
          print("WS: Pending rejection отправлен для: $callerKey");
          
          // Небольшая задержка между отправками
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          print("WS ERROR: Не удалось отправить pending rejection для $callerKey: $e");
        }
      }
      
      print("WS: Все pending rejections обработаны");
    } catch (e) {
      print("WS ERROR: Ошибка при отправке pending rejections: $e");
    }
  }

  void _handleDisconnect() {
    if (_statusController.value != ConnectionStatus.Disconnected) {
      _statusController.add(ConnectionStatus.Disconnected);
    }

    _stopPingPong();

    if (!_isDisconnectingIntentional) {
      print("WS: Планирование переподключения через 3 сек...");
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        print("WS: Попытка реконнекта...");
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

  // --- ДИАГНОСТИКА: ЛОГИРОВАНИЕ ОТПРАВКИ СИГНАЛОВ ---
  void sendSignalingMessage(String recipientPublicKey, String type, Map<String, dynamic> data) {
    final msg = {
      "recipient_pubkey": recipientPublicKey,
      "type": type,
      "data": data
    };
    print("📤 WS SEND $type → ${recipientPublicKey.substring(0, 8)}... Size: ${data.toString().length}");
    _sendMessage(msg);
  }

  void sendRawMessage(String jsonString) {
    if (_channel != null) _channel!.sink.add(jsonString);
  }

  void _sendMessage(Map<String, dynamic> map) {
    if (_channel == null || _statusController.value != ConnectionStatus.Connected) {
      print("❌ WS ERROR: Нет соединения для отправки сообщения type=${map['type']}");
      return;
    }
    print("✅ WS SENDING: type=${map['type']}");
    _channel!.sink.add(json.encode(map));
  }
}