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
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
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

    // ИНИЦИАЛИЗАЦИЯ ФОНОВОГО СЕРВИСА
    await BackgroundCallService.initialize();
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

void _listenForMessages() {
  websocketService.stream.listen((messageJson) async {
    try {
      final messageData = json.decode(messageJson) as Map<String, dynamic>;
      final type = messageData['type'] as String?;
      final senderKey = messageData['sender_pubkey'] as String?;

      if (type == 'error' || type == 'payment-confirmed' || type == 'license-status' || senderKey == null) return;

      // --- ЛОГИКА ЗВОНКОВ ---
      if (type == 'call-offer') {
        final data = messageData['data'] as Map<String, dynamic>;

        // Сброс буфера для нового звонка
        _incomingCallBuffers.remove(senderKey);
        _incomingCallBuffers[senderKey] = [];

        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (context) => CallScreen(contactPublicKey: senderKey, offer: data),
        ));
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
    } catch (e) {
      print("Message Handler Error: $e");
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