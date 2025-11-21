// lib/services/notification_service.dart

import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';

// Эта функция должна быть ВНЕ класса (top-level), чтобы работать, когда приложение выгружено из памяти
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Здесь срабатывает код, когда уведомление приходит в убитое приложение
  print("FIREBASE BACKGROUND: Получено сообщение: ${message.messageId}");
}

class NotificationService {
  // Singleton паттерн
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // Переменная для хранения токена
  String? fcmToken;

  Future<void> init() async {
    // 1. Запрос разрешений (Критично для Android 13+)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    print('FIREBASE: Разрешение на уведомления: ${settings.authorizationStatus}');

    // 2. Получение токена
    try {
      fcmToken = await _firebaseMessaging.getToken();
      print("FIREBASE FCM TOKEN: $fcmToken");

      // Подписываемся на обновление токена (если он изменится)
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        fcmToken = newToken;
        print("FIREBASE: Токен обновлен: $newToken");
        // В будущем здесь нужно будет отправлять новый токен на сервер
      });

    } catch (e) {
      print("FIREBASE ERROR: Не удалось получить токен: $e");
    }

    // 3. Обработка сообщений, когда приложение ОТКРЫТО (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('FIREBASE FOREGROUND: ${message.notification?.title} / ${message.notification?.body}');

      // Если приложение открыто, Firebase по умолчанию НЕ показывает уведомление сверху.
      // Мы можем добавить свою логику здесь, если захотим (например, всплывающее окно внутри приложения),
      // но пока оставим просто лог.
    });

    // 4. Обработка клика по уведомлению (когда приложение свернуто)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('FIREBASE: Пользователь нажал на уведомление!');
      // Здесь можно добавить логику перехода в конкретный чат
    });
  }
}