import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/update_service.dart';

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
  });
}

