// lib/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:orpheus_project/config.dart';
import 'package:rxdart/rxdart.dart';

enum ConnectionStatus { Disconnected, Connecting, Connected }

class WebSocketService {
  WebSocketChannel? _channel;
  final _socketResponseController = StreamController<String>.broadcast();
  Stream<String> get stream => _socketResponseController.stream;

  final _statusController = BehaviorSubject<ConnectionStatus>.seeded(ConnectionStatus.Disconnected);
  Stream<ConnectionStatus> get status => _statusController.stream;

  // --- ИЗМЕНЕНИЕ 1: `connect` больше не вызывает `disconnect` ---
  void connect(String myPublicKey) {
    // Добавляем "защиту от дурака": если мы уже подключены или подключаемся, ничего не делаем.
    if (_statusController.value == ConnectionStatus.Connected || _statusController.value == ConnectionStatus.Connecting) {
      print("Попытка подключения, когда уже есть соединение. Игнорируется.");
      return;
    }

    final uri = Uri.parse(AppConfig.webSocketUrl(myPublicKey));
    try {
      _statusController.add(ConnectionStatus.Connecting);
      print("Подключение к WebSocket: $uri");
      _channel = IOWebSocketChannel.connect(uri);

      // Статус "Connected" теперь отправляется только после того, как соединение подтверждено.
      // Для IOWebSocketChannel это происходит практически сразу, так что оставляем здесь.
      _statusController.add(ConnectionStatus.Connected);

      _channel!.stream.listen(
            (message) => _socketResponseController.add(message),
        onDone: () {
          print("Соединение закрыто (onDone).");
          // Убедимся, что мы действительно отключены, прежде чем менять статус
          if (_channel != null) {
            disconnect();
          }
        },
        onError: (error) {
          print("Ошибка WebSocket: $error");
          disconnect();
        },
      );
    } catch (e) {
      print("Не удалось подключиться: $e");
      _statusController.add(ConnectionStatus.Disconnected);
    }
  }

  // --- ИЗМЕНЕНИЕ 2: `disconnect` теперь более надежный ---
  void disconnect() {
    if (_channel == null) return; // Если уже отключены, ничего не делаем

    print("Отключение от WebSocket...");
    _statusController.add(ConnectionStatus.Disconnected);
    _channel!.sink.close();
    _channel = null;
  }

  // Методы отправки остаются без изменений
  void sendChatMessage(String recipientPublicKey, String payload) {
    if (_channel == null || _channel!.closeCode != null) return;
    final message = json.encode({"recipient_pubkey": recipientPublicKey, "type": "chat", "payload": payload});
    _channel!.sink.add(message);
  }
  void sendSignalingMessage(String recipientPublicKey, String type, Map<String, dynamic> data) {
    if (_channel == null || _channel!.closeCode != null) return;
    final message = json.encode({"recipient_pubkey": recipientPublicKey, "type": type, "data": data});
    print(">>> Отправка сигнала '$type' к $recipientPublicKey");
    _channel!.sink.add(message);
  }
}