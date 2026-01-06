import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/sound_service.dart';

class _FakeSoundBackend implements SoundBackend {
  int playDialingCalls = 0;
  int playIncomingRingtoneCalls = 0;
  int playConnectedCalls = 0;
  int playDisconnectedCalls = 0;
  int stopAllCalls = 0;

  Object? throwOnDialing;
  Object? throwOnStopAll;

  @override
  Future<void> playDialing() async {
    playDialingCalls += 1;
    if (throwOnDialing != null) throw throwOnDialing!;
  }

  @override
  Future<void> playIncomingRingtone() async {
    playIncomingRingtoneCalls += 1;
  }

  @override
  Future<void> playConnected() async {
    playConnectedCalls += 1;
  }

  @override
  Future<void> playDisconnected() async {
    playDisconnectedCalls += 1;
  }

  @override
  Future<void> stopAll() async {
    stopAllCalls += 1;
    if (throwOnStopAll != null) throw throwOnStopAll!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSoundBackend backend;

  setUp(() {
    backend = _FakeSoundBackend();
    SoundService.debugSetBackendForTesting(backend);
  });

  tearDown(() {
    SoundService.debugSetBackendForTesting(null);
  });

  group('SoundService Tests', () {
    test('SoundService - Singleton паттерн', () {
      final instance1 = SoundService.instance;
      final instance2 = SoundService.instance;

      expect(instance1, same(instance2));
      expect(instance1, isA<SoundService>());
    });

    test('play*: вызывает backend (это ловит регрессии логики вызовов)', () async {
      final service = SoundService.instance;

      await service.playDialingSound();
      await service.playIncomingRingtone();
      await service.playConnectedSound();
      await service.playDisconnectedSound();

      expect(backend.playDialingCalls, equals(1));
      expect(backend.playIncomingRingtoneCalls, equals(1));
      expect(backend.playConnectedCalls, equals(1));
      expect(backend.playDisconnectedCalls, equals(1));
    });

    test('stopAllSounds: вызывает backend.stopAll', () async {
      final service = SoundService.instance;

      await service.stopAllSounds();
      expect(backend.stopAllCalls, equals(1));
    });

    test('Множественные вызовы методов безопасны', () async {
      final service = SoundService.instance;

      // Множественные вызовы не должны вызывать ошибки
      await service.playDialingSound();
      await service.playDialingSound();
      await service.playIncomingRingtone();
      await service.stopAllSounds();
      await service.stopAllSounds();

      expect(backend.playDialingCalls, equals(2));
      expect(backend.playIncomingRingtoneCalls, equals(1));
      expect(backend.stopAllCalls, equals(2));
    });

    test('Ошибки backend не должны пробрасываться наружу (best-effort)', () async {
      backend.throwOnDialing = StateError('boom');
      backend.throwOnStopAll = StateError('boom');

      final service = SoundService.instance;

      await service.playDialingSound(); // не должно упасть
      await service.stopAllSounds(); // не должно упасть
    });
  });
}

