import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService cryptoService;

  setUp(() {
    // Имитируем SecureStorage (чтобы не лезть в реальный Keystore устройства)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          return null; // Имитируем, что ключей пока нет
        }
        if (methodCall.method == 'write') {
          return null; // Успешная запись
        }
        return null;
      },
    );

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
      expect(privKey.length, greaterThan(10));
    });

    test('Публичный ключ доступен только после генерации', () async {
      // До генерации ключей
      expect(cryptoService.publicKeyBase64, isNull);

      // После генерации
      await cryptoService.generateNewKeys();
      expect(cryptoService.publicKeyBase64, isNotNull);
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

    test('Шифрование пустого сообщения', () async {
      await cryptoService.generateNewKeys();
      final otherService = CryptoService();
      await otherService.generateNewKeys();
      final otherPub = otherService.publicKeyBase64!;

      const emptyText = "";

      final encryptedJson = await cryptoService.encrypt(otherPub, emptyText);
      expect(encryptedJson, isNotEmpty);

      final decryptedText = await otherService.decrypt(cryptoService.publicKeyBase64!, encryptedJson);
      expect(decryptedText, equals(emptyText));
    });

    test('Шифрование длинного сообщения', () async {
      await cryptoService.generateNewKeys();
      final otherService = CryptoService();
      await otherService.generateNewKeys();
      final otherPub = otherService.publicKeyBase64!;

      final longText = "A" * 10000;

      final encryptedJson = await cryptoService.encrypt(otherPub, longText);
      expect(encryptedJson, isNotEmpty);

      final decryptedText = await otherService.decrypt(cryptoService.publicKeyBase64!, encryptedJson);
      expect(decryptedText, equals(longText));
      expect(decryptedText.length, 10000);
    });

    test('Шифрование сообщения с эмодзи и спецсимволами', () async {
      await cryptoService.generateNewKeys();
      final otherService = CryptoService();
      await otherService.generateNewKeys();
      final otherPub = otherService.publicKeyBase64!;

      final specialText = "Привет! 🚀 Hello @#\$%^&*() 中文 العربية";

      final encryptedJson = await cryptoService.encrypt(otherPub, specialText);
      final decryptedText = await otherService.decrypt(cryptoService.publicKeyBase64!, encryptedJson);

      expect(decryptedText, equals(specialText));
    });

    test('Ошибка при шифровании без инициализации ключей', () async {
      final uninitializedService = CryptoService();
      final otherService = CryptoService();
      await otherService.generateNewKeys();
      final otherPub = otherService.publicKeyBase64!;

      expect(() async {
        await uninitializedService.encrypt(otherPub, "test");
      }, throwsA(anything));
    });

    test('Ошибка при дешифровании с неверным ключом', () async {
      await cryptoService.generateNewKeys();
      final otherService = CryptoService();
      await otherService.generateNewKeys();
      final otherPub = otherService.publicKeyBase64!;

      final encryptedJson = await cryptoService.encrypt(otherPub, "test");

      // Пытаемся дешифровать с неправильным ключом
      final wrongService = CryptoService();
      await wrongService.generateNewKeys();

      expect(() async {
        await wrongService.decrypt(cryptoService.publicKeyBase64!, encryptedJson);
      }, throwsA(anything));
    });
  });
}