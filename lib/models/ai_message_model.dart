/// Модель сообщения в чате с AI помощником.
/// 
/// Поддерживает роли: user (пользователь), assistant (AI), system (системные).
class AiMessage {
  final String id;
  final AiMessageRole role;
  final String content;
  final DateTime createdAt;
  final bool isError;

  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isError = false,
  });

  /// Создаёт сообщение пользователя.
  factory AiMessage.user(String content) {
    return AiMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: AiMessageRole.user,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  /// Создаёт сообщение от AI.
  factory AiMessage.assistant(String content) {
    return AiMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: AiMessageRole.assistant,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  /// Создаёт сообщение об ошибке.
  factory AiMessage.error(String content) {
    return AiMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: AiMessageRole.assistant,
      content: content,
      createdAt: DateTime.now(),
      isError: true,
    );
  }

  /// Преобразует в JSON для API.
  Map<String, dynamic> toApiJson() {
    return {
      'role': role.name,
      'content': content,
    };
  }

  /// Копия с изменениями.
  AiMessage copyWith({
    String? id,
    AiMessageRole? role,
    String? content,
    DateTime? createdAt,
    bool? isError,
  }) {
    return AiMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isError: isError ?? this.isError,
    );
  }
}

/// Роль в диалоге с AI.
enum AiMessageRole {
  user,
  assistant,
  system,
}
