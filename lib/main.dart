// lib/main.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:orpheus_project/call_screen.dart'; // <-- Импорт нового экрана
import 'package:orpheus_project/contacts_screen.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/theme/app_theme.dart';

// --- Глобальные сервисы и состояние ---
final cryptoService = CryptoService();
final websocketService = WebSocketService();

// Позволяет навигироваться без BuildContext, нужно для входящих звонков
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Старый контроллер для обновления чата
final StreamController<String> messageUpdateController = StreamController.broadcast();
// НОВЫЙ контроллер для передачи сигналов WebRTC на экран звонка
final StreamController<Map<String, dynamic>> signalingStreamController = StreamController.broadcast();


void main() async {
  // ... (код main остается почти без изменений)
  WidgetsFlutterBinding.ensureInitialized();
  await cryptoService.init();
  _listenForMessages();
  if (cryptoService.publicKeyBase64 != null) {
    websocketService.connect(cryptoService.publicKeyBase64!);
  }
  runApp(const MyApp());
}

void _listenForMessages() {
  websocketService.stream.listen((messageJson) async {
    try {
      final messageData = json.decode(messageJson) as Map<String, dynamic>;
      final senderKey = messageData['sender_pubkey'] as String?;
      final type = messageData['type'] as String?;

      if (senderKey == null) return;

      // --- ГЛАВНЫЙ ДИСПЕТЧЕР ---
      if (type == 'call-offer') {
        // ВХОДЯЩИЙ ЗВОНОК!
        print("<<< Получен входящий звонок от $senderKey");
        final data = messageData['data'] as Map<String, dynamic>;
        // Навигируемся на экран звонка, передавая данные
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (context) => CallScreen(
            contactPublicKey: senderKey,
            offer: data, // Передаем offer, чтобы экран знал, что мы отвечаем
          ),
        ));

      } else if (type == 'call-answer' || type == 'ice-candidate' || type == 'hang-up') {
        // Другие сигналы просто пересылаем на активный экран звонка
        print("<<< Получен сигнал '$type' от $senderKey");
        signalingStreamController.add(messageData);

      } else { // Если type не указан или "chat"
        // Это обычное сообщение чата
        final payload = messageData['payload'] as String?;
        if (payload != null) {
          final decryptedMessage = await cryptoService.decrypt(senderKey, payload);
          final receivedMessage = ChatMessage(text: decryptedMessage, isSentByMe: false);
          await DatabaseService.instance.addMessage(receivedMessage, senderKey);
          messageUpdateController.add(senderKey);
        }
      }
    } catch (e) { print("Ошибка обработки входящего сообщения: $e"); }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // ... (код _MyAppState остается без изменений)
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      websocketService.disconnect();
      if (cryptoService.publicKeyBase64 != null) {
        websocketService.connect(cryptoService.publicKeyBase64!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orpheus Client',
      theme: AppTheme.lightTheme,
      // Устанавливаем глобальный ключ навигатора
      navigatorKey: navigatorKey,
      home: const ContactsScreen(),
    );
  }
}