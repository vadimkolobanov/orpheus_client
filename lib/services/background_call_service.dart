import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Foreground service для поддержания активного звонка.
/// Запускается ТОЛЬКО на время звонка, останавливается после.
/// Не работает постоянно — не мешает пользователю.
class BackgroundCallService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static bool _isInitialized = false;

  /// ID канала для уведомления активного звонка
  static const String _channelId = 'orpheus_active_call';
  static const String _channelName = 'Активный звонок';
  static const int _notificationId = 888;

  /// Инициализация сервиса (вызывается один раз)
  static Future<void> initialize() async {
    if (_isInitialized) return;

    // Создаём канал уведомлений с низким приоритетом (не мешает)
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Уведомление во время активного звонка',
      importance: Importance.low,  // Низкий приоритет - не звенит
      enableVibration: false,
      playSound: false,
    );

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Конфигурация сервиса
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,  // НЕ автозапуск — только вручную при звонке
        autoStartOnBoot: false,  // НЕ запускать при загрузке
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'Orpheus',
        initialNotificationContent: 'Звонок...',
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: [AndroidForegroundType.microphone],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
      ),
    );

    _isInitialized = true;
    print("📞 BackgroundCallService initialized");
  }

  /// Запуск сервиса при начале звонка
  static Future<void> startCallService() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    if (!await _service.isRunning()) {
      await _service.startService();
      print("📞 Call service STARTED");
    }
  }

  /// Остановка сервиса при завершении звонка
  static Future<void> stopCallService() async {
    if (await _service.isRunning()) {
      _service.invoke("stopService");
      print("📞 Call service STOPPED");
    }
  }

  /// Обновление времени звонка в уведомлении
  static void updateCallDuration(String duration, String contactName) {
    _service.invoke('updateNotification', {
      'title': contactName,
      'content': 'Звонок: $duration',
    });
  }

  /// Entry point для foreground service
  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    print("📞 BackgroundCallService _onStart");

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    // Обработка остановки
    service.on('stopService').listen((event) {
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
}
