import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Сервис для фоновой работы во время активного звонка.
/// Держит приложение живым когда экран выключен или приложение свёрнуто.
@pragma('vm:entry-point')
class BackgroundCallService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  /// ID канала для уведомления активного звонка
  static const String _activeCallChannelId = 'orpheus_active_call';
  static const String _activeCallChannelName = 'Активный звонок';

  /// Инициализация сервиса (вызывается один раз при старте приложения)
  /// ПРИМЕЧАНИЕ: Сервис уже настроен через NotificationForegroundService,
  /// поэтому здесь только создаём канал уведомлений для звонков
  static Future<void> initialize() async {
    // Создаём канал уведомлений для активного звонка
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _activeCallChannelId,
      _activeCallChannelName,
      description: 'Уведомление во время активного защищённого звонка',
      importance: Importance.low, // Низкий приоритет - не мешает пользователю
      enableVibration: false,
      playSound: false,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    
    // НЕ настраиваем сервис здесь - он уже настроен через NotificationForegroundService
    // BackgroundCallService просто обновляет уведомление через тот же сервис
    
    print("🔊 BackgroundCallService initialized (using shared service)");
  }

  /// Обновление уведомления для активного звонка
  /// Сервис уже работает через NotificationForegroundService,
  /// просто обновляем уведомление
  static Future<void> startCallService({String? contactName}) async {
    // Сервис уже запущен через NotificationForegroundService
    // Просто обновляем уведомление
    _service.invoke('updateNotification', {
      'title': 'Orpheus',
      'content': contactName != null ? 'Звонок с $contactName' : 'Защищённый звонок активен',
    });
    print("🔊 Call notification updated for: ${contactName ?? 'Unknown'}");
  }

  /// Возврат уведомления к обычному статусу после завершения звонка
  /// Сервис продолжает работать, просто обновляем уведомление
  static Future<void> stopCallService() async {
    // Не останавливаем сервис - он должен работать постоянно
    // Просто возвращаем уведомление к обычному статусу
    _service.invoke('updateNotification', {
      'title': 'Orpheus',
      'content': 'Служба уведомлений активна',
    });
    print("🔊 Call notification reset to normal status");
  }

  /// Обновление времени звонка в уведомлении
  static void updateCallDuration(String duration) {
    _service.invoke('updateNotification', {
      'title': 'Orpheus',
      'content': 'Звонок: $duration',
    });
  }

  /// Проверка работает ли сервис
  static Future<bool> isRunning() async {
    return await _service.isRunning();
  }

  // ПРИМЕЧАНИЕ: _onStart и _onIosBackground больше не используются,
  // так как сервис управляется через NotificationForegroundService
}

