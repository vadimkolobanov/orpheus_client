// lib/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final _socketResponseController = StreamController<String>.broadcast();

  Stream<String> get stream => _socketResponseController.stream;

  void connect(String myPublicKey) {
    // ------------------- ИСПРАВЛЕНИЕ ЗДЕСЬ -------------------
    // Кодируем публичный ключ, чтобы символы вроде '+' и '/' не ломали URL.
    // Например, '/' станет '%2F'. FastAPI на сервере автоматически раскодирует это обратно.
    final encodedPublicKey = Uri.encodeComponent(myPublicKey);
    // -----------------------------------------------------------

    // ВАЖНО: Используйте 'localhost' для iOS-симулятора или '10.0.2.2' для Android-эмулятора
    final uri = Uri.parse('ws://10.0.2.2:8000/ws/$encodedPublicKey');

    try {
      _channel = IOWebSocketChannel.connect(uri);
      print("Подключение к WebSocket: $uri");

      _channel!.stream.listen((message) {
        print("Получено с сервера: $message");
        _socketResponseController.add(message);
      },
          onDone: () {
            print("Соединение закрыто.");
          },
          onError: (error) {
            print("Ошибка WebSocket: $error");
          });
    } catch (e) {
      print("Не удалось подключиться: $e");
    }
  }

  void sendMessage(String recipientPublicKey, String payload) {
    if (_channel == null || _channel!.closeCode != null) {
      print("Ошибка: WebSocket не подключен.");
      return;
    }

    final message = json.encode({
      "recipient_pubkey": recipientPublicKey,
      "payload": payload,
    });

    print("Отправка на сервер: $message");
    _channel!.sink.add(message);
  }

  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      print("Отключение от WebSocket.");
    }
  }
}