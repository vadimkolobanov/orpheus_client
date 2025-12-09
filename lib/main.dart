import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:orpheus_project/call_screen.dart';
import 'package:orpheus_project/license_screen.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/background_call_service.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/theme/app_theme.dart';
import 'package:orpheus_project/welcome_screen.dart';
import 'package:orpheus_project/screens/home_screen.dart';

// Глобальные сервисы
final cryptoService = CryptoService();
final websocketService = WebSocketService();
final notificationService = NotificationService();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Потоки для обновлений UI
final StreamController<String> messageUpdateController = StreamController.broadcast();
final StreamController<Map<String, dynamic>> signalingStreamController = StreamController.broadcast();

// Буфер для входящих ICE кандидатов (race condition fix)
final Map<String, List<Map<String, dynamic>>> _incomingCallBuffers = {};

List<Map<String, dynamic>> getAndClearIncomingCallBuffer(String contactPublicKey) {
  final buffer = _incomingCallBuffers.remove(contactPublicKey) ?? [];
  print("MAIN: Извлечено ${buffer.length} буферизованных кандидатов для ${contactPublicKey.substring(0, 8)}...");
  return buffer;
}

bool _hasKeys = false;

/// Глобальный флаг: приложение в foreground (активно)?
bool isAppInForeground = true;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  DebugLogger.info('APP', '🚀 Orpheus запускается...');

  try {
    // 1. Firebase
    DebugLogger.info('APP', 'Инициализация Firebase...');
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    DebugLogger.success('APP', 'Firebase инициализирован');
    
    // 2. Уведомления (простая инициализация)
    DebugLogger.info('APP', 'Инициализация уведомлений...');
    await notificationService.init();
    DebugLogger.success('APP', 'Уведомления инициализированы');

    // 3. BackgroundCallService (только инициализация, не запуск)
    DebugLogger.info('APP', 'Инициализация BackgroundCallService...');
    await BackgroundCallService.initialize();
    DebugLogger.success('APP', 'BackgroundCallService инициализирован');
  } catch (e) {
    print("INIT ERROR: $e");
    DebugLogger.error('APP', 'INIT ERROR: $e');
  }

  // 4. Криптография
  DebugLogger.info('APP', 'Инициализация криптографии...');
  _hasKeys = await cryptoService.init();
  DebugLogger.info('APP', 'Ключи: ${_hasKeys ? "ЕСТЬ" : "НЕТ"}');

  // 5. WebSocket подключение
  if (_hasKeys && cryptoService.publicKeyBase64 != null) {
    DebugLogger.info('APP', 'Подключение WebSocket...');
    websocketService.connect(cryptoService.publicKeyBase64!);
  }

  // 6. Слушаем сообщения
  _listenForMessages();

  DebugLogger.success('APP', '✅ Приложение запущено');
  runApp(const MyApp());
}

