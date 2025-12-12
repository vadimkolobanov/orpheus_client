import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/models/contact_model.dart';

void main() {
  group('Contact Model Tests', () {
    test('Создание контакта с минимальными данными', () {
      final contact = Contact(
        name: 'Иван',
        publicKey: 'PUBLIC_KEY_123',
      );

      expect(contact.name, equals('Иван'));
      expect(contact.publicKey, equals('PUBLIC_KEY_123'));
      expect(contact.id, isNull);
    });

    test('Создание контакта с ID', () {
      final contact = Contact(
        id: 42,
        name: 'Мария',
        publicKey: 'PUBLIC_KEY_456',
      );

      expect(contact.id, equals(42));
      expect(contact.name, equals('Мария'));
      expect(contact.publicKey, equals('PUBLIC_KEY_456'));
    });

    test('Конвертация в Map для БД', () {
      final contact = Contact(
        id: 1,
        name: 'Тест',
        publicKey: 'KEY_789',
      );

      final map = contact.toMap();

      expect(map['id'], equals(1));
      expect(map['name'], equals('Тест'));
      expect(map['publicKey'], equals('KEY_789'));
    });

    test('Конвертация контакта без ID', () {
      final contact = Contact(
        name: 'Без ID',
        publicKey: 'KEY_999',
      );

      final map = contact.toMap();

      expect(map['id'], isNull);
      expect(map['name'], equals('Без ID'));
      expect(map['publicKey'], equals('KEY_999'));
    });

    test('Пустое имя обрабатывается корректно', () {
      final contact = Contact(
        name: '',
        publicKey: 'KEY_EMPTY',
      );

      expect(contact.name, isEmpty);
      expect(contact.toMap()['name'], isEmpty);
    });

    test('Длинное имя обрабатывается корректно', () {
      final longName = 'A' * 200;
      final contact = Contact(
        name: longName,
        publicKey: 'KEY_LONG',
      );

      expect(contact.name.length, equals(200));
      expect(contact.toMap()['name'], equals(longName));
    });

    test('Публичный ключ с пробелами обрабатывается', () {
      const keyWithSpaces = '  KEY_WITH_SPACES  ';
      final contact = Contact(
        name: 'Тест',
        publicKey: keyWithSpaces,
      );

      expect(contact.publicKey, equals(keyWithSpaces));
      expect(contact.toMap()['publicKey'], equals(keyWithSpaces));
    });
  });
}

