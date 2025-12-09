import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:orpheus_project/call_screen.dart';
import 'package:orpheus_project/contacts_screen.dart';
import 'package:orpheus_project/license_screen.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/background_call_service.dart'; // НОВОЕ
import 'package:orpheus_project/services/notification_foreground_service.dart'; // НОВОЕ - постоянный сервис
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/pending_actions_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/theme/app_theme.dart';
import 'package:orpheus_project/welcome_screen.dart';
import 'package:orpheus_project/screens/home_screen.dart';
final cryptoService = CryptoService();
final websocketService = WebSocketService();
final notificationService = NotificationService();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final StreamController<String> messageUpdateController = StreamController.broadcast();
final StreamController<Map<String, dynamic>> signalingStreamController = StreamController.broadcast();

// --- ГЛОБАЛЬНЫЙ БУФЕР ДЛЯ ВХОДЯЩИХ ЗВОНКОВ ---
final Map<String, List<Map<String, dynamic>>> _incomingCallBuffers = {};

List<Map<String, dynamic>> getAndClearIncomingCallBuffer(String contactPublicKey) {
  final buffer = _incomingCallBuffers.remove(contactPublicKey) ?? [];
  print("MAIN: Из буфера извлечено ${buffer.length} кандидатов для $contactPublicKey");
  return buffer;
}

bool _hasKeys = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await notificationService.init();

    // ИНИЦИАЛИЗАЦИЯ ФОНОВЫХ СЕРВИСОВ
    // ВАЖНО: NotificationForegroundService должен инициализироваться первым,
    // так как он настраивает общий сервис. BackgroundCallService только создает канал уведомлений.
    await NotificationForegroundService.initialize(); // Постоянный сервис для уведомлений
    await BackgroundCallService.initialize(); // Создает канал уведомлений для звонков
    
    // Запуск постоянного сервиса уведомлений
    await NotificationForegroundService.start();
    
    // Регистрация callback'ов для FCM уведомлений
    _setupNotificationCallbacks();
  } catch (e) {
    print("INIT ERROR: $e");
  }

  _hasKeys = await cryptoService.init();
  _listenForMessages();

  if (_hasKeys && cryptoService.publicKeyBase64 != null) {
    websocketService.connect(cryptoService.publicKeyBase64!);
  }

  runApp(const MyApp());
}

/// Настройка callback'ов для обработки FCM уведомлений
void _setupNotificationCallbacks() {
  // Callback для входящих звонков из push-уведомления
  NotificationService.onIncomingCall = (String callerKey, Map<String, dynamic>? offerData) {
    print("📞 FCM: Incoming call from $callerKey");
    
    // Проверяем, не обрабатывается ли уже этот звонок
    // Если звонок уже обрабатывается в main.dart, не открываем новый экран
    if (NotificationForegroundService.isCallHandledInMain(callerKey)) {
      print("📞 Call already being handled, skipping duplicate screen");
      // Отменяем уведомление
      NotificationService.cancelCallNotification();
      return;
    }
    
    // Отменяем уведомление
    NotificationService.cancelCallNotification();
    
    // Уведомляем сервис, что звонок обрабатывается в main isolate
    NotificationForegroundService.markCallHandledInMain(callerKey);
    
    // Открываем экран звонка (если навигатор готов)
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(MaterialPageRoute(
        builder: (context) => CallScreen(
          contactPublicKey: callerKey,
          offer: offerData,
        ),
      ));
    }
  };

  // Callback для новых сообщений из push-уведомления
  NotificationService.onNewMessage = (String senderKey) {
    print("📨 FCM: New message from $senderKey");
    
    // Отменяем уведомление
    NotificationService.cancelMessageNotification(senderKey);
    
    // Обновляем UI чата
    messageUpdateController.add(senderKey);
  };

  // Callback для отклонения звонка (отправка hang-up на сервер)
  NotificationService.onDeclineCall = (String callerKey) async {
    print("📞 Отклонение звонка от: $callerKey");
    // Отменяем уведомление сразу
    NotificationService.cancelCallNotification();
    
    // Проверяем подключение WebSocket перед отправкой
    if (websocketService.currentStatus == ConnectionStatus.Connected) {
      // Отправляем hang-up на сервер
      websocketService.sendSignalingMessage(callerKey, 'call-rejected', {});
      print("📞 Hang-up отправлен на сервер");
    } else {
      print("📞 WARN: WebSocket не подключен, сохраняем отклонение для последующей отправки");
      // Сохраняем отклонение локально для отправки при следующем подключении
      await PendingActionsService.addPendingRejection(callerKey);
    }
  };

  // Callback для отправки FCM токена на сервер при его обновлении
  NotificationService.onTokenUpdated = () {
    print("🔔 FCM: Токен обновлен, отправка на сервер...");
    websocketService.sendFcmToken();
  };
}

void _listenForMessages() {
  websocketService.stream.listen((messageJson) async {
    try {
      final messageData = json.decode(messageJson) as Map<String, dynamic>;
      final type = messageData['type'] as String?;
      final senderKey = messageData['sender_pubkey'] as String?;

      // Логируем все входящие сообщения для отладки
      print("📨 WS RECEIVED: type=$type, sender=${senderKey?.substring(0, 8) ?? 'null'}...");

      if (type == 'error' || type == 'payment-confirmed' || type == 'license-status' || senderKey == null) return;

      // --- ЛОГИКА ЗВОНКОВ ---
      if (type == 'call-offer') {
        print("📞 INCOMING CALL from: ${senderKey.substring(0, 8)}...");
        
        // Безопасное получение данных оффера
        final rawData = messageData['data'];
        if (rawData == null || rawData is! Map<String, dynamic>) {
          print("❌ ERROR: call-offer data is null or invalid: $rawData");
          return;
        }
        final data = rawData;

        // Сохраняем данные оффера для использования при принятии из уведомления
        NotificationService.pendingOffers[senderKey] = data;
        print("📞 Saved offer data for incoming call from: ${senderKey.substring(0, 8)}...");

        // Уведомляем сервис, что звонок обрабатывается в main isolate
        // Это предотвратит показ уведомления в сервисе
        NotificationForegroundService.markCallHandledInMain(senderKey);

        // Сброс буфера для нового звонка
        _incomingCallBuffers.remove(senderKey);
        _incomingCallBuffers[senderKey] = [];

        // Проверяем, готов ли Navigator
        if (navigatorKey.currentState != null) {
          print("📞 Opening CallScreen...");
          navigatorKey.currentState!.push(MaterialPageRoute(
            builder: (context) => CallScreen(contactPublicKey: senderKey, offer: data),
          ));
        } else {
          print("❌ ERROR: Navigator not ready! Cannot open CallScreen.");
        }
      }
      else if (type == 'ice-candidate') {
        // Если экран звонка еще не готов (в буфере есть ключ), сохраняем туда
        if (_incomingCallBuffers.containsKey(senderKey)) {
          print("MAIN: Кандидат сохранен в глобальный буфер");
          _incomingCallBuffers[senderKey]!.add(messageData);
        }
        // Отправляем в поток (для активного CallScreen)
        signalingStreamController.add(messageData);
      }
      else if (type == 'call-answer') {
        signalingStreamController.add(messageData);
      }
      else if (type == 'hang-up' || type == 'call-rejected') {
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
            print("Decryption Error: $e");
          }
        }
      }
    } catch (e, stackTrace) {
      print("❌ Message Handler Error: $e");
      print("Stack trace: $stackTrace");
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
  late bool _keysExist;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  void _onAuthComplete() {
    setState(() => _keysExist = true);
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
      // Принудительный реконнект при разворачивании
      if (cryptoService.publicKeyBase64 != null) {
        websocketService.connect(cryptoService.publicKeyBase64!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orpheus',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: !_keysExist
          ? WelcomeScreen(onAuthComplete: _onAuthComplete)
          : !_isCheckCompleted
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _isLicensed
          ? const HomeScreen() // <--- ИЗМЕНЕНИЕ ЗДЕСЬ
          : LicenseScreen(onLicenseConfirmed: () => setState(() => _isLicensed = true)),
    );
  }}