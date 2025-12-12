import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/websocket_service.dart';

void main() {
  group('WebSocketService Tests', () {
    late WebSocketService service;

    setUp(() {
      service = WebSocketService();
    });

    tearDown(() {
      service.disconnect();
    });

    test('Инициализация сервиса', () {
      expect(service, isNotNull);
      expect(service.stream, isNotNull);
      expect(service.status, isNotNull);
    });

    test('Начальное состояние - Disconnected', () async {
      final status = await service.status.first;
      expect(status, equals(ConnectionStatus.Disconnected));
    });

    test('Попытка отправки сообщения без подключения', () {
      // Не должно выбрасывать исключение, но и не отправлять
      expect(() {
        service.sendChatMessage('recipient_key', 'payload');
      }, returnsNormally);
    });

    test('Попытка отправки сигнального сообщения без подключения', () {
      expect(() {
        service.sendSignalingMessage('recipient_key', 'call-offer', {'sdp': 'test'});
      }, returnsNormally);
    });

    test('Попытка отправки сырого сообщения без подключения', () {
      expect(() {
        service.sendRawMessage('{"type":"test"}');
      }, returnsNormally);
    });

    test('Множественные вызовы disconnect безопасны', () {
      expect(() {
        service.disconnect();
        service.disconnect();
        service.disconnect();
      }, returnsNormally);
    });

    test('Поток статуса работает корректно', () async {
      final statuses = <ConnectionStatus>[];
      final subscription = service.status.listen((status) {
        statuses.add(status);
      });

      // Даем время на получение начального статуса
      await Future.delayed(const Duration(milliseconds: 100));

      subscription.cancel();
      expect(statuses, isNotEmpty);
      expect(statuses.first, equals(ConnectionStatus.Disconnected));
    });

    test('Поток сообщений работает корректно', () async {
      final messages = <String>[];
      final subscription = service.stream.listen((message) {
        messages.add(message);
      });

      // Даем время на инициализацию
      await Future.delayed(const Duration(milliseconds: 100));

      subscription.cancel();
      // Поток должен быть создан, даже если сообщений нет
      expect(service.stream, isNotNull);
    });
  });
}

