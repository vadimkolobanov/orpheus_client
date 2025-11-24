// lib/services/crypto_service.dart

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  final _secureStorage = const FlutterSecureStorage();

  static const _privateKeyStoreKey = 'orpheus_private_key_data';
  static const _publicKeyStoreKey = 'orpheus_public_key_data';

  final keyExchangeAlgorithm = X25519();
  final symmetricCipher = Chacha20.poly1305Aead();

  SimpleKeyPair? _keyPair;
  SimplePublicKey? _publicKey;

  String? get publicKeyBase64 => _publicKey != null ? base64.encode(_publicKey!.bytes) : null;

  // Метод инициализации теперь возвращает true, если ключи загружены, и false, если их нет
  Future<bool> init() async {
    final privateKeyB64 = await _secureStorage.read(key: _privateKeyStoreKey);
    final publicKeyB64 = await _secureStorage.read(key: _publicKeyStoreKey);

    if (privateKeyB64 != null && publicKeyB64 != null) {
      final privateKeyBytes = base64.decode(privateKeyB64);
      final publicKeyBytes = base64.decode(publicKeyB64);

      _publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519);
      _keyPair = SimpleKeyPairData(
        privateKeyBytes,
        publicKey: _publicKey!,
        type: KeyPairType.x25519,
      );
      print("Ключи загружены.");
      return true; // Ключи есть
    }
    return false; // Ключей нет
  }

  // Явная генерация (для кнопки "Создать аккаунт")
  Future<void> generateNewKeys() async {
    _keyPair = await keyExchangeAlgorithm.newKeyPair();
    final privateKeyData = await _keyPair!.extract();
    _publicKey = await _keyPair!.extractPublicKey();

    await _saveKeys(privateKeyData.bytes, _publicKey!.bytes);
    print("Новые ключи сгенерированы.");
  }

  // Импорт ключа (для кнопки "Восстановить")
  // Принимает приватный ключ в Base64
  Future<void> importPrivateKey(String privateKeyB64) async {
    try {
      final privateKeyBytes = base64.decode(privateKeyB64);

      // Восстанавливаем пару из приватного ключа
      _keyPair = await keyExchangeAlgorithm.newKeyPairFromSeed(privateKeyBytes);
      final privateKeyData = await _keyPair!.extract(); // Убеждаемся, что данные валидны
      _publicKey = await _keyPair!.extractPublicKey();

      await _saveKeys(privateKeyData.bytes, _publicKey!.bytes);
      print("Ключи успешно импортированы.");
    } catch (e) {
      throw Exception("Неверный формат ключа");
    }
  }

  // Экспорт приватного ключа (для бэкапа)
  Future<String> getPrivateKeyBase64() async {
    if (_keyPair == null) throw Exception("Нет ключей");
    final data = await _keyPair!.extract();
    return base64.encode(data.bytes);
  }

  Future<void> _saveKeys(List<int> privateBytes, List<int> publicBytes) async {
    await _secureStorage.write(key: _privateKeyStoreKey, value: base64.encode(privateBytes));
    await _secureStorage.write(key: _publicKeyStoreKey, value: base64.encode(publicBytes));
  }

  // Шифрование и дешифровка (остаются без изменений)
  Future<String> encrypt(String recipientPublicKeyBase64, String message) async {
    if (_keyPair == null) throw Exception("Ключи не инициализированы!");
    final recipientPublicKey = SimplePublicKey(base64.decode(recipientPublicKeyBase64), type: KeyPairType.x25519);
    final sharedSecret = await keyExchangeAlgorithm.sharedSecretKey(keyPair: _keyPair!, remotePublicKey: recipientPublicKey);
    final messageBytes = utf8.encode(message);
    final secretBox = await symmetricCipher.encrypt(messageBytes, secretKey: sharedSecret);
    return json.encode({
      'cipherText': base64.encode(secretBox.cipherText),
      'nonce': base64.encode(secretBox.nonce),
      'mac': base64.encode(secretBox.mac.bytes),
    });
  }

  Future<String> decrypt(String senderPublicKeyBase64, String encryptedPayload) async {
    if (_keyPair == null) throw Exception("Ключи не инициализированы!");
    final senderPublicKey = SimplePublicKey(base64.decode(senderPublicKeyBase64), type: KeyPairType.x25519);
    final sharedSecret = await keyExchangeAlgorithm.sharedSecretKey(keyPair: _keyPair!, remotePublicKey: senderPublicKey);
    final payloadMap = json.decode(encryptedPayload) as Map<String, dynamic>;
    final secretBox = SecretBox(
      base64.decode(payloadMap['cipherText']!),
      nonce: base64.decode(payloadMap['nonce']!),
      mac: Mac(base64.decode(payloadMap['mac']!)),
    );
    final decryptedBytes = await symmetricCipher.decrypt(secretBox, secretKey: sharedSecret);
    return utf8.decode(decryptedBytes);
  }
}