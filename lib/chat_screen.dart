// lib/chat_screen.dart
// (Импорты остаются те же)
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

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _messageController = TextEditingController();
  List<ChatMessage> _chatHistory = [];
  late StreamSubscription _messageUpdateSubscription;
  final ScrollController _scrollController = ScrollController();
  
  // Анимация шифрования
  late AnimationController _encryptionController;
  bool _isEncrypting = false;

  @override
  void initState() {
    super.initState();
    _encryptionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _loadChatHistory();
    _markAsRead();

    _messageUpdateSubscription = messageUpdateController.stream.listen((senderKey) {
      if (senderKey == widget.contact.publicKey) {
        _loadChatHistory();
        _markAsRead();
      }
    });
  }

  Future<void> _loadChatHistory() async {
    final history = await DatabaseService.instance.getMessagesForContact(widget.contact.publicKey);
    if (mounted) {
      setState(() {
        _chatHistory = history;
      });
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
  }

  @override
  void dispose() {
    _messageUpdateSubscription.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _encryptionController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    // Запускаем анимацию шифрования
    setState(() => _isEncrypting = true);
    _encryptionController.reset();
    _encryptionController.forward();

    final sentMessage = ChatMessage(
        text: messageText,
        isSentByMe: true,
        status: MessageStatus.sent,
        isRead: true
    );

    await DatabaseService.instance.addMessage(sentMessage, widget.contact.publicKey);
    try {
      final payload = await cryptoService.encrypt(widget.contact.publicKey, messageText);
      websocketService.sendChatMessage(widget.contact.publicKey, payload);
    } catch (e) {
      print("Ошибка отправки: $e");
    }
    
    // Завершаем анимацию
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _isEncrypting = false);
    }
    
    _messageController.clear();
    _loadChatHistory();
  }

  void _showClearHistoryDialog() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Удалить историю?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ОТМЕНА')),
            TextButton(
                child: const Text('УДАЛИТЬ', style: TextStyle(color: Colors.red)),
                onPressed: () async {
                  await DatabaseService.instance.clearChatHistory(widget.contact.publicKey);
                  Navigator.pop(context);
                  _loadChatHistory();
                }),
          ],
        ));
  }

  // --- ВИДЖЕТ СООБЩЕНИЯ ---
  Widget _buildMessageItem(ChatMessage message) {
    final isMyMessage = message.isSentByMe;
    final timeStr = DateFormat('HH:mm').format(message.timestamp);

    // Цвета пузырей под новый стиль
    final bubbleColor = isMyMessage
        ? const Color(0xFFB0BEC5) // Моё: Светлое серебро
        : const Color(0xFF263238); // Чужое: Темный Gunmetal

    final textColor = isMyMessage ? Colors.black : Colors.white;
    final metaColor = isMyMessage ? Colors.black54 : Colors.white54;

    return Align(
      alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: bubbleColor.withOpacity(0.9),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: isMyMessage ? const Radius.circular(12) : Radius.zero,
              bottomRight: isMyMessage ? Radius.zero : const Radius.circular(12),
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.text,
                style: TextStyle(fontSize: 16, color: textColor),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Иконка замка
                  Icon(Icons.lock, size: 10, color: metaColor),
                  const SizedBox(width: 4),
                  // Время
                  Text(timeStr, style: TextStyle(fontSize: 11, color: metaColor)),

                  if (isMyMessage) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.done_all, size: 14, color: Colors.black), // Черная галочка на светлом фоне
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
      // Черный фон чата
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF101010),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFB0BEC5),
              child: Text(
                widget.contact.name[0].toUpperCase(),
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.contact.name, style: const TextStyle(fontSize: 16, color: Colors.white)),
                  const Text(
                    "ENCRYPTED",
                    style: TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            color: const Color(0xFFB0BEC5),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (context) => CallScreen(contactPublicKey: widget.contact.publicKey))),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: Colors.red[300],
            onPressed: _showClearHistoryDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              reverse: true,
              itemCount: _chatHistory.length,
              itemBuilder: (context, index) {
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: const Color(0xFF101010),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end, // Выравнивание по низу, чтобы кнопка не прыгала
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF202020).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: Colors.white),

                  // --- ИСПРАВЛЕНИЕ ЗДЕСЬ ---
                  maxLines: null, // Разрешаем перенос строк
                  keyboardType: TextInputType.multiline, // Клавиатура с кнопкой Enter
                  minLines: 1, // Минимальная высота
                  // -------------------------

                  decoration: const InputDecoration(
                    hintText: 'Сообщение...',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Кнопка отправки с анимацией шифрования
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              child: AnimatedBuilder(
                animation: _encryptionController,
                builder: (context, child) {
                  if (_isEncrypting) {
                    return Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF6AD394).withOpacity(0.2),
                        border: Border.all(
                          color: const Color(0xFF6AD394),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6AD394).withOpacity(0.5),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: RotationTransition(
                        turns: Tween(begin: 0.0, end: 1.0).animate(
                          CurvedAnimation(
                            parent: _encryptionController,
                            curve: Curves.linear,
                          ),
                        ),
                        child: const Icon(Icons.lock, color: Color(0xFF6AD394), size: 20),
                      ),
                    );
                  }
                  return CircleAvatar(
                    backgroundColor: const Color(0xFFB0BEC5),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.black, size: 18),
                      onPressed: _sendMessage,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }}