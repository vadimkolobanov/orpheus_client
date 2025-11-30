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
import 'package:orpheus_project/welcome_screen.dart'; // Экран входа/восстановления

// --- Глобальные сервисы ---
final cryptoService = CryptoService();
final websocketService = WebSocketService();
final notificationService = NotificationService();

// Глобальный ключ навигации
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Контроллеры потоков
final StreamController<String> messageUpdateController = StreamController.broadcast();
final StreamController<Map<String, dynamic>> signalingStreamController = StreamController.broadcast();

// Буфер для ICE кандидатов входящих звонков (до создания CallScreen)
final Map<String, List<Map<String, dynamic>>> _incomingCallBuffers = {};

// Функция для получения и очистки буфера кандидатов
List<Map<String, dynamic>> getAndClearIncomingCallBuffer(String contactPublicKey) {
  final buffer = _incomingCallBuffers.remove(contactPublicKey) ?? [];
  return buffer;
}

// Глобальная переменная: есть ли ключи на старте
bool _hasKeys = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Инициализация Firebase
  try {
    await Firebase.initializeApp();
    // Регистрация фонового обработчика
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    // Инициализация сервиса уведомлений
    await notificationService.init();
  } catch (e) {
    print("FIREBASE ERROR: $e");
  }

  // 2. Инициализация криптографии (возвращает true, если ключи уже есть)
  _hasKeys = await cryptoService.init();

  // 3. Запуск слушателя сообщений
  _listenForMessages();

  // 4. Если ключи есть сразу - подключаемся. Если нет - ждем прохождения WelcomeScreen
  if (_hasKeys && cryptoService.publicKeyBase64 != null) {
    websocketService.connect(cryptoService.publicKeyBase64!);
  }

  runApp(const MyApp());
}

void _listenForMessages() {
  websocketService.stream.listen((messageJson) async {
    try {
      final messageData = json.decode(messageJson) as Map<String, dynamic>;
      final type = messageData['type'] as String?;

      if (type == 'error' || type == 'payment-confirmed' || type == 'license-status') return;

      final senderKey = messageData['sender_pubkey'] as String?;
      if (senderKey == null) return;

      // --- ЗВОНКИ ---
      if (type == 'call-offer') {
        final data = messageData['data'] as Map<String, dynamic>;
        // Очищаем старый буфер, если он есть (на случай если приложение было свернуто)
        _incomingCallBuffers.remove(senderKey);
        // Инициализируем новый буфер для этого звонка
        _incomingCallBuffers[senderKey] = [];
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (context) => CallScreen(contactPublicKey: senderKey, offer: data),
        ));
      } else if (type == 'ice-candidate') {
        // Если это входящий звонок (есть буфер), сохраняем кандидат
        if (_incomingCallBuffers.containsKey(senderKey)) {
          _incomingCallBuffers[senderKey]!.add(messageData);
        }
        // Всегда отправляем в signalingStreamController для активных звонков
        signalingStreamController.add(messageData);
      } else if (type == 'call-answer') {
        signalingStreamController.add(messageData);
      } else if (type == 'hang-up' || type == 'call-rejected') {
        // Очищаем буфер кандидатов при завершении/отклонении звонка
        _incomingCallBuffers.remove(senderKey);
        signalingStreamController.add(messageData);
      }

      // --- ЧАТ ---
      else if (type == 'chat') {
        final payload = messageData['payload'] as String?;
        if (payload != null) {
          try {
            final decryptedMessage = await cryptoService.decrypt(senderKey, payload);

            final receivedMessage = ChatMessage(
                text: decryptedMessage,
                isSentByMe: false,
                status: MessageStatus.delivered,
                isRead: false
            );

            await DatabaseService.instance.addMessage(receivedMessage, senderKey);
            messageUpdateController.add(senderKey);

          } catch (e) {
            print("Ошибка расшифровки: $e");
          }
        }
      }
    } catch (e) {
      print("Ошибка обработки: $e");
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isLicensed = false;
  bool _isCheckCompleted = false;

  // Локальное состояние наличия ключей (чтобы обновить UI после создания аккаунта)
  late bool _keysExist;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Инициализируем состояние из глобальной переменной
    _keysExist = _hasKeys;

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
      } catch (_) {}
    });
  }

  // Коллбэк, который вызывается из WelcomeScreen после успешного создания/импорта
  void _onAuthComplete() {
    setState(() {
      _keysExist = true;
    });
    // Сразу подключаемся к серверу
    if (cryptoService.publicKeyBase64 != null) {
      websocketService.connect(cryptoService.publicKeyBase64!);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (cryptoService.publicKeyBase64 != null) {
        websocketService.connect(cryptoService.publicKeyBase64!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orpheus',

      // ВКЛЮЧАЕМ ТЕМНУЮ ТЕМУ
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Принудительно темная

      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: !_keysExist
          ? WelcomeScreen(onAuthComplete: _onAuthComplete)
          : !_isCheckCompleted
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _isLicensed
          ? const ContactsScreen()
          : LicenseScreen(onLicenseConfirmed: () => setState(() => _isLicensed = true)),
    );
  }
}