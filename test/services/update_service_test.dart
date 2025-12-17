import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/update_service.dart';
import 'package:orpheus_project/config.dart';

void main() {
  group('UpdateService Tests', () {
    test('Сервис является статическим классом', () {
      // Проверяем, что методы доступны без создания экземпляра
      expect(UpdateService.checkForUpdate, isA<Function>());
    });

    test('Метод checkForUpdate определен', () {
      // Проверяем, что метод существует и может быть вызван
      expect(UpdateService.checkForUpdate, isNotNull);
    });

    test('resolveDownloadUrl: абсолютный URL не меняется', () {
      const url = 'https://update.orpheus.click/orpheus.apk';
      expect(UpdateService.resolveDownloadUrl(url), equals(url));
    });

    test('resolveDownloadUrl: относительный путь резолвится через AppConfig', () {
      const path = '/download';
      expect(UpdateService.resolveDownloadUrl(path), equals(AppConfig.httpUrl(path)));
    });
  });
}

