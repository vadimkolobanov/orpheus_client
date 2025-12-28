import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/call_state_service.dart';

void main() {
  group('CallStateService (контракт глобального флага активного звонка)', () {
    test('по умолчанию isCallActive=false', () {
      expect(CallStateService.instance.isCallActive.value, isFalse);
    });

    test('setCallActive меняет значение и уведомляет слушателей только при изменении', () {
      final service = CallStateService.instance;
      // сбросим в дефолт (на случай, если тесты запускались в другом порядке)
      service.setCallActive(false);

      var notifications = 0;
      void listener() => notifications += 1;

      service.isCallActive.addListener(listener);
      addTearDown(() {
        service.isCallActive.removeListener(listener);
        service.setCallActive(false);
      });

      expect(service.isCallActive.value, isFalse);

      service.setCallActive(true);
      expect(service.isCallActive.value, isTrue);
      expect(notifications, equals(1));

      // повтор того же значения — без лишних уведомлений
      service.setCallActive(true);
      expect(notifications, equals(1));

      service.setCallActive(false);
      expect(service.isCallActive.value, isFalse);
      expect(notifications, equals(2));
    });
  });
}




