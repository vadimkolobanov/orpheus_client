import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/models/security_config.dart';
import 'package:orpheus_project/services/panic_wipe_service.dart';

class _FakeAuth implements PanicWipeAuth {
  _FakeAuth({required this.config, Future<void> Function()? performWipe})
      : _performWipe = performWipe;

  @override
  SecurityConfig config;

  int wipeCalls = 0;
  final Future<void> Function()? _performWipe;

  @override
  Future<void> performWipe() async {
    wipeCalls += 1;
    final fn = _performWipe;
    if (fn != null) {
      await fn();
    }
  }
}

void main() {
  group('PanicWipeService (контракт: 3 быстрых ухода в фон)', () {
    test('когда жест выключен — уходы в фон не триггерят wipe', () async {
      final auth = _FakeAuth(config: const SecurityConfig(isPanicGestureEnabled: false));
      var now = DateTime.utc(2025, 1, 27, 12, 0, 0);
      final service = PanicWipeService.createForTesting(auth: auth, now: () => now);

      var callbackCalls = 0;
      service.onPanicWipe = () async {
        callbackCalls += 1;
      };

      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 1));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 1));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);

      await Future<void>.delayed(Duration.zero);
      expect(auth.wipeCalls, equals(0));
      expect(callbackCalls, equals(0));
    });

    test('3 паузы подряд в пределах окна (<=3s между событиями) → wipe и callback', () async {
      final auth = _FakeAuth(config: const SecurityConfig(isPanicGestureEnabled: true));
      var now = DateTime.utc(2025, 1, 27, 12, 0, 0);
      final service = PanicWipeService.createForTesting(auth: auth, now: () => now);

      var callbackCalls = 0;
      service.onPanicWipe = () async {
        callbackCalls += 1;
      };

      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 1));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 2));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);

      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(auth.wipeCalls, equals(1));
      expect(callbackCalls, equals(1));
    });

    test('разрыв >3s ломает паттерн; wipe срабатывает только когда есть 3 подряд в окне', () async {
      final auth = _FakeAuth(config: const SecurityConfig(isPanicGestureEnabled: true));
      var now = DateTime.utc(2025, 1, 27, 12, 0, 0);
      final service = PanicWipeService.createForTesting(auth: auth, now: () => now);

      // t=0
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      // t=4 (разрыв)
      now = now.add(const Duration(seconds: 4));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      // t=5
      now = now.add(const Duration(seconds: 1));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);

      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(auth.wipeCalls, equals(0));

      // t=6: теперь последние 3 события (4,5,6) подряд и в окне → wipe
      now = now.add(const Duration(seconds: 1));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);

      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(auth.wipeCalls, equals(1));
    });

    test('защита от повторного срабатывания: пока wipe не завершён — новые паузы игнорируются', () async {
      final completer = Completer<void>();
      final auth = _FakeAuth(
        config: const SecurityConfig(isPanicGestureEnabled: true),
        performWipe: () => completer.future,
      );
      var now = DateTime.utc(2025, 1, 27, 12, 0, 0);
      final service = PanicWipeService.createForTesting(auth: auth, now: () => now);

      var callbackCalls = 0;
      service.onPanicWipe = () async {
        callbackCalls += 1;
      };

      // Триггерим wipe
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 1));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 1));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);

      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(auth.wipeCalls, equals(1));
      expect(callbackCalls, equals(0)); // callback после завершения wipe

      // Пока wipe не завершён — дополнительные паузы не должны вызывать новый wipe
      now = now.add(const Duration(seconds: 1));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 1));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(auth.wipeCalls, equals(1));

      completer.complete();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(callbackCalls, equals(1));
    });

    test('manual trigger: triggerManualWipe вызывает wipe независимо от флага жеста', () async {
      final auth = _FakeAuth(config: const SecurityConfig(isPanicGestureEnabled: false));
      final service = PanicWipeService.createForTesting(auth: auth);

      var callbackCalls = 0;
      service.onPanicWipe = () async {
        callbackCalls += 1;
      };

      await service.triggerManualWipe();
      expect(auth.wipeCalls, equals(1));
      expect(callbackCalls, equals(1));
    });
  });
}


