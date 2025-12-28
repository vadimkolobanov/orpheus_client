import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';

void main() {
  group('DebugLogger (контракты логирования)', () {
    setUp(() {
      DebugLogger.clear();
    });

    test('log добавляет запись и getLogsByTag фильтрует', () {
      DebugLogger.info('WS', 'hello');
      DebugLogger.error('DB', 'boom');
      DebugLogger.warn('WS', 'warn');

      expect(DebugLogger.logs, hasLength(3));
      expect(DebugLogger.getLogsByTag('WS'), hasLength(2));
      expect(DebugLogger.getLogsByTag('DB'), hasLength(1));
    });

    test('clear очищает логи', () {
      DebugLogger.info('X', '1');
      expect(DebugLogger.logs, isNotEmpty);
      DebugLogger.clear();
      expect(DebugLogger.logs, isEmpty);
    });

    test('ограничение размера: хранит не больше 1000 записей', () {
      for (var i = 0; i < 1200; i++) {
        DebugLogger.info('SPAM', 'm$i');
      }
      expect(DebugLogger.logs.length, equals(1000));
      // Должны быть последние 1000
      expect(DebugLogger.logs.first.message, equals('m200'));
      expect(DebugLogger.logs.last.message, equals('m1199'));
    });

    test('exportToText содержит заголовок и отформатированные записи', () {
      DebugLogger.success('AUTH', 'ok');
      final text = DebugLogger.exportToText();
      expect(text, contains('=== ORPHEUS DEBUG LOGS ==='));
      expect(text, contains('[✅ AUTH] ok'));
    });

    test('onUpdate эмитит событие при log/clear', () async {
      final events = <void>[];
      final sub = DebugLogger.onUpdate.listen((e) => events.add(e));

      DebugLogger.info('T', '1');
      DebugLogger.clear();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(events.length, greaterThanOrEqualTo(2));
    });
  });
}




