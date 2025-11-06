// lib/main.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:orpheus_project/contacts_screen.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/theme/app_theme.dart'; // <-- ИМПОРТИРУЕМ НАШ НОВЫЙ ФАЙЛ С ТЕМОЙ

final cryptoService = CryptoService();
final websocketService = WebSocketService();
final StreamController<String> messageUpdateController = StreamController.broadcast();

void main() async {
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
      final payload = messageData['payload'] as String?;
      if (senderKey != null && payload != null) {
        final decryptedMessage = await cryptoService.decrypt(senderKey, payload);
        final receivedMessage = ChatMessage(text: decryptedMessage, isSentByMe: false);
        await DatabaseService.instance.addMessage(receivedMessage, senderKey);
        messageUpdateController.add(senderKey);
      }
    } catch (e) {
      print("Ошибка обработки входящего сообщения: $e");
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
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
      // --- ВСЯ ТЕМА ТЕПЕРЬ БЕРЕТСЯ ИЗ ОДНОГО МЕСТА ---
      theme: AppTheme.lightTheme,
      home: const ContactsScreen(),
    );
  }
}