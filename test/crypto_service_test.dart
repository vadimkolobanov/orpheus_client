import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService cryptoService;

  setUp(() {
    // Имитируем SecureStorage (чтобы не лезть в реальный Keystore устройства)
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'read') {
        return null; // Имитируем, что ключей пока нет
      }
      if (methodCall.method == 'write') {
        return null; // Успешная запись
      }
      return null;
    });

    cryptoService = CryptoService();
  });

  group('CryptoService Critical Tests', () {
    test('Генерация ключей создает валидную пару', () async {
      await cryptoService.generateNewKeys();

      final pubKey = cryptoService.publicKeyBase64;
      expect(pubKey, isNotNull);
      expect(pubKey!.length, greaterThan(10));

      final privKey = await cryptoService.getPrivateKeyBase64();
      expect(privKey, isNotNull);
    });

    test('Полный цикл: Шифрование -> Дешифровка (через Isolate)', () async {
      // 1. Генерируем ключи для "Себя"
      await cryptoService.generateNewKeys();
      final myPub = cryptoService.publicKeyBase64!;

      // 2. Генерируем ключи для "Собеседника" (через второй сервис)
      final otherService = CryptoService();
      await otherService.generateNewKeys();
      final otherPub = otherService.publicKeyBase64!;

      const originalText = "Секретное сообщение для миллиардера 🚀";

      // 3. Шифруем (Я -> Ему)
      // ВАЖНО: Это проверяет работу compute() и изолятов
      final encryptedJson = await cryptoService.encrypt(otherPub, originalText);

      expect(encryptedJson, isNot(originalText));
      expect(encryptedJson, contains('cipherText'));
      expect(encryptedJson, contains('nonce'));
      expect(encryptedJson, contains('mac'));

      // 4. Дешифруем (Он -> От меня)
      // Имитируем получение на стороне собеседника
      // Для теста нам нужно инициализировать ключи собеседника в его сервисе
      // Но так как decrypt требует приватный ключ внутри сервиса, используем otherService

      final decryptedText = await otherService.decrypt(myPub, encryptedJson);

      expect(decryptedText, equals(originalText));
    });
  });
}