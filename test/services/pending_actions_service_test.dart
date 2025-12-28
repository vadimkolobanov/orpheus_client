import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/pending_actions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ThrowingPrefs implements PendingActionsPrefs {
  @override
  List<String>? getStringList(String key) => throw StateError('boom:get');

  @override
  Future<bool> setStringList(String key, List<String> value) async => throw StateError('boom:set');

  @override
  Future<bool> remove(String key) async => throw StateError('boom:remove');
}

void main() {
  group('PendingActionsService (контракт отложенных отклонений звонков)', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      PendingActionsService.debugSetPrefsProviderForTesting(null);
    });

    tearDown(() {
      PendingActionsService.debugSetPrefsProviderForTesting(null);
    });

    test('по умолчанию pending список пустой', () async {
      final list = await PendingActionsService.getPendingRejections();
      expect(list, isEmpty);
    });

    test('addPendingRejection сохраняет ключ; getPendingRejections возвращает сохранённое', () async {
      await PendingActionsService.addPendingRejection('CALLER_A');
      final list = await PendingActionsService.getPendingRejections();
      expect(list, equals(['CALLER_A']));
    });

    test('addPendingRejection не добавляет дубликаты и не меняет порядок', () async {
      await PendingActionsService.addPendingRejection('CALLER_A');
      await PendingActionsService.addPendingRejection('CALLER_A');
      await PendingActionsService.addPendingRejection('CALLER_B');
      await PendingActionsService.addPendingRejection('CALLER_A');

      final list = await PendingActionsService.getPendingRejections();
      expect(list, equals(['CALLER_A', 'CALLER_B']));
    });

    test('removePendingRejection удаляет элемент; повторное удаление безопасно', () async {
      await PendingActionsService.addPendingRejection('CALLER_A');
      await PendingActionsService.addPendingRejection('CALLER_B');

      await PendingActionsService.removePendingRejection('CALLER_A');
      var list = await PendingActionsService.getPendingRejections();
      expect(list, equals(['CALLER_B']));

      await PendingActionsService.removePendingRejection('CALLER_A');
      list = await PendingActionsService.getPendingRejections();
      expect(list, equals(['CALLER_B']));
    });

    test('clearAllPendingRejections очищает всё', () async {
      await PendingActionsService.addPendingRejection('CALLER_A');
      await PendingActionsService.addPendingRejection('CALLER_B');

      await PendingActionsService.clearAllPendingRejections();
      final list = await PendingActionsService.getPendingRejections();
      expect(list, isEmpty);
    });

    test('ошибки хранилища не должны падать наружу (best-effort)', () async {
      PendingActionsService.debugSetPrefsProviderForTesting(() async => _ThrowingPrefs());

      await PendingActionsService.addPendingRejection('CALLER_A'); // не должно бросать
      final list = await PendingActionsService.getPendingRejections(); // не должно бросать
      expect(list, isEmpty);
      await PendingActionsService.removePendingRejection('CALLER_A'); // не должно бросать
      await PendingActionsService.clearAllPendingRejections(); // не должно бросать
    });
  });
}


