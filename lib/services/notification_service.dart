// lib/services/notification_service.dart

import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';

/// Обработчик фоновых FCM сообщений (top-level функция)
/// Вызывается когда приложение убито или в фоне
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("📱 FCM BACKGROUND: ${message.messageId}");
  DebugLogger.info('FCM', 'BACKGROUND: ${message.messageId}');
  
  // FCM сам показывает уведомление если есть notification payload
  // Для data-only сообщений можно показать локальное уведомление
  final data = message.data;
  if (data.containsKey('type')) {
    DebugLogger.info('FCM', 'Background message type: ${data['type']}');
    await NotificationService._handleBackgroundMessage(data);
  }
}

class NotificationService {
  // Singleton
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static FlutterLocalNotificationsPlugin? _localNotifications;

  /// FCM токен для отправки на сервер
  String? fcmToken;

  /// Callbacks для обработки событий
  static VoidCallback? onTokenUpdated;
  static Function(String callerKey)? onIncomingCallFromPush;

  // ID каналов уведомлений
  static const String _callChannelId = 'orpheus_calls';
  static const String _callChannelName = 'Входящие звонки';
  static const String _messageChannelId = 'orpheus_messages';
  static const String _messageChannelName = 'Сообщения';

  // Notification IDs
  static const int _callNotificationId = 1001;
  static const int _messageNotificationId = 1002;

  /// Инициализация сервиса
  Future<void> init() async {
    // 1. Инициализация локальных уведомлений
    await _initLocalNotifications();

    // 2. Запрос разрешений FCM
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,  // Важно для звонков
      provisional: false,
    );
    print('📱 FCM Permission: ${settings.authorizationStatus}');
    DebugLogger.info('FCM', 'Permission: ${settings.authorizationStatus}');

