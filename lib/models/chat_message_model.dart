// lib/models/chat_message_model.dart

enum MessageStatus { sending, sent, delivered, read, failed }

class ChatMessage {
  final int? id; // Добавим ID для точного обновления
  final String text;
  final bool isSentByMe;
  final DateTime timestamp;
  final MessageStatus status;
  final bool isRead; // Прочитано ли сообщение (для входящих)

  ChatMessage({
    this.id,
    required this.text,
    required this.isSentByMe,
    DateTime? timestamp,
    this.status = MessageStatus.sent, // По дефолту считаем отправленным
    this.isRead = true, // Свои сообщения всегда прочитаны, чужие - зависит
  }) : timestamp = timestamp ?? DateTime.now();

  // Конвертация статуса в int для БД
  static int _statusToInt(MessageStatus status) => status.index;
  static MessageStatus _intToStatus(int index) => MessageStatus.values[index];

  Map<String, dynamic> toMap(String contactKey) {
    return {
      'contactPublicKey': contactKey,
      'text': text,
      'isSentByMe': isSentByMe ? 1 : 0,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'status': _statusToInt(status),
      'isRead': isRead ? 1 : 0,
    };
  }
}