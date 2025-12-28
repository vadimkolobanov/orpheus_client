// lib/services/notification_service.dart

import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:flutter/foundation.dart';

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

  /// ВАЖНО: не трогаем `FirebaseMessaging.instance` в момент импорта/конструирования
  /// (widget-тесты могут падать без зарегистрированных плагинов).
  /// Достаём инстанс лениво — только когда реально вызывается `init()`.
  FirebaseMessaging get _firebaseMessaging => FirebaseMessaging.instance;

  // ===== Local notifications backend (DI for unit tests) =====
  static NotificationLocalBackend? _localBackend;
  static bool _localInitialized = false;

  @visibleForTesting
  static void debugSetLocalBackendForTesting(NotificationLocalBackend? backend) {
    _localBackend = backend;
    _localInitialized = false;
  }

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

  /// Android small icon для уведомлений.
  ///
  /// Важно: НЕ используем `ic_launcher` (часто адаптивный) — он и даёт "белый квадрат".
  /// Нужна монохромная иконка в `res/drawable`.
  static const String _androidSmallIcon = 'ic_stat_orpheus';

  // Notification IDs
  static const int _callNotificationId = 1001;
  static const int _messageNotificationId = 1002;

  /// Инициализация сервиса
  Future<void> init() async {
    // 1. Инициализация локальных уведомлений
    await _ensureLocalNotificationsInitialized();

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
  static Future<void> _ensureLocalNotificationsInitialized() async {
    if (_localBackend == null) {
      _localBackend = PluginNotificationLocalBackend();
    }
    if (_localInitialized) return;

    // Создаём каналы уведомлений
    await _localBackend!.createAndroidChannel(
      id: _callChannelId,
      name: _callChannelName,
      description: 'Уведомления о входящих звонках',
      importance: Importance.max,
      ledColor: const Color(0xFF6AD394),
    );

    await _localBackend!.createAndroidChannel(
      id: _messageChannelId,
      name: _messageChannelName,
      description: 'Уведомления о новых сообщениях',
      importance: Importance.high,
    );

    await _localBackend!.initialize(onTap: _onNotificationTap);

    _localInitialized = true;
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
    await _ensureLocalNotificationsInitialized();

    final type = data['type'];
    final senderName = data['sender_name'] ?? 'Неизвестный';

    if (type == 'call') {
      await showCallNotification(callerName: senderName);
    } else if (type == 'message') {
      await showMessageNotification(senderName: senderName);
    }
  }

  @visibleForTesting
  static Future<void> debugHandleBackgroundMessageForTesting(Map<String, dynamic> data) {
    return _handleBackgroundMessage(data);
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
      await _ensureLocalNotificationsInitialized();

      await _localBackend!.show(
        id: _callNotificationId,
        channelId: _callChannelId,
        channelName: _callChannelName,
        title: 'Входящий звонок',
        body: callerName,
        category: AndroidNotificationCategory.call,
        androidSmallIcon: _androidSmallIcon,
        fullScreenIntent: true,
        ongoing: true,
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
      await _localBackend?.cancel(_callNotificationId);
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
      await _ensureLocalNotificationsInitialized();

      await _localBackend!.show(
        id: _messageNotificationId + senderName.hashCode % 1000, // Уникальный ID для разных отправителей
        channelId: _messageChannelId,
        channelName: _messageChannelName,
        title: senderName,
        body: 'Новое сообщение', // Не показываем содержимое для приватности
        category: AndroidNotificationCategory.message,
        androidSmallIcon: _androidSmallIcon,
        groupKey: 'orpheus_messages_group',
        ongoing: false,
        fullScreenIntent: false,
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
      await _localBackend?.cancelAll();
      print("🔔 All notifications hidden");
    } catch (e) {
      print("🔔 hideMessageNotifications error (ignored): $e");
      DebugLogger.warn('NOTIF', 'hideMessageNotifications ошибка: $e');
    }
  }

  /// Показать тестовое уведомление
  static Future<void> showTestNotification() async {
    await _ensureLocalNotificationsInitialized();

    await _localBackend!.show(
      id: 9999,
      channelId: _messageChannelId,
      channelName: _messageChannelName,
      title: 'Orpheus',
      body: 'Тестовое уведомление работает! 🔔',
      category: AndroidNotificationCategory.message,
      androidSmallIcon: _androidSmallIcon,
      groupKey: null,
      ongoing: false,
      fullScreenIntent: false,
    );

    print("🔔 Test notification shown");
  }
}

/// Минимальный интерфейс для локальных уведомлений (DI для unit-тестов).
abstract class NotificationLocalBackend {
  Future<void> createAndroidChannel({
    required String id,
    required String name,
    required String description,
    required Importance importance,
    Color? ledColor,
  });

  Future<void> initialize({required void Function(NotificationResponse response) onTap});

  Future<void> show({
    required int id,
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    required AndroidNotificationCategory category,
    required String androidSmallIcon,
    required bool fullScreenIntent,
    required bool ongoing,
    String? groupKey,
  });

  Future<void> cancel(int id);
  Future<void> cancelAll();
}

class PluginNotificationLocalBackend implements NotificationLocalBackend {
  PluginNotificationLocalBackend({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> createAndroidChannel({
    required String id,
    required String name,
    required String description,
    required Importance importance,
    Color? ledColor,
  }) async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        id,
        name,
        description: description,
        importance: importance,
        playSound: true,
        enableVibration: true,
        enableLights: ledColor != null,
        ledColor: ledColor,
      ),
    );
  }

  @override
  Future<void> initialize({required void Function(NotificationResponse response) onTap}) async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings(NotificationService._androidSmallIcon),
      ),
      onDidReceiveNotificationResponse: onTap,
    );
  }

  @override
  Future<void> show({
    required int id,
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    required AndroidNotificationCategory category,
    required String androidSmallIcon,
    required bool fullScreenIntent,
    required bool ongoing,
    String? groupKey,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: category == AndroidNotificationCategory.call ? Importance.max : Importance.high,
      priority: category == AndroidNotificationCategory.call ? Priority.max : Priority.high,
      category: category,
      icon: androidSmallIcon,
      fullScreenIntent: fullScreenIntent,
      ongoing: ongoing,
      autoCancel: !ongoing,
      showWhen: category != AndroidNotificationCategory.call,
      enableVibration: true,
      playSound: true,
      groupKey: groupKey,
    );

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
