// lib/services/notification_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:orpheus_project/services/pending_actions_service.dart';

/// Top-level функция для обработки FCM сообщений в фоне.
/// ДОЛЖНА быть top-level (не в классе), чтобы работать когда приложение убито.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("🔔🔔🔔 FIREBASE BACKGROUND HANDLER ВЫЗВАН 🔔🔔🔔");
  print("🔔 Message ID: ${message.messageId}");
  print("🔔 Message Type: ${message.data['type']}");
  print("🔔 Data: ${message.data}");
  print("🔔 Notification: ${message.notification?.title} - ${message.notification?.body}");
  print("🔔 Sent Time: ${message.sentTime}");
  print("🔔 Message ID from FCM: ${message.messageId}");
  print("🔔 Has notification payload: ${message.notification != null}");
  print("🔔 Has data payload: ${message.data.isNotEmpty}");
  print("🔔 Full message: ${message.toString()}");
  
  // Инициализируем и показываем уведомление
  await NotificationService._handleBackgroundMessage(message);
}

class NotificationService {
  // Singleton
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  String? fcmToken;

  // ID каналов уведомлений
  static const String _callChannelId = 'orpheus_incoming_call';
  static const String _callChannelName = 'Входящие звонки';
  static const String _messageChannelId = 'orpheus_messages';
  static const String _messageChannelName = 'Сообщения';

  // Notification IDs
  static const int _callNotificationId = 1001;
  static const int _messageNotificationId = 1002;

  // Callback для обработки входящих звонков из FCM
  static Function(String callerKey, Map<String, dynamic>? offerData)? onIncomingCall;
  static Function(String senderKey)? onNewMessage;
  
  // Callback для отклонения звонка (отправка hang-up на сервер)
  static Function(String callerKey)? onDeclineCall;
  
  // Callback для отправки FCM токена на сервер при его обновлении
  static VoidCallback? onTokenUpdated;
  
  // Хранилище данных оффера для входящих звонков (ключ: callerKey, значение: offerData)
  static final Map<String, Map<String, dynamic>> pendingOffers = {};

