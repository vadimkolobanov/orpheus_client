// lib/services/crypto_service.dart

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  final _secureStorage = const FlutterSecureStorage();

  // ИЗМЕНЕНИЕ: Нам нужно хранить приватную и публичную части ключа отдельно,
  // чтобы правильно восстановить пару.
  static const _privateKeyStoreKey = 'orpheus_private_key_data';
  static const _publicKeyStoreKey = 'orpheus_public_key_data';

  final keyExchangeAlgorithm = X25519();
  final symmetricCipher = Chacha20.poly1305Aead();

  SimpleKeyPair? _keyPair;
  SimplePublicKey? _publicKey;

  String? get publicKeyBase64 => _publicKey != null ? base64.encode(_publicKey!.bytes) : null;

  Future<void> init() async {
    // Пытаемся загрузить обе части ключа из хранилища
    final privateKeyB64 = await _secureStorage.read(key: _privateKeyStoreKey);
    final publicKeyB64 = await _secureStorage.read(key: _publicKeyStoreKey);

    if (privateKeyB64 != null && publicKeyB64 != null) {
      // Если обе части найдены, восстанавливаем из них пару
      final privateKeyBytes = base64.decode(privateKeyB64);
      final publicKeyBytes = base64.decode(publicKeyB64);

      // 1. Сначала создаем объект публичного ключа
      _publicKey = SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.x25519,
      );

      // 2. Затем, используя его, создаем полную пару ключей.
      //    ЭТО И ЕСТЬ ИСПРАВЛЕНИЕ, которого требовал компилятор.
      _keyPair = SimpleKeyPairData(
        privateKeyBytes,
        publicKey: _publicKey!, // Передаем обязательный именованный параметр `publicKey`
        type: KeyPairType.x25519,
      );
      print("Ключи X25519 успешно загружены из хранилища.");

    } else {
      // Если хотя бы одной части нет, генерируем все заново
      _keyPair = await keyExchangeAlgorithm.newKeyPair();

      // Извлекаем обе части
      final privateKeyData = await _keyPair!.extract();
      _publicKey = await _keyPair!.extractPublicKey();

      // Сохраняем обе части в хранилище по разным ключам
      await _secureStorage.write(
        key: _privateKeyStoreKey,
        value: base64.encode(privateKeyData.bytes),
      );
      await _secureStorage.write(
        key: _publicKeyStoreKey,
        value: base64.encode(_publicKey!.bytes),
      );
      print("Новые ключи X25519 сгенерированы и сохранены.");
    }
  }

  // Методы encrypt и decrypt остаются БЕЗ ИЗМЕНЕНИЙ. Они были написаны правильно.

  Future<String> encrypt(String recipientPublicKeyBase64, String message) async {
    if (_keyPair == null) throw Exception("Ключи не инициализированы!");

    final recipientPublicKey = SimplePublicKey(
      base64.decode(recipientPublicKeyBase64),
      type: KeyPairType.x25519,
    );

    final sharedSecret = await keyExchangeAlgorithm.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: recipientPublicKey,
    );

    final messageBytes = utf8.encode(message);

    final secretBox = await symmetricCipher.encrypt(
      messageBytes,
      secretKey: sharedSecret,
    );

    final payloadMap = {
      'cipherText': base64.encode(secretBox.cipherText),
      'nonce': base64.encode(secretBox.nonce),
      'mac': base64.encode(secretBox.mac.bytes),
    };

    return json.encode(payloadMap);
  }

  Future<String> decrypt(String senderPublicKeyBase64, String encryptedPayload) async {
    if (_keyPair == null) throw Exception("Ключи не инициализированы!");

    final senderPublicKey = SimplePublicKey(
      base64.decode(senderPublicKeyBase64),
      type: KeyPairType.x25519,
    );

    final sharedSecret = await keyExchangeAlgorithm.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: senderPublicKey,
    );

    final payloadMap = json.decode(encryptedPayload) as Map<String, dynamic>;
    final secretBox = SecretBox(
      base64.decode(payloadMap['cipherText']!),
      nonce: base64.decode(payloadMap['nonce']!),
      mac: Mac(base64.decode(payloadMap['mac']!)),
    );

    final decryptedBytes = await symmetricCipher.decrypt(
      secretBox,
      secretKey: sharedSecret,
    );

    return utf8.decode(decryptedBytes);
  }
}