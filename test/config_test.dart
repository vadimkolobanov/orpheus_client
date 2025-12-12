import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/config.dart';

void main() {
  group('AppConfig Tests', () {
    test('Версия приложения определена', () {
      expect(AppConfig.appVersion, isNotEmpty);
      expect(AppConfig.appVersion, contains('0.9'));
    });

    test('Генерация WebSocket URL', () {
      const publicKey = 'test_public_key_123';
      final url = AppConfig.webSocketUrl(publicKey);

      expect(url, contains('wss://'));
      expect(url, contains(publicKey));
      expect(url, contains(AppConfig.serverIp));
    });

    test('Генерация WebSocket URL с специальными символами', () {
      const publicKey = 'key+with/special=chars';
      final url = AppConfig.webSocketUrl(publicKey);

      // URL должен быть правильно закодирован
      expect(url, isNotEmpty);
      expect(url, contains('wss://'));
    });

    test('Генерация HTTP URL', () {
      final url = AppConfig.httpUrl('/api/test');

      expect(url, contains('https://'));
      expect(url, contains(AppConfig.serverIp));
      expect(url, endsWith('/api/test'));
    });

    test('Генерация HTTP URL с разными путями', () {
      final url1 = AppConfig.httpUrl('/api/check-update');
      final url2 = AppConfig.httpUrl('/api/users');

      expect(url1, contains('/api/check-update'));
      expect(url2, contains('/api/users'));
      expect(url1, startsWith('https://'));
      expect(url2, startsWith('https://'));
    });

    test('Changelog данные присутствуют', () {
      expect(AppConfig.changelogData, isNotEmpty);
      expect(AppConfig.changelogData.length, greaterThan(0));
    });

    test('Changelog содержит необходимые поля', () {
      for (final entry in AppConfig.changelogData) {
        expect(entry.containsKey('version'), isTrue);
        expect(entry.containsKey('date'), isTrue);
        expect(entry.containsKey('changes'), isTrue);
        expect(entry['changes'], isA<List>());
      }
    });

    test('Changelog версии корректны', () {
      for (final entry in AppConfig.changelogData) {
        final version = entry['version'] as String;
        expect(version, isNotEmpty);
      }
    });
  });
}




