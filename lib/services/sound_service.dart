// lib/services/sound_service.dart

import 'package:audioplayers/audioplayers.dart';

class SoundService {
  // --- НАСТОЯЩИЙ SINGLETON ---
  // Приватный конструктор
  SoundService._internal() {
    // Конфигурация происходит один раз при создании
    _dialingPlayer.setReleaseMode(ReleaseMode.loop);
  }
  // Единственный экземпляр
  static final SoundService instance = SoundService._internal();
  // -------------------------

  final AudioPlayer _dialingPlayer = AudioPlayer();
  final AudioPlayer _notificationPlayer = AudioPlayer();
  bool _isDisposed = false;

  Future<void> playDialingSound() async {
    if (_isDisposed) return;
    try {
      // Устанавливаем источник каждый раз, это надежнее
      await _dialingPlayer.setSource(AssetSource('sounds/dialing.mp3'));
      await _dialingPlayer.resume();
    } catch (e) { print("Ошибка playDialingSound: $e"); }
  }

  Future<void> playConnectedSound() async {
    if (_isDisposed) return;
    try {
      await _notificationPlayer.play(AssetSource('sounds/connected.mp3'));
    } catch (e) { print("Ошибка playConnectedSound: $e"); }
  }

  Future<void> playDisconnectedSound() async {
    if (_isDisposed) return;
    try {
      await _notificationPlayer.play(AssetSource('sounds/disconnected.mp3'));
    } catch (e) { print("Ошибка playDisconnectedSound: $e"); }
  }

  Future<void> stopAllSounds() async {
    if (_isDisposed) return;
    try {
      if (_dialingPlayer.state == PlayerState.playing) {
        await _dialingPlayer.pause();
      }
      if (_notificationPlayer.state == PlayerState.playing) {
        await _notificationPlayer.stop();
      }
    } catch (e) { print("Ошибка stopAllSounds: $e"); }
  }

// Этот метод больше не нужен и удален.
// Вместо него мы можем добавить метод для освобождения ресурсов при выходе из приложения,
// но для текущей задачи это не требуется.
// Future<void> dispose() async { ... }
}