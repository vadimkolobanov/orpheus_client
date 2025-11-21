// lib/main.dart

import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:orpheus_project/call_screen.dart';
import 'package:orpheus_project/contacts_screen.dart';
import 'package:orpheus_project/license_screen.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/theme/app_theme.dart';

// --- Глобальные сервисы ---
final cryptoService = CryptoService();
final websocketService = WebSocketService();
final notificationService = NotificationService();

// Глобальный ключ навигации
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Контроллеры потоков для обновления UI
final StreamController<String> messageUpdateController = StreamController.broadcast();
final StreamController<Map<String, dynamic>> signalingStreamController = StreamController.broadcast();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Инициализация Firebase
  try {
    await Firebase.initializeApp();
    print("FIREBASE: Инициализирован успешно");

    // Регистрация фонового обработчика (ОБЯЗАТЕЛЬНО до runApp)
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Инициализация нашего сервиса уведомлений (запрос прав, получение токена)
    await notificationService.init();

  } catch (e) {
    print("FIREBASE ERROR: Ошибка инициализации: $e");
  }

  // 2. Инициализация криптографии
  await cryptoService.init();

  // 3. Запуск слушателя WebSocket сообщений
  _listenForMessages();

  // 4. Подключение к WebSocket (если есть ключи)
  if (cryptoService.publicKeyBase64 != null) {
    websocketService.connect(cryptoService.publicKeyBase64!);
  }

  runApp(const MyApp());
}

void _listenForMessages() {
  websocketService.stream.listen((messageJson) async {
    try {
      final messageData = json.decode(messageJson) as Map<String, dynamic>;
      final type = messageData['type'] as String?;

      // Пропускаем системные сообщения и ошибки
      if (type == 'error' || type == 'payment-confirmed' || type == 'license-status') return;

      final senderKey = messageData['sender_pubkey'] as String?;
      // Если нет отправителя - игнорируем (кроме системных, но их мы отфильтровали выше)
      if (senderKey == null) return;

      // --- ЛОГИКА ЗВОНКОВ ---
      if (type == 'call-offer') {
        print("<<< Входящий звонок от $senderKey");
        final data = messageData['data'] as Map<String, dynamic>;

        // Открываем экран звонка через глобальный ключ навигации
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (context) => CallScreen(contactPublicKey: senderKey, offer: data),
        ));

      } else if (type == 'call-answer' || type == 'ice-candidate' || type == 'hang-up' || type == 'call-rejected') {
        // Пересылаем сигналы WebRTC в контроллер (его слушает CallScreen)
        signalingStreamController.add(messageData);
      }

      // --- ЛОГИКА ЧАТА ---
      else if (type == 'chat') {
        final payload = messageData['payload'] as String?;
        if (payload != null) {
          try {
            final decryptedMessage = await cryptoService.decrypt(senderKey, payload);

            // Сохраняем сообщение как НЕ ПРОЧИТАННОЕ (isRead: false)
            // Благодаря этому в контактах появится красный кружок
            final receivedMessage = ChatMessage(
                text: decryptedMessage,
                isSentByMe: false,
                status: MessageStatus.delivered,
                isRead: false
            );

            await DatabaseService.instance.addMessage(receivedMessage, senderKey);

            // Уведомляем UI (чтобы обновились счетчики внутри приложения и экран чата)
            messageUpdateController.add(senderKey);

          } catch (e) {
            print("Ошибка расшифровки сообщения: $e");
          }
        }
      }
    } catch (e) {
      print("Ошибка обработки сообщения в main: $e");
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // Состояние лицензии
  bool _isLicensed = false;
  bool _isCheckCompleted = false; // Ждем ответа от сервера перед показом экрана

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Слушаем WebSocket для глобальной проверки статуса лицензии
    websocketService.stream.listen((message) {
      try {
        final data = json.decode(message);
        if (data['type'] == 'license-status') {
          setState(() {
            _isLicensed = (data['status'] == 'active');
            _isCheckCompleted = true;
          });
        } else if (data['type'] == 'payment-confirmed') {
          setState(() {
            _isLicensed = true;
            _isCheckCompleted = true;
          });
        }
      } catch (e) {
        // Игнорируем ошибки парсинга
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Переподключение при сворачивании/разворачивании
    if (state == AppLifecycleState.resumed) {
      if (cryptoService.publicKeyBase64 != null) {
        websocketService.connect(cryptoService.publicKeyBase64!);
      }
    }
    // Примечание: мы специально НЕ вызываем disconnect() при паузе,
    // чтобы WebSocket жил как можно дольше в фоне.
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orpheus Client',
      theme: AppTheme.lightTheme,
      navigatorKey: navigatorKey, // Важно для входящих звонков
      debugShowCheckedModeBanner: false,

      // ЛОГИКА МАРШРУТИЗАЦИИ
      home: !_isCheckCompleted
          ? const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Подключение к серверу..."),
            ],
          ),
        ),
      )
          : _isLicensed
          ? const ContactsScreen() // Лицензия есть -> Контакты
          : LicenseScreen(       // Лицензии нет -> Экран оплаты
        onLicenseConfirmed: () {
          setState(() => _isLicensed = true);
        },
      ),
    );
  }
}