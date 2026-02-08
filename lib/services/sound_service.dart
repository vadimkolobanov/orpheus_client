// lib/services/sound_service.dart

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Минимальный контракт для звукового бэкенда.
///
/// Важно: в тестах мы подменяем бэкенд на in-memory fake, чтобы проверять,
/// что SoundService действительно вызывает нужные действия (а не просто "не падает").
abstract class SoundBackend {
  Future<void> playDialing();
  Future<void> playIncomingRingtone();
  Future<void> playConnected();
  Future<void> playDisconnected();
  Future<void> stopAll();
}

class NoopSoundBackend implements SoundBackend {
  @override
  Future<void> playDialing() async {}

  @override
  Future<void> playIncomingRingtone() async {}

  @override
  Future<void> playConnected() async {}

  @override
  Future<void> playDisconnected() async {}

  @override
  Future<void> stopAll() async {}
}

class AudioplayersSoundBackend implements SoundBackend {
  AudioplayersSoundBackend({
    Duration timeout = const Duration(seconds: 2),
  }) : _timeout = timeout;

  final Duration _timeout;

  AudioPlayer? _dialingPlayer;
  AudioPlayer? _notificationPlayer;

  void _ensurePlayers() {
    if (_dialingPlayer != null && _notificationPlayer != null) return;
    try {
      _dialingPlayer = AudioPlayer();
      _notificationPlayer = AudioPlayer();
      unawaited(_dialingPlayer!.setReleaseMode(ReleaseMode.loop).catchError((_) {}));
    } catch (_) {
      // best-effort: звук не должен валить приложение
      _dialingPlayer = null;
      _notificationPlayer = null;
    }
  }

  @override
  Future<void> playDialing() async {
    _ensurePlayers();
    final dialing = _dialingPlayer;
    if (dialing == null) return;
    try {
      // Устанавливаем источник каждый раз, это надежнее
      // Важно: AssetSource ожидает путь ОТНОСИТЕЛЬНО assets/ (сам добавляет префикс).
      // Поэтому тут должно быть 'sounds/...' а не 'assets/sounds/...'
      await dialing.setSource(AssetSource('sounds/dialing.mp3')).timeout(_timeout);
      await dialing.resume().timeout(_timeout);
    } catch (e) {
      // best-effort, но логируем для диагностики (эмулятор/устройство)
      // ignore: avoid_print
      print('SOUND: playDialing failed: $e');
    }
  }

  @override
  Future<void> playIncomingRingtone() async {
    _ensurePlayers();
    final dialing = _dialingPlayer;
    if (dialing == null) return;
    try {
      // Рингтон входящего звонка — отдельный ассет.
      // По умолчанию в репо он может быть копией dialing.mp3 (позже можно заменить).
      await dialing.setSource(AssetSource('sounds/ringtone.mp3')).timeout(_timeout);
      await dialing.resume().timeout(_timeout);
    } catch (e) {
      // ignore: avoid_print
      print('SOUND: playIncomingRingtone failed: $e');
    }
  }

  @override
  Future<void> playConnected() async {
    _ensurePlayers();
    final notif = _notificationPlayer;
    if (notif == null) return;
    try {
      await notif.play(AssetSource('sounds/connected.mp3')).timeout(_timeout);
    } catch (e) {
      // ignore: avoid_print
      print('SOUND: playConnected failed: $e');
    }
  }

  @override
  Future<void> playDisconnected() async {
    _ensurePlayers();
    final notif = _notificationPlayer;
    if (notif == null) return;
    try {
      await notif.play(AssetSource('sounds/disconnected.mp3')).timeout(_timeout);
    } catch (e) {
      // ignore: avoid_print
      print('SOUND: playDisconnected failed: $e');
    }
  }

  @override
  Future<void> stopAll() async {
    _ensurePlayers();
    final dialing = _dialingPlayer;
    final notif = _notificationPlayer;
    if (dialing == null || notif == null) return;
    try {
      if (dialing.state == PlayerState.playing) {
        await dialing.pause().timeout(_timeout);
      }
      if (notif.state == PlayerState.playing) {
        await notif.stop().timeout(_timeout);
      }
    } catch (e) {
      // ignore: avoid_print
      print('SOUND: stopAll failed: $e');
    }
  }
}

class SoundService {
  // --- НАСТОЯЩИЙ SINGLETON ---
  // Приватный конструктор
  SoundService._internal() : _backend = _defaultBackend();
  // Единственный экземпляр
  static final SoundService instance = SoundService._internal();
  // -------------------------

  SoundBackend _backend;
  bool _isDisposed = false;

  bool get _supportsAudioPlatform {
    const isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
    return !isFlutterTest &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
  }

  static SoundBackend _defaultBackend() {
    const isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
    if (isFlutterTest) return NoopSoundBackend();
    if (kIsWeb) return NoopSoundBackend();
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return NoopSoundBackend();
    }
    return AudioplayersSoundBackend();
  }

  @visibleForTesting
  static void debugSetBackendForTesting(SoundBackend? backend) {
    instance._backend = backend ?? _defaultBackend();
  }

  Future<void> playDialingSound() async {
    if (_isDisposed) return;
    try {
      await _backend.playDialing();
    } catch (e) {
      // best-effort: звук не должен валить приложение
      print("Error playDialingSound: $e");
    }
  }

  Future<void> playIncomingRingtone() async {
    if (_isDisposed) return;
    try {
      await _backend.playIncomingRingtone();
    } catch (e) {
      print("Error playIncomingRingtone: $e");
    }
  }

  Future<void> playConnectedSound() async {
    if (_isDisposed) return;
    try {
      await _backend.playConnected();
    } catch (e) {
      print("Error playConnectedSound: $e");
    }
  }

  Future<void> playDisconnectedSound() async {
    if (_isDisposed) return;
    try {
      await _backend.playDisconnected();
    } catch (e) {
      print("Error playDisconnectedSound: $e");
    }
  }

  Future<void> stopAllSounds() async {
    if (_isDisposed) return;
    try {
      await _backend.stopAll();
    } catch (e) {
      print("Error stopAllSounds: $e");
    }
  }

// Этот метод больше не нужен и удален.
// Вместо него мы можем добавить метод для освобождения ресурсов при выходе из приложения,
// но для текущей задачи это не требуется.
// Future<void> dispose() async { ... }
}