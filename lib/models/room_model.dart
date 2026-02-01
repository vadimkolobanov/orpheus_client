class Room {
  final String id;
  final String name;
  final bool isOwner;
  final int membersCount;
  final String? inviteCode;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;

  Room({
    required this.id,
    required this.name,
    this.isOwner = false,
    this.membersCount = 0,
    this.inviteCode,
    this.lastMessageAt,
    this.lastMessagePreview,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final name = (json['name'] as String?)?.trim() ?? 'Room';
    final membersCount = (json['members_count'] as num?)?.toInt() ?? 0;
    final inviteCode = json['invite_code'] as String?;
    final lastMessagePreview = json['last_message'] as String?;
    final lastMessageAtRaw = json['last_message_at'];
    DateTime? lastMessageAt;
    if (lastMessageAtRaw is String) {
      lastMessageAt = DateTime.tryParse(lastMessageAtRaw);
    } else if (lastMessageAtRaw is int) {
      lastMessageAt = DateTime.fromMillisecondsSinceEpoch(lastMessageAtRaw);
    }

    return Room(
      id: id,
      name: name,
      isOwner: json['is_owner'] == true,
      membersCount: membersCount,
      inviteCode: inviteCode,
      lastMessageAt: lastMessageAt,
      lastMessagePreview: lastMessagePreview,
    );
  }
}

class RoomCreateResult {
  final Room room;
  final String inviteCode;

  RoomCreateResult({
    required this.room,
    required this.inviteCode,
  });
}