void _listenForMessages() {
  websocketService.stream.listen((messageJson) async {
    try {
      final messageData = json.decode(messageJson) as Map<String, dynamic>;
      final type = messageData['type'] as String?;
      final senderKey = messageData['sender_pubkey'] as String?;

      print("📨 WS: type=$type, sender=${senderKey?.substring(0, 8) ?? 'null'}...");

      // Пропускаем служебные сообщения
      if (type == 'error' || type == 'payment-confirmed' || type == 'license-status' || type == 'pong' || senderKey == null) {
        return;
      }

      // Логируем все входящие сигнальные сообщения
      DebugLogger.info('MAIN', '📨 IN: $type от ${senderKey.substring(0, 8)}...');

      // === ЗВОНКИ ===
      if (type == 'call-offer') {
        final data = messageData['data'] as Map<String, dynamic>;
        DebugLogger.success('CALL', '📞 Входящий звонок от ${senderKey.substring(0, 8)}...');

        // Сброс буфера для нового звонка
        _incomingCallBuffers.remove(senderKey);
        _incomingCallBuffers[senderKey] = [];

        // Показываем уведомление о звонке
        final contactName = await _getContactName(senderKey);
        await NotificationService.showCallNotification(callerName: contactName);

        // Открываем экран звонка
        DebugLogger.info('CALL', 'Открытие CallScreen...');
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (context) => CallScreen(contactPublicKey: senderKey, offer: data),
        ));
      }
      else if (type == 'ice-candidate') {
        // Буферизуем если экран звонка ещё не готов
        if (_incomingCallBuffers.containsKey(senderKey)) {
          _incomingCallBuffers[senderKey]!.add(messageData);
          DebugLogger.info('ICE', 'Кандидат буферизован (всего: ${_incomingCallBuffers[senderKey]!.length})');
        }
        signalingStreamController.add(messageData);
      }
      else if (type == 'call-answer') {
        DebugLogger.success('CALL', '📞 Получен answer от ${senderKey.substring(0, 8)}...');
        signalingStreamController.add(messageData);
      }
      else if (type == 'hang-up' || type == 'call-rejected') {
        DebugLogger.warn('CALL', '📞 Получен $type от ${senderKey.substring(0, 8)}...');
        _incomingCallBuffers.remove(senderKey);
        
        // ВАЖНО: Сначала отправляем сигнал в CallScreen (до hideCallNotification)
        // чтобы ошибка ProGuard не блокировала завершение звонка
        signalingStreamController.add(messageData);
        DebugLogger.info('CALL', '✅ Сигнал $type отправлен в CallScreen');
        
        // Теперь безопасно скрываем уведомление
        try {
          await NotificationService.hideCallNotification();
        } catch (e) {
          DebugLogger.error('NOTIF', 'Ошибка hideCallNotification: $e');
        }
        
        print("📞 MAIN: Получен $type от ${senderKey.substring(0, 8)}...");
      }

      // === ЧАТ ===
      else if (type == 'chat') {
        final payload = messageData['payload'] as String?;
        if (payload != null) {
          try {
            final decryptedMessage = await cryptoService.decrypt(senderKey, payload);
            DebugLogger.info('CHAT', '💬 Сообщение от ${senderKey.substring(0, 8)}...');
            final receivedMessage = ChatMessage(
              text: decryptedMessage,
              isSentByMe: false,
              status: MessageStatus.delivered,
              isRead: false,
            );
            await DatabaseService.instance.addMessage(receivedMessage, senderKey);
            messageUpdateController.add(senderKey);

            // Показываем уведомление только если:
            // 1. Приложение в фоне (не активно)
            // 2. Это не системное сообщение о звонке
            final isCallStatusMessage = _isCallStatusMessage(decryptedMessage);
            if (!isAppInForeground && !isCallStatusMessage) {
              final contactName = await _getContactName(senderKey);
              DebugLogger.info('CHAT', 'Показ уведомления (app in background)');
              // Не показываем содержимое сообщения - только имя отправителя
              await NotificationService.showMessageNotification(
                senderName: contactName,
              );
            }
          } catch (e) {
            print("Decryption Error: $e");
            DebugLogger.error('CHAT', 'Ошибка расшифровки: $e');
          }
        }
      }
    } catch (e) {
      print("Message Handler Error: $e");
      DebugLogger.error('MAIN', 'Message Handler Error: $e');
    }
  });
}

/// Получить имя контакта по публичному ключу
Future<String> _getContactName(String publicKey) async {
  try {
    final contact = await DatabaseService.instance.getContact(publicKey);
    if (contact != null && contact.name.isNotEmpty) {
      return contact.name;
    }
  } catch (_) {}
  return publicKey.substring(0, 8);
}

/// Проверка является ли сообщение системным сообщением о звонке
bool _isCallStatusMessage(String message) {
  const callStatusMessages = [
    'Исходящий звонок',
    'Входящий звонок',
    'Пропущен звонок',
  ];
  return callStatusMessages.contains(message);
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
    print("🔑 Keys exist: $_keysExist | Public key: ${cryptoService.publicKeyBase64?.substring(0, 20) ?? 'NULL'}...");

    // Слушаем статус лицензии
    websocketService.stream.listen((message) {
      try {
        final data = json.decode(message);
        if (data['type'] == 'license-status') {
          print("📋 License status received: ${data['status']}");
          setState(() {
            _isLicensed = (data['status'] == 'active');
            _isCheckCompleted = true;
          });
        } else if (data['type'] == 'payment-confirmed') {
          print("💳 Payment confirmed!");
          setState(() {
            _isLicensed = true;
            _isCheckCompleted = true;
          });
        }
      } catch (_) {}
    });

    // Таймаут на проверку лицензии (10 секунд)
    // Если за это время не получили ответ — показываем экран лицензии
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && !_isCheckCompleted) {
        print("⚠️ License check timeout - showing license screen");
        setState(() {
          _isCheckCompleted = true;
          _isLicensed = false;
        });
      }
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
    // Логируем изменение состояния
    DebugLogger.info('LIFECYCLE', 'State: $state');
    
    // Обновляем глобальный флаг состояния приложения
    isAppInForeground = (state == AppLifecycleState.resumed);
    
    if (state == AppLifecycleState.resumed) {
      DebugLogger.info('LIFECYCLE', 'Приложение в foreground, переподключение WS...');
      // Переподключение WebSocket при возврате в приложение
      if (cryptoService.publicKeyBase64 != null) {
        websocketService.connect(cryptoService.publicKeyBase64!);
      }
    } else if (state == AppLifecycleState.paused) {
      DebugLogger.info('LIFECYCLE', 'Приложение в background');
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
                  ? const HomeScreen()
                  : LicenseScreen(onLicenseConfirmed: () => setState(() => _isLicensed = true)),
    );
  }
}
