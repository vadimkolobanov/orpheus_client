// lib/models/support_message.dart
// Модель сообщения чата поддержки

enum MessageDirection { user, admin }

class SupportMessage {
  final int id;
  final MessageDirection direction;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  SupportMessage({
    required this.id,
    required this.direction,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    return SupportMessage(
      id: json['id'] as int,
      direction: json['direction'] == 'admin' 
          ? MessageDirection.admin 
          : MessageDirection.user,
      message: json['message'] as String,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'direction': direction == MessageDirection.admin ? 'admin' : 'user',
    'message': message,
    'is_read': isRead,
    'created_at': createdAt.toIso8601String(),
  };

  /// Проверяет, является ли сообщение системным (например, "📎 Debug-логи отправлены")
  bool get isSystemMessage => message.startsWith('📎');
}


