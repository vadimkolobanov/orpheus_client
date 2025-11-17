// lib/chat_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:orpheus_project/call_screen.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/config.dart'; // <-- Импорт конфигурации

class ChatScreen extends StatefulWidget {
  final Contact contact;
  const ChatScreen({super.key, required this.contact});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  List<ChatMessage> _chatHistory = [];
  late StreamSubscription _messageUpdateSubscription;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    _messageUpdateSubscription = messageUpdateController.stream.listen((senderKey) {
      if (senderKey == widget.contact.publicKey) {
        _loadChatHistory();
      }
    });
  }

  Future<void> _loadChatHistory() async {
    final history = await DatabaseService.instance.getMessagesForContact(widget.contact.publicKey);
    setState(() {
      _chatHistory = history;
    });
  }

  @override
  void dispose() {
    _messageUpdateSubscription.cancel();
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final messageText = _messageController.text;
    if (messageText.isEmpty) return;
    final sentMessage = ChatMessage(text: messageText, isSentByMe: true);
    await DatabaseService.instance.addMessage(sentMessage, widget.contact.publicKey);
    try {
      final payload = await cryptoService.encrypt(widget.contact.publicKey, messageText);
      websocketService.sendChatMessage(widget.contact.publicKey, payload);
    } catch (e) {
      print("Ошибка отправки: $e");
    }
    _messageController.clear();
    _loadChatHistory();
  }

  void _showClearHistoryDialog() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Очистить историю'),
          content: const Text('Вы уверены, что хотите удалить все сообщения в этом чате?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            TextButton(
                child: const Text('Удалить', style: TextStyle(color: Colors.red)),
                onPressed: () async {
                  await DatabaseService.instance.clearChatHistory(widget.contact.publicKey);
                  Navigator.pop(context);
                  _loadChatHistory();
                }),
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        // ВЕРСИЯ И ОБЛАЧКО В TITLE
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Зеленое облачко (можно заменить на свой виджет статуса)
            const Icon(Icons.cloud_rounded, color: Colors.green, size: 26),

            // Отступ между облачком и версией
            const SizedBox(width: 6),

            // Текст с версией приложения
            Text(
              AppConfig.appVersion,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),

            // Отступ между версией и именем контакта
            const SizedBox(width: 12),

            // Имя контакта
            Flexible(
              child: Text(
                widget.contact.name,
                style: const TextStyle(fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        // Кнопки действий в AppBar
        actions: [
          // Кнопка звонка
          IconButton(
            icon: const Icon(Icons.call_outlined, size: 26),
            tooltip: 'Позвонить',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => CallScreen(contactPublicKey: widget.contact.publicKey),
              ));
            },
          ),
          // Кнопка очистки истории
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Очистить историю чата',
            onPressed: _showClearHistoryDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Список сообщений
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              itemCount: _chatHistory.length,
              itemBuilder: (context, index) {
                final message = _chatHistory.reversed.toList()[index];
                final isMyMessage = message.isSentByMe;

                return Align(
                  alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: isMyMessage ? Theme.of(context).colorScheme.primary : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 5, offset: const Offset(0, 2))
                        ],
                      ),
                      child: Text(
                        message.text,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: isMyMessage ? Colors.white : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Поле ввода сообщения
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [BoxShadow(offset: const Offset(0, -2), blurRadius: 4, color: Colors.black.withOpacity(0.03))],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: const InputDecoration(
                        hintText: 'Сообщение...',
                        filled: false,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