    // 3. Получение токена
    try {
      fcmToken = await _firebaseMessaging.getToken();
      print("📱 FCM Token: $fcmToken");
      DebugLogger.success('FCM', 'Token получен: ${fcmToken?.substring(0, 30)}...');

      // Подписка на обновление токена
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        fcmToken = newToken;
        print("📱 FCM Token updated: $newToken");
        DebugLogger.info('FCM', 'Token обновлён: ${newToken.substring(0, 30)}...');
        onTokenUpdated?.call();
      });
    } catch (e) {
      print("📱 FCM Error: $e");
      DebugLogger.error('FCM', 'Ошибка получения токена: $e');
    }

    // 4. Обработка foreground сообщений
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 5. Обработка клика по уведомлению
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // 6. Проверка начального сообщения (если приложение открыто из уведомления)
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  /// Инициализация локальных уведомлений
  static Future<void> _initLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();

    // Создаём каналы уведомлений
    final androidPlugin = _localNotifications!
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    // Канал для звонков - максимальный приоритет
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _callChannelId,
        _callChannelName,
        description: 'Уведомления о входящих звонках',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFF6AD394),
      ),
    );

    // Канал для сообщений - высокий приоритет
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _messageChannelId,
        _messageChannelName,
        description: 'Уведомления о новых сообщениях',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    // Инициализация
    await _localNotifications!.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    print("🔔 Local notifications initialized");
  }

  /// Обработка foreground FCM сообщений
  void _handleForegroundMessage(RemoteMessage message) {
    print('📱 FCM Foreground: ${message.notification?.title}');
    
    // Если приложение открыто - FCM не показывает уведомление автоматически
    // Можно показать локальное уведомление если нужно
    final data = message.data;
    if (data.containsKey('type') && data['type'] == 'call') {
      // Для звонков можно показать уведомление даже в foreground
      // (но обычно экран звонка уже открывается через WebSocket)
    }
  }

  /// Обработка фоновых data-only сообщений
  static Future<void> _handleBackgroundMessage(Map<String, dynamic> data) async {
    // Обеспечиваем инициализацию локальных уведомлений
    if (_localNotifications == null) {
      await _initLocalNotifications();
    }

    final type = data['type'];
    final senderName = data['sender_name'] ?? 'Неизвестный';

    if (type == 'call') {
      await showCallNotification(callerName: senderName);
    } else if (type == 'message') {
      await showMessageNotification(senderName: senderName);
    }
  }

  /// Обработка клика по уведомлению FCM
  void _handleNotificationTap(RemoteMessage message) {
    print('📱 Notification tap: ${message.data}');
    
    final data = message.data;
    if (data.containsKey('caller_key')) {
      onIncomingCallFromPush?.call(data['caller_key']);
    }
  }

  /// Обработка клика по локальному уведомлению
  static void _onNotificationTap(NotificationResponse response) {
    print('🔔 Local notification tap: ${response.payload}');
    // Можно добавить навигацию к чату/звонку по payload
  }

  // ==================== ПУБЛИЧНЫЕ МЕТОДЫ ====================

  /// Показать уведомление о входящем звонке
  /// Простое, без кнопок, со звуком и вибрацией
  static Future<void> showCallNotification({
    required String callerName,
  }) async {
    try {
      if (_localNotifications == null) {
        await _initLocalNotifications();
      }

      const androidDetails = AndroidNotificationDetails(
        _callChannelId,
        _callChannelName,
        channelDescription: 'Входящий звонок',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,  // Не смахивается
        autoCancel: false,
        showWhen: false,
        enableVibration: true,
        playSound: true,
        // Без кнопок actions!
      );

      await _localNotifications!.show(
        _callNotificationId,
        'Входящий звонок',
        callerName,
        const NotificationDetails(android: androidDetails),
      );

      print("🔔 Call notification shown: $callerName");
      DebugLogger.success('NOTIF', '🔔 Показано уведомление о звонке: $callerName');
    } catch (e) {
      print("🔔 showCallNotification error: $e");
      DebugLogger.error('NOTIF', 'showCallNotification ошибка: $e');
    }
  }

  /// Скрыть уведомление о звонке
  static Future<void> hideCallNotification() async {
    try {
      await _localNotifications?.cancel(_callNotificationId);
      print("🔔 Call notification hidden");
      DebugLogger.info('NOTIF', '🔔 Уведомление о звонке скрыто');
    } catch (e) {
      // ProGuard/R8 может вызывать ошибки с Gson TypeToken
      // Логируем но не бросаем исключение
      print("🔔 hideCallNotification error (ignored): $e");
      DebugLogger.warn('NOTIF', 'hideCallNotification ошибка (игнорируем): $e');
    }
  }

  /// Показать уведомление о новом сообщении
  /// Содержимое сообщения НЕ показывается для приватности
  static Future<void> showMessageNotification({
    required String senderName,
  }) async {
    try {
      if (_localNotifications == null) {
        await _initLocalNotifications();
      }

      final androidDetails = AndroidNotificationDetails(
        _messageChannelId,
        _messageChannelName,
        channelDescription: 'Новое сообщение',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        // Группировка сообщений от одного контакта
        groupKey: 'orpheus_messages_group',
      );

      await _localNotifications!.show(
        _messageNotificationId + senderName.hashCode % 1000,  // Уникальный ID для разных отправителей
        senderName,
        'Новое сообщение',  // Не показываем содержимое для приватности
        NotificationDetails(android: androidDetails),
      );

      print("🔔 Message notification shown: $senderName");
      DebugLogger.success('NOTIF', '📩 Показано уведомление: $senderName');
    } catch (e) {
      print("🔔 showMessageNotification error: $e");
      DebugLogger.error('NOTIF', 'showMessageNotification ошибка: $e');
    }
  }

  /// Скрыть все уведомления о сообщениях
  static Future<void> hideMessageNotifications() async {
    try {
      await _localNotifications?.cancelAll();
      print("🔔 All notifications hidden");
    } catch (e) {
      print("🔔 hideMessageNotifications error (ignored): $e");
      DebugLogger.warn('NOTIF', 'hideMessageNotifications ошибка: $e');
    }
  }

  /// Показать тестовое уведомление
  static Future<void> showTestNotification() async {
    if (_localNotifications == null) {
      await _initLocalNotifications();
    }

    const androidDetails = AndroidNotificationDetails(
      _messageChannelId,
      _messageChannelName,
      channelDescription: 'Тестовое уведомление',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    await _localNotifications!.show(
      9999,
      'Orpheus',
      'Тестовое уведомление работает! 🔔',
      const NotificationDetails(android: androidDetails),
    );

    print("🔔 Test notification shown");
  }
}
