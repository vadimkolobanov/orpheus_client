class RoomMessage {
  final String id;
  final String text;
  final String? senderKey;
  final String? senderName;
  final String? authorType;
  final DateTime createdAt;
  final bool isSystem;
  final String? systemCode;

  RoomMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    this.senderKey,
    this.senderName,
    this.authorType,
    this.isSystem = false,
    this.systemCode,
  });

  factory RoomMessage.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'];
    DateTime createdAt = DateTime.now().toUtc();
    if (createdAtRaw is String) {
      createdAt = _parseServerDateTime(createdAtRaw);
    } else if (createdAtRaw is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtRaw, isUtc: true);
    }

    final text = (json['text'] as String?) ?? (json['message'] as String?) ?? '';

    return RoomMessage(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      senderKey: json['sender_pubkey'] as String?,
      senderName: json['sender_name'] as String?,
      authorType: json['author_type'] as String? ?? json['sender_type'] as String?,
      createdAt: createdAt,
      isSystem: json['is_system'] == true || json['type'] == 'system',
      systemCode: json['system_code'] as String?,
    );
  }
}

DateTime _parseServerDateTime(String raw) {
  final hasTimezone =
      raw.endsWith('Z') || RegExp(r'[+\-]\d{2}:?\d{2}$').hasMatch(raw);
  final normalized = hasTimezone ? raw : '${raw}Z';
  final parsed = DateTime.tryParse(normalized);
  return parsed?.toUtc() ?? DateTime.now().toUtc();
}
