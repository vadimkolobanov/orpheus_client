// lib/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:orpheus_project/config.dart'; // <-- ДОБАВЛЕН ИМПОРТ НАШЕГО КОНФИГА

class WebSocketService {
  WebSocketChannel? _channel;
  final _socketResponseController = StreamController<String>.broadcast();

  // Стрим, на который UI будет подписываться, чтобы получать сообщения
  Stream<String> get stream => _socketResponseController.stream;

  // Подключение к серверу
  void connect(String myPublicKey) {
    // ИЗМЕНЕНИЕ: Теперь URL строится централизованно из файла config.dart
    // Мы больше не пишем IP-адрес прямо здесь.
    final uri = Uri.parse(AppConfig.webSocketUrl(myPublicKey));

    try {
      // Предварительно закрываем старое соединение, если оно было
      disconnect();

      _channel = IOWebSocketChannel.connect(uri);
      print("Подключение к WebSocket: $uri");

      // Слушаем входящие сообщения
      _channel!.stream.listen((message) {
        print("Получено с сервера: $message");
        // Добавляем полученное сообщение в стрим для UI
        _socketResponseController.add(message);
      },
          onDone: () {
            print("Соединение закрыто.");
          },
          onError: (error) {
            print("Ошибка WebSocket: $error");
            // Можно добавить логику повторного подключения здесь, если нужно
          });
    } catch (e) {
      print("Не удалось подключиться: $e");
    }
  }

  // Отправка сообщения
  void sendMessage(String recipientPublicKey, String payload) {
    if (_channel == null || _channel!.closeCode != null) {
      print("Ошибка: WebSocket не подключен.");
      // Попытка переподключения, если соединение разорвано
      // if (cryptoService.publicKeyBase64 != null) {
      //   connect(cryptoService.publicKeyBase64!);
      // }
      return;
    }

    // Формируем JSON, который ожидает сервер
    final message = json.encode({
      "recipient_pubkey": recipientPublicKey,
      "payload": payload,
    });

    print("Отправка на сервер: $message");
    _channel!.sink.add(message);
  }

  // Закрытие соединения
  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null; // Важно обнулить канал после закрытия
      print("Отключение от WebSocket.");
    }
  }
}