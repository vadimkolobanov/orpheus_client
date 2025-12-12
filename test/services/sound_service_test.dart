import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    
    // Мокаем MethodChannel для audioplayers
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async {
        // Возвращаем успешный ответ для всех методов
        if (methodCall.method == 'play' || 
            methodCall.method == 'setSource' || 
            methodCall.method == 'resume' || 
            methodCall.method == 'pause' || 
            methodCall.method == 'stop' ||
            methodCall.method == 'getDuration' ||
            methodCall.method == 'getCurrentPosition' ||
            methodCall.method == 'setReleaseMode') {
          return null;
        }
        if (methodCall.method == 'getState') {
          return 'completed';
        }
        return null;
      },
    );
    
    // Мокаем глобальный канал audioplayers
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'init') {
          return null;
        }
        return null;
      },
    );
    
    // Мокаем path_provider (используется audioplayers)
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getTemporaryDirectory') {
          return '/tmp';
        }
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return '/tmp';
        }
        return null;
      },
    );
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    
    // Очищаем моки после каждого теста
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  group('SoundService Tests', () {
    test('SoundService - Singleton паттерн', () {
      final instance1 = SoundService.instance;
      final instance2 = SoundService.instance;

      expect(instance1, same(instance2));
      expect(instance1, isA<SoundService>());
    });

    test('Методы воспроизведения не выбрасывают исключения', () async {
      final service = SoundService.instance;

      // С моками эти методы должны работать без ошибок
      await service.playDialingSound();
      await service.playConnectedSound();
      await service.playDisconnectedSound();
      
      expect(service, isNotNull);
    });

    test('Остановка всех звуков безопасна', () async {
      final service = SoundService.instance;

      await service.stopAllSounds();
      expect(service, isNotNull);
    });

    test('Множественные вызовы методов безопасны', () async {
      final service = SoundService.instance;

      // Множественные вызовы не должны вызывать ошибки
      await service.playDialingSound();
      await service.playDialingSound();
      await service.stopAllSounds();
      await service.stopAllSounds();

      expect(service, isNotNull);
    });
  });
}

