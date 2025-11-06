// lib/models/chat_message_model.dart

class ChatMessage {
  final String text;
  final bool isSentByMe;

  ChatMessage({required this.text, required this.isSentByMe});
}