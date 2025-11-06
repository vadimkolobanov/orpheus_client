// lib/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:orpheus_project/config.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final _socketResponseController = StreamController<String>.broadcast();
  Stream<String> get stream => _socketResponseController.stream;

  void connect(String myPublicKey) {
    final uri = Uri.parse(AppConfig.webSocketUrl(myPublicKey));
    try {
      disconnect();
      _channel = IOWebSocketChannel.connect(uri);
      print("Подключение к WebSocket: $uri");
      _channel!.stream.listen((message) {
        // print("Получено с сервера: $message"); // Можно закомментировать, чтобы не спамить в лог
        _socketResponseController.add(message);
      },
          onDone: () => print("Соединение закрыто."),
          onError: (error) => print("Ошибка WebSocket: $error"));
    } catch (e) {
      print("Не удалось подключиться: $e");
    }
  }

  // Старый метод для отправки сообщений чата
  void sendChatMessage(String recipientPublicKey, String payload) {
    if (_channel == null || _channel!.closeCode != null) return;
    final message = json.encode({
      "recipient_pubkey": recipientPublicKey,
      "type": "chat", // Явно указываем тип
      "payload": payload,
    });
    _channel!.sink.add(message);
  }

  // НОВЫЙ УНИВЕРСАЛЬНЫЙ МЕТОД для отправки сигнальных сообщений
  void sendSignalingMessage(String recipientPublicKey, String type, Map<String, dynamic> data) {
    if (_channel == null || _channel!.closeCode != null) return;
    final message = json.encode({
      "recipient_pubkey": recipientPublicKey,
      "type": type,
      "data": data,
    });
    print(">>> Отправка сигнала '$type' к $recipientPublicKey");
    _channel!.sink.add(message);
  }

  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
      print("Отключение от WebSocket.");
    }
  }
}