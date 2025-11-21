// lib/chat_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orpheus_project/call_screen.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/services/database_service.dart';

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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    // При входе сразу помечаем прочитанными
    _markAsRead();

    _messageUpdateSubscription = messageUpdateController.stream.listen((senderKey) {
      if (senderKey == widget.contact.publicKey) {
        _loadChatHistory();
        _markAsRead(); // Если пришло новое, пока мы в чате - сразу читаем
      }
    });
  }

  Future<void> _loadChatHistory() async {
    final history = await DatabaseService.instance.getMessagesForContact(widget.contact.publicKey);
    if (mounted) {
      setState(() {
        _chatHistory = history;
      });
      // Скролл вниз после загрузки
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _markAsRead() async {
    await DatabaseService.instance.markMessagesAsRead(widget.contact.publicKey);
    // Уведомляем глобально, чтобы обновился счетчик в списке контактов
    // (Это можно сделать через отдельный Stream, но пока используем обновление UI)
  }

  @override
  void dispose() {
    _messageUpdateSubscription.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    final sentMessage = ChatMessage(
        text: messageText,
        isSentByMe: true,
        status: MessageStatus.sent, // Пока просто sent
        isRead: true
    );

    await DatabaseService.instance.addMessage(sentMessage, widget.contact.publicKey);

    try {
      final payload = await cryptoService.encrypt(widget.contact.publicKey, messageText);
      websocketService.sendChatMessage(widget.contact.publicKey, payload);
      // Тут можно обновить статус на 'delivered' если бы сервер отвечал подтверждением
    } catch (e) {
      print("Ошибка отправки: $e");
      // Тут можно обновить статус на 'failed'
    }

    _messageController.clear();
    _loadChatHistory();
  }

  void _showClearHistoryDialog() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Очистить историю'),
          content: const Text('Вы уверены, что хотите удалить все сообщения?'),
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

  // --- Виджет одного сообщения ---
  Widget _buildMessageItem(ChatMessage message) {
    final isMyMessage = message.isSentByMe;
    final timeStr = DateFormat('HH:mm').format(message.timestamp);

    return Align(
      alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: isMyMessage ? Theme.of(context).colorScheme.primary : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMyMessage ? const Radius.circular(16) : Radius.zero,
              bottomRight: isMyMessage ? Radius.zero : const Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3, offset: const Offset(0, 1))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Текст сообщения
              Text(
                message.text,
                style: TextStyle(
                  fontSize: 16,
                  color: isMyMessage ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),

              // Строка статуса (время + иконки)
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Для понта: иконка замка (шифрование)
                  Icon(
                    Icons.lock_outline,
                    size: 10,
                    color: isMyMessage ? Colors.white70 : Colors.grey,
                  ),
                  const SizedBox(width: 4),

                  // Время
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: isMyMessage ? Colors.white70 : Colors.grey,
                    ),
                  ),

                  // Статус (галочки) только для моих сообщений
                  if (isMyMessage) ...[
                    const SizedBox(width: 4),
                    Icon(
                      // Логика иконок: Sent -> одна галочка, Read -> две галочки (синие или белые)
                      // Пока у нас нет receipts от сервера, ставим одну галочку "Sent"
                      Icons.done,
                      size: 14,
                      color: Colors.white,
                    ),
                  ]
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F7), // Светло-серый фон чата
      appBar: AppBar(
        title: Row(
          children: [
            // Аватарка в AppBar
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              child: Text(
                widget.contact.name[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.contact.name, style: const TextStyle(fontSize: 18)),
                  // Статус "В сети" (фейковый или реальный, если допилим presense)
                  const Text(
                    "Orpheus Secure",
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (context) => CallScreen(contactPublicKey: widget.contact.publicKey))),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showClearHistoryDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              reverse: true, // Список снизу вверх
              itemCount: _chatHistory.length,
              itemBuilder: (context, index) {
                // reverse: true переворачивает массив визуально, но нам нужно брать с конца
                final message = _chatHistory.reversed.toList()[index];
                return _buildMessageItem(message);
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.grey),
              onPressed: () {}, // Заглушка для аттачей
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Сообщение...',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  maxLines: null, // Многострочный ввод
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 18),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}