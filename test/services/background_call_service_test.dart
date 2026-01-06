import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:orpheus_project/services/background_call_service.dart';

class _FakeBackend implements BackgroundCallBackend {
  int createChannelCalls = 0;
  int configureCalls = 0;
  int isRunningCalls = 0;
  int startCalls = 0;
  final invoked = <({String method, Map<String, dynamic>? args})>[];

  bool running = false;

  Object? throwOnCreateChannel;
  Object? throwOnConfigure;
  Object? throwOnIsRunning;
  Object? throwOnStart;
  Object? throwOnInvoke;

  @override
  Future<void> createNotificationChannel({
    required String channelId,
    required String channelName,
    required String description,
  }) async {
    createChannelCalls += 1;
    if (throwOnCreateChannel != null) throw throwOnCreateChannel!;
  }

  @override
  Future<void> configure({
    required void Function(ServiceInstance service) onStart,
    required String notificationChannelId,
    required int notificationId,
  }) async {
    configureCalls += 1;
    if (throwOnConfigure != null) throw throwOnConfigure!;
  }

  @override
  Future<bool> isRunning() async {
    isRunningCalls += 1;
    if (throwOnIsRunning != null) throw throwOnIsRunning!;
    return running;
  }

  @override
  Future<void> startService() async {
    startCalls += 1;
    if (throwOnStart != null) throw throwOnStart!;
    running = true;
  }

  @override
  void invoke(String method, [Map<String, dynamic>? args]) {
    if (throwOnInvoke != null) throw throwOnInvoke!;
    invoked.add((method: method, args: args));
  }
}

void main() {
  group('BackgroundCallService (контракт foreground service на время звонка)', () {
    late _FakeBackend backend;

    setUp(() {
      backend = _FakeBackend();
      BackgroundCallService.debugSetBackendForTesting(backend);
      BackgroundCallService.debugResetForTesting();
    });

    tearDown(() {
      BackgroundCallService.debugSetBackendForTesting(null);
      BackgroundCallService.debugResetForTesting();
    });

    test('initialize идемпотентен: channel+configure вызываются один раз', () async {
      await BackgroundCallService.initialize();
      await BackgroundCallService.initialize();

      expect(backend.createChannelCalls, equals(1));
      expect(backend.configureCalls, equals(1));
    });

    test('startCallService: если не running — стартует сервис', () async {
      backend.running = false;
      await BackgroundCallService.startCallService();

      expect(backend.createChannelCalls, equals(1));
      expect(backend.configureCalls, equals(1));
      expect(backend.startCalls, equals(1));
      expect(backend.running, isTrue);
    });

    test('startCallService: если уже running — не стартует повторно', () async {
      backend.running = true;
      await BackgroundCallService.startCallService();

      expect(backend.startCalls, equals(0));
      // При первом вызове всё равно происходит initialize, потому что _isInitialized был false.
      expect(backend.configureCalls, equals(1));
    });

    test('stopCallService: если running — вызывает stopService', () async {
      backend.running = true;
      await BackgroundCallService.stopCallService();

      expect(backend.invoked.where((e) => e.method == 'stopService').length, equals(1));
    });

    test('stopCallService: если не running — ничего не вызывает', () async {
      backend.running = false;
      await BackgroundCallService.stopCallService();

      expect(backend.invoked, isEmpty);
    });

    test('updateCallDuration отправляет updateNotification с title/content', () async {
      BackgroundCallService.updateCallDuration('00:12', 'Alice');
      expect(backend.invoked, hasLength(1));
      expect(backend.invoked.single.method, equals('updateNotification'));
      expect(backend.invoked.single.args, equals({'title': 'Alice', 'content': 'Звонок: 00:12'}));
    });

    test('ошибки backend не должны пробрасываться наружу (best-effort)', () async {
      backend.throwOnCreateChannel = StateError('boom:create');
      backend.throwOnConfigure = StateError('boom:configure');
      backend.throwOnIsRunning = StateError('boom:isRunning');
      backend.throwOnStart = StateError('boom:start');
      backend.throwOnInvoke = StateError('boom:invoke');

      // Ничего из этого не должно падать
      await BackgroundCallService.initialize();
      await BackgroundCallService.startCallService();
      await BackgroundCallService.stopCallService();
      BackgroundCallService.updateCallDuration('00:01', 'Bob');
    });
  });
}