  Future<void> init() async {
    print('🔔🔔🔔 FIREBASE INIT НАЧАЛО 🔔🔔🔔');
    
    // 1. Запрос разрешений Firebase (критично для Android 13+)
    try {
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        criticalAlert: true, // Для критических уведомлений
      );

      print('🔔 FIREBASE: Разрешение на уведомления: ${settings.authorizationStatus}');
      print('🔔 FIREBASE: Alert разрешен: ${settings.alert}');
      print('🔔 FIREBASE: Badge разрешен: ${settings.badge}');
      print('🔔 FIREBASE: Sound разрешен: ${settings.sound}');
      print('🔔 FIREBASE: Critical alert разрешен: ${settings.criticalAlert}');
      
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        print('🔔 WARN: FIREBASE разрешения НЕ предоставлены!');
      }
    } catch (e) {
      print('🔔 FIREBASE ERROR: Ошибка запроса разрешений: $e');
    }

    // 2. Инициализация локальных уведомлений
    try {
      await _initLocalNotifications();
      print('🔔 FIREBASE: Локальные уведомления инициализированы');
    } catch (e) {
      print('🔔 FIREBASE ERROR: Ошибка инициализации локальных уведомлений: $e');
    }

    // 3. Получение FCM токена
    try {
      fcmToken = await _firebaseMessaging.getToken();
      if (fcmToken != null) {
        print("🔔 FIREBASE FCM TOKEN: $fcmToken");
        print("🔔 FIREBASE FCM TOKEN длина: ${fcmToken?.length ?? 0}");
      } else {
        print("🔔 WARN: FIREBASE FCM TOKEN = NULL!");
      }

      // Подписка на обновление токена
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        fcmToken = newToken;
        print("🔔 FIREBASE: Токен обновлен: $newToken");
        print("🔔 FIREBASE: Отправка нового токена на сервер...");
        // Автоматически отправляем токен на сервер через WebSocket
        if (onTokenUpdated != null) {
          onTokenUpdated!();
        } else {
          print("🔔 WARN: Callback для отправки токена не установлен!");
        }
      });
    } catch (e) {
      print("🔔 FIREBASE ERROR: Не удалось получить токен: $e");
    }

    // 4. Обработка сообщений когда приложение ОТКРЫТО или СВЕРНУТО (Foreground)
    // onMessage вызывается когда приложение в foreground (открыто или свернуто)
    // Отключаем автоматическое показ FCM уведомлений, показываем только локальные
    FirebaseMessaging.onMessage.listen((message) {
      print('🔔 FIREBASE: onMessage listener вызван (приложение в foreground)');
      print('🔔 FIREBASE: Message type: ${message.data['type']}');
      print('🔔 FIREBASE: Has notification: ${message.notification != null}');
      // Отключаем автоматическое показ уведомления FCM
      // Показываем только наше локальное уведомление
      _handleForegroundMessage(message);
    });
    print('🔔 FIREBASE: onMessage listener зарегистрирован');
    
    // Настраиваем FCM так, чтобы он не показывал уведомления автоматически
    // Мы будем показывать только локальные уведомления для полного контроля
    await _firebaseMessaging.setAutoInitEnabled(true);

    // 5. Обработка клика по уведомлению (приложение было свернуто)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      print('🔔 FIREBASE: onMessageOpenedApp listener вызван');
      _handleNotificationTap(message);
    });
    print('🔔 FIREBASE: onMessageOpenedApp listener зарегистрирован');

    // 6. Проверяем, не было ли приложение открыто из уведомления
    try {
      RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        print('🔔 FIREBASE: Приложение открыто из уведомления');
        _handleNotificationTap(initialMessage);
      } else {
        print('🔔 FIREBASE: Приложение открыто не из уведомления');
      }
    } catch (e) {
      print('🔔 FIREBASE ERROR: Ошибка проверки initialMessage: $e');
    }

    // 7. Запрос на игнорирование оптимизации батареи
    try {
      await _requestBatteryOptimizationExemption();
      print('🔔 FIREBASE: Запрос на игнорирование оптимизации батареи выполнен');
    } catch (e) {
      print('🔔 FIREBASE ERROR: Ошибка запроса на игнорирование оптимизации батареи: $e');
    }
    
    print('🔔🔔🔔 FIREBASE INIT ЗАВЕРШЕНО 🔔🔔🔔');
  }

  /// Инициализация локальных уведомлений с каналами
  Future<void> _initLocalNotifications() async {
    // Android настройки
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const initSettings = InitializationSettings(android: androidSettings);
    
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );

    // Создание канала для ВХОДЯЩИХ ЗВОНКОВ (максимальный приоритет)
    final callChannel = AndroidNotificationChannel(
      _callChannelId,
      _callChannelName,
      description: 'Уведомления о входящих защищённых звонках',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]), // Длинная вибрация
      enableLights: true,
      ledColor: const Color.fromARGB(255, 106, 211, 148), // Зелёный как в теме
    );

    // Создание канала для СООБЩЕНИЙ (высокий приоритет)
    final messageChannel = AndroidNotificationChannel(
      _messageChannelId,
      _messageChannelName,
      description: 'Уведомления о новых сообщениях',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 250, 100, 250]), // Короткая вибрация
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(callChannel);
      await androidPlugin.createNotificationChannel(messageChannel);
      print("🔔 Notification channels created");
    }
  }

  /// Обработка FCM сообщения в background (статический метод для изолята)
  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    print("🔔🔔🔔 _handleBackgroundMessage ВЫЗВАН 🔔🔔🔔");
    print("🔔 Message ID: ${message.messageId}");
    print("🔔 Notification: ${message.notification?.title} - ${message.notification?.body}");
    print("🔔 Sent Time: ${message.sentTime}");
    print("🔔 Message ID from FCM: ${message.messageId}");
    print("🔔 Has notification: ${message.notification != null}");
    print("🔔 Has data: ${message.data.isNotEmpty}");
    
    final data = message.data;
    final type = data['type'];
    
    print("🔔 Background message type: $type");
    print("🔔 Background message data: $data");
    print("🔔 Full message: ${message.toString()}");

    // Переинициализация локальных уведомлений в изоляте
    try {
      await initLocalNotificationsInIsolate();
      print("🔔 Локальные уведомления инициализированы");
    } catch (e) {
      print("🔔 ОШИБКА инициализации локальных уведомлений: $e");
    }

    // Проверяем, есть ли notification payload от FCM
    // Если есть, FCM автоматически покажет уведомление, поэтому мы не показываем локальное
    // чтобы избежать дублирования. Но для звонков мы всегда показываем локальное с кнопками.
    final hasFcmNotification = message.notification != null;
    
    if (type == 'incoming_call') {
      final callerKey = data['caller_key'] ?? '';
      final callerName = data['caller_name'] ?? 'Неизвестный';
      
      // Для звонков: если FCM уже покажет уведомление, не показываем локальное
      // чтобы избежать дублирования. FCM уведомление будет без кнопок, но это лучше чем дублирование.
      // В идеале на сервере нужно отправлять только data payload для звонков, без notification.
      // Извлекаем данные оффера из сообщения
      Map<String, dynamic>? offerData;
      if (data['offer_data'] != null) {
        try {
          offerData = json.decode(data['offer_data']);
          print("🔔 Offer data получен в background: ${offerData != null}");
        } catch (e) {
          print("🔔 ОШИБКА декодирования offer_data в background: $e");
        }
      }
      
      if (!hasFcmNotification) {
        print("🔔 Показываем локальное уведомление о звонке от: $callerName (FCM notification: $hasFcmNotification)");
        try {
          await _showCallNotification(
            callerKey: callerKey,
            callerName: callerName,
            offerData: offerData,
          );
          print("🔔 Уведомление о звонке показано успешно");
        } catch (e) {
          print("🔔 ОШИБКА показа уведомления о звонке: $e");
        }
      } else {
        // Даже если FCM покажет уведомление, сохраняем данные оффера на случай если пользователь откроет приложение
        if (offerData != null) {
          pendingOffers[callerKey] = offerData;
          print("🔔 FCM покажет уведомление, но сохранили offer data для: $callerKey");
        } else {
          print("🔔 FCM уже покажет уведомление о звонке, пропускаем локальное (чтобы избежать дублирования)");
        }
      }
    } else if (type == 'new_message') {
      final senderKey = data['sender_key'] ?? '';
      final senderName = data['sender_name'] ?? 'Новое сообщение';
      
      // Для сообщений: если FCM уже покажет уведомление, не показываем локальное
      // чтобы избежать дублирования
      if (!hasFcmNotification) {
        print("🔔 Показываем локальное уведомление о сообщении от: $senderName");
        try {
          await _showMessageNotification(
            senderKey: senderKey,
            senderName: senderName,
          );
          print("🔔 Уведомление о сообщении показано успешно");
        } catch (e) {
          print("🔔 ОШИБКА показа уведомления о сообщении: $e");
        }
      } else {
        print("🔔 FCM уже покажет уведомление, пропускаем локальное для сообщения");
      }
    } else {
      print("🔔 Неизвестный тип сообщения: $type");
    }
  }

  /// Статическая инициализация для background isolate (публичный для использования в сервисе)
  static Future<void> initLocalNotificationsInIsolate() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );
  }

  /// Показ уведомления о входящем звонке
  static Future<void> _showCallNotification({
    required String callerKey,
    required String callerName,
    Map<String, dynamic>? offerData,
  }) async {
    print("🔔 Showing CALL notification for: $callerName");

    final androidDetails = AndroidNotificationDetails(
      _callChannelId,
      _callChannelName,
      channelDescription: 'Уведомления о входящих защищённых звонках',
      importance: Importance.max,
      priority: Priority.max,
      
      // !!! КЛЮЧЕВОЕ: Full-Screen Intent показывает Activity поверх экрана блокировки
      fullScreenIntent: true,
      
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      
      // Уведомление не исчезает автоматически
      autoCancel: false,
      ongoing: true,
      
      // Вибрация: пауза-вибрация-пауза-вибрация...
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]),
      enableVibration: true,
      
      playSound: true,
      
      // Таймаут (звонок актуален 60 секунд)
      timeoutAfter: 60000,
      
      // Показывать время
      usesChronometer: true,
      chronometerCountDown: true,
      when: DateTime.now().add(const Duration(seconds: 60)).millisecondsSinceEpoch,
      
      // Цвет акцента
      color: const Color.fromARGB(255, 106, 211, 148),
      colorized: true,
      
      // Действия
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'accept_call',
          '✓ Принять',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          'decline_call',
          '✕ Отклонить',
          cancelNotification: true,
        ),
      ],
    );

    // Сохраняем данные оффера для последующего использования при принятии
    if (offerData != null) {
      pendingOffers[callerKey] = offerData;
      print("🔔 Saved offer data for caller: ${callerKey.substring(0, 8)}...");
    }
    
    await _localNotifications.show(
      _callNotificationId,
      '📞 Входящий звонок',
      'Звонит: $callerName',
      NotificationDetails(android: androidDetails),
      payload: 'call:$callerKey',
    );
  }
  
  /// Получить и удалить данные оффера для звонка
  static Map<String, dynamic>? getAndRemoveOffer(String callerKey) {
    final offer = pendingOffers.remove(callerKey);
    if (offer != null) {
      print("🔔 Retrieved offer data for caller: ${callerKey.substring(0, 8)}...");
    }
    return offer;
  }

  /// Показ уведомления о новом сообщении
  static Future<void> _showMessageNotification({
    required String senderKey,
    required String senderName,
  }) async {
    print("🔔 Showing MESSAGE notification from: $senderName");

    final androidDetails = AndroidNotificationDetails(
      _messageChannelId,
      _messageChannelName,
      channelDescription: 'Уведомления о новых сообщениях',
      importance: Importance.high,
      priority: Priority.high,
      
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 250, 100, 250]),
      
      playSound: true,
      
      // Цвет акцента
      color: const Color.fromARGB(255, 106, 211, 148),
    );

    await _localNotifications.show(
      senderKey.hashCode, // Уникальный ID для каждого отправителя
      senderName,
      'Новое защищённое сообщение',
      NotificationDetails(android: androidDetails),
      payload: 'chat:$senderKey',
    );
  }

  /// Обработка FCM сообщения когда приложение открыто
  void _handleForegroundMessage(RemoteMessage message) {
    print('🔔🔔🔔 FIREBASE FOREGROUND MESSAGE ПОЛУЧЕНО 🔔🔔🔔');
    print('🔔 Message ID: ${message.messageId}');
    print('🔔 Notification: ${message.notification?.title} - ${message.notification?.body}');
    print('🔔 Sent Time: ${message.sentTime}');
    print('🔔 Message ID from FCM: ${message.messageId}');
    
    final data = message.data;
    final type = data['type'];
    
    print('🔔 FIREBASE FOREGROUND: type=$type, data=$data');
    print('🔔 Full message: ${message.toString()}');
    print('🔔 Has notification payload: ${message.notification != null}');
    print('🔔 Has data payload: ${data.isNotEmpty}');

    // В foreground (приложение открыто или свернуто) всегда показываем локальное уведомление
    // FCM notification в foreground не показывается автоматически, поэтому показываем локальное
    if (type == 'incoming_call') {
      final callerKey = data['caller_key'] ?? '';
      final callerName = data['caller_name'] ?? 'Неизвестный';
      
      print('🔔 FOREGROUND: Обработка входящего звонка: $callerName ($callerKey)');
      
      // Извлекаем данные оффера из сообщения
      Map<String, dynamic>? offerData;
      if (data['offer_data'] != null) {
        try {
          offerData = json.decode(data['offer_data']);
          print('🔔 Offer data получен в foreground: ${offerData != null}');
        } catch (e) {
          print('🔔 ОШИБКА декодирования offer_data в foreground: $e');
        }
      }
      
      // Всегда показываем локальное уведомление с кнопками в foreground
      _showCallNotification(
        callerKey: callerKey,
        callerName: callerName,
        offerData: offerData,
      );
      
      // Вызываем callback если зарегистрирован
      if (onIncomingCall != null && callerKey.isNotEmpty) {
        print('🔔 Вызываем callback onIncomingCall');
        onIncomingCall!(callerKey, offerData);
      } else {
        print('🔔 WARN: onIncomingCall не зарегистрирован или callerKey пуст');
      }
    } else if (type == 'new_message') {
      final senderKey = data['sender_key'] ?? '';
      final senderName = data['sender_name'] ?? 'Новое сообщение';
      
      print('🔔 FOREGROUND: Обработка нового сообщения: $senderName ($senderKey)');
      
      // В foreground всегда показываем локальное уведомление
      // (FCM notification в foreground не показывается автоматически)
      _showMessageNotification(
        senderKey: senderKey,
        senderName: senderName,
      );
      
      if (onNewMessage != null && senderKey.isNotEmpty) {
        print('🔔 Вызываем callback onNewMessage');
        onNewMessage!(senderKey);
      } else {
        print('🔔 WARN: onNewMessage не зарегистрирован или senderKey пуст');
      }
    } else {
      print('🔔 WARN: Неизвестный тип сообщения в foreground: $type');
    }
  }

  /// Обработка клика по уведомлению
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    print('🔔 FIREBASE: Пользователь нажал на уведомление! data=$data');
    
    // Здесь можно добавить навигацию к конкретному экрану
    final type = data['type'];
    if (type == 'incoming_call') {
      final callerKey = data['caller_key'] ?? '';
      if (onIncomingCall != null && callerKey.isNotEmpty) {
        onIncomingCall!(callerKey, null);
      }
    } else if (type == 'new_message') {
      final senderKey = data['sender_key'] ?? '';
      if (onNewMessage != null && senderKey.isNotEmpty) {
        onNewMessage!(senderKey);
      }
    }
  }

  /// Обработка нажатия на локальное уведомление
  static void _onNotificationResponse(NotificationResponse response) {
    print('🔔 LOCAL NOTIFICATION TAP: ${response.payload}, action: ${response.actionId}');
    
    final payload = response.payload ?? '';
    final actionId = response.actionId;
    
    if (payload.startsWith('call:')) {
      final callerKey = payload.substring(5);
      
      if (actionId == 'accept_call') {
        // Принять звонок - получаем сохраненные данные оффера
        print('🔔 Принятие звонка от: $callerKey');
        final offerData = getAndRemoveOffer(callerKey);
        if (onIncomingCall != null) {
          onIncomingCall!(callerKey, offerData);
        }
      } else if (actionId == 'decline_call') {
        // Отклонить звонок - отправляем hang-up на сервер
        print('🔔 Отклонение звонка от: $callerKey');
        if (onDeclineCall != null) {
          onDeclineCall!(callerKey);
        } else {
          print('🔔 WARN: onDeclineCall не зарегистрирован');
        }
      } else {
        // Просто клик по уведомлению - открываем звонок с данными оффера
        final offerData = getAndRemoveOffer(callerKey);
        if (onIncomingCall != null) {
          onIncomingCall!(callerKey, offerData);
        }
      }
    } else if (payload.startsWith('chat:')) {
      final senderKey = payload.substring(5);
      if (onNewMessage != null) {
        onNewMessage!(senderKey);
      }
    }
  }

  /// Обработка нажатия в background
  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) async {
    print('🔔 BACKGROUND NOTIFICATION TAP: ${response.payload}, action: ${response.actionId}');
    
    final payload = response.payload ?? '';
    final actionId = response.actionId;
    
    if (payload.startsWith('call:')) {
      final callerKey = payload.substring(5);
      
      if (actionId == 'accept_call') {
        // Принять звонок - откроется при запуске приложения
        print('🔔 BACKGROUND: Принятие звонка от: $callerKey');
        // Сохраняем действие для обработки при запуске приложения
        // Это будет обработано через getInitialMessage или onMessageOpenedApp
      } else if (actionId == 'decline_call') {
        // Отклонить звонок - сохраняем для отправки при подключении
        print('🔔 BACKGROUND: Отклонение звонка от: $callerKey');
        try {
          await PendingActionsService.addPendingRejection(callerKey);
          print('🔔 BACKGROUND: Pending rejection сохранен для: $callerKey');
        } catch (e) {
          print('🔔 BACKGROUND ERROR: Не удалось сохранить pending rejection: $e');
        }
      }
    }
  }

  /// Отмена уведомления о звонке
  static Future<void> cancelCallNotification() async {
    await _localNotifications.cancel(_callNotificationId);
    // Очищаем все сохраненные офферы при отмене уведомления
    pendingOffers.clear();
  }

  /// Отмена уведомления о сообщении от конкретного пользователя
  static Future<void> cancelMessageNotification(String senderKey) async {
    await _localNotifications.cancel(senderKey.hashCode);
  }

  /// Отмена всех уведомлений
  static Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  /// Запрос на игнорирование оптимизации батареи
  Future<void> _requestBatteryOptimizationExemption() async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.example.orpheus_project/battery');
        final isDisabled = await platform.invokeMethod<bool>('isBatteryOptimizationDisabled');
        
        if (isDisabled != true) {
          print("🔔 Battery optimization is enabled, requesting exemption...");
          await platform.invokeMethod('requestBatteryOptimization');
        } else {
          print("🔔 Battery optimization already disabled");
        }
      } catch (e) {
        print("🔔 Battery optimization request error: $e");
      }
    }
  }

  /// Проверка статуса оптимизации батареи
  Future<bool> isBatteryOptimizationDisabled() async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.example.orpheus_project/battery');
        return await platform.invokeMethod<bool>('isBatteryOptimizationDisabled') ?? false;
      } catch (e) {
        return false;
      }
    }
    return true;
  }

  /// Открыть настройки батареи
  Future<void> openBatterySettings() async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.example.orpheus_project/battery');
        await platform.invokeMethod('openBatterySettings');
      } catch (e) {
        print("🔔 Open battery settings error: $e");
      }
    }
  }

  /// Публичный метод для тестирования уведомлений
  static Future<void> showTestNotification() async {
    await _showMessageNotification(
      senderKey: 'test_${DateTime.now().millisecondsSinceEpoch}',
      senderName: 'Тестовое уведомление',
    );
  }

  /// Публичный метод для показа уведомления о звонке (для использования в foreground service)
  static Future<void> showCallNotification({
    required String callerKey,
    required String callerName,
    Map<String, dynamic>? offerData,
  }) async {
    await _showCallNotification(
      callerKey: callerKey,
      callerName: callerName,
      offerData: offerData,
    );
  }

  /// Публичный метод для показа уведомления о сообщении (для использования в foreground service)
  static Future<void> showMessageNotification({
    required String senderKey,
    required String senderName,
  }) async {
    await _showMessageNotification(
      senderKey: senderKey,
      senderName: senderName,
    );
  }
}
