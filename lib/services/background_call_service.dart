import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Entry point для foreground/background service (должен быть top-level для стабильной работы в AOT).
@pragma('vm:entry-point')
void backgroundCallServiceOnStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  // ignore: avoid_print
  print("📞 BackgroundCallService onStart (top-level)");

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  // Обработка остановки
  service.on('stopService').listen((event) {
    // ignore: avoid_print
    print("📞 Service stopping...");
    service.stopSelf();
  });

  // Обработка обновления уведомления
  service.on('updateNotification').listen((event) {
    if (event != null && service is AndroidServiceInstance) {
      final title = event['title'] as String? ?? 'Orpheus';
      final content = event['content'] as String? ?? 'Звонок...';

      service.setForegroundNotificationInfo(
        title: title,
        content: content,
      );
    }
  });
}

/// Абстракция над плагинами, чтобы unit-тесты не зависели от MethodChannel.
abstract class BackgroundCallBackend {
  Future<void> createNotificationChannel({
    required String channelId,
    required String channelName,
    required String description,
  });

  Future<void> configure({
    required void Function(ServiceInstance service) onStart,
    required String notificationChannelId,
    required int notificationId,
  });

  Future<bool> isRunning();
  Future<void> startService();
  void invoke(String method, [Map<String, dynamic>? args]);
}

class PluginBackgroundCallBackend implements BackgroundCallBackend {
  PluginBackgroundCallBackend({
    FlutterBackgroundService? service,
    FlutterLocalNotificationsPlugin? notifications,
  })  : _service = service ?? FlutterBackgroundService(),
        _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  final FlutterBackgroundService _service;
  final FlutterLocalNotificationsPlugin _notifications;

  @override
  Future<void> createNotificationChannel({
    required String channelId,
    required String channelName,
    required String description,
  }) async {
    const channel = AndroidNotificationChannel(
      BackgroundCallService.channelId,
      BackgroundCallService.channelName,
      description: 'Уведомление во время активного звонка',
      importance: Importance.low, // Низкий приоритет - не звенит
      enableVibration: false,
      playSound: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  @override
  Future<void> configure({
    required void Function(ServiceInstance service) onStart,
    required String notificationChannelId,
    required int notificationId,
  }) async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        // Важно: flutter_background_service требует top-level или static функцию.
        // Любые лямбды/обёртки ломают запуск на Android.
        onStart: onStart,
        autoStart: false, // НЕ автозапуск — только вручную при звонке
        autoStartOnBoot: false, // НЕ запускать при загрузке
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Orpheus',
        initialNotificationContent: 'Звонок...',
        foregroundServiceNotificationId: notificationId,
        foregroundServiceTypes: [AndroidForegroundType.microphone],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );
  }

  @override
  Future<bool> isRunning() => _service.isRunning();

  @override
  Future<void> startService() => _service.startService();

  @override
  void invoke(String method, [Map<String, dynamic>? args]) => _service.invoke(method, args);
}

/// Foreground service для поддержания активного звонка.
/// Запускается ТОЛЬКО на время звонка, останавливается после.
/// Не работает постоянно — не мешает пользователю.
class BackgroundCallService {
  static bool _isInitialized = false;

  /// ID канала для уведомления активного звонка
  static const String channelId = 'orpheus_active_call';
  static const String channelName = 'Активный звонок';
  static const int _notificationId = 888;

  static BackgroundCallBackend _backend = PluginBackgroundCallBackend();

  /// Для unit-тестов: подменить backend, чтобы не дергать плагины.
  static void debugSetBackendForTesting(BackgroundCallBackend? backend) {
    _backend = backend ?? PluginBackgroundCallBackend();
  }

  /// Для unit-тестов: сбросить инициализацию, чтобы тесты не зависели от порядка запуска.
  static void debugResetForTesting() {
    _isInitialized = false;
  }

  /// Инициализация сервиса (вызывается один раз)
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Создаём канал уведомлений с низким приоритетом (не мешает)
      await _backend.createNotificationChannel(
        channelId: channelId,
        channelName: channelName,
        description: 'Уведомление во время активного звонка',
      );

      // Конфигурация сервиса
      await _backend.configure(
        onStart: backgroundCallServiceOnStart,
        notificationChannelId: channelId,
        notificationId: _notificationId,
      );

      _isInitialized = true;
      print("📞 BackgroundCallService initialized");
    } catch (e) {
      // Важно: сервис должен быть best-effort — не валим приложение.
      print("📞 ERROR: BackgroundCallService init failed: $e");
    }
  }

  /// Запуск сервиса при начале звонка
  static Future<void> startCallService() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (!await _backend.isRunning()) {
        await _backend.startService();
        print("📞 Call service STARTED");
      }
    } catch (e) {
      print("📞 ERROR: startCallService failed: $e");
    }
  }

  /// Остановка сервиса при завершении звонка
  static Future<void> stopCallService() async {
    try {
      if (await _backend.isRunning()) {
        _backend.invoke("stopService");
        print("📞 Call service STOPPED");
      }
    } catch (e) {
      print("📞 ERROR: stopCallService failed: $e");
    }
  }

  /// Обновление времени звонка в уведомлении
  static void updateCallDuration(String duration, String contactName) {
    try {
      _backend.invoke('updateNotification', {
        'title': contactName,
        'content': 'Звонок: $duration',
      });
    } catch (e) {
      print("📞 ERROR: updateCallDuration failed: $e");
    }
  }

}
