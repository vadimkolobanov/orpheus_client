import 'dart:convert';

class DesktopSession {
  DesktopSession({
    required this.desktopId,
    required this.desktopName,
    required this.desktopPubkey,
    required this.lanIp,
    required this.lanPort,
    required this.sessionToken,
    required this.otp,
    required this.phoneName,
    required this.createdAt,
  });

  final String desktopId;
  final String desktopName;
  final String desktopPubkey;
  final String lanIp;
  final int lanPort;
  final String sessionToken;
  final String otp;
  final String phoneName;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'desktop_id': desktopId,
        'desktop_name': desktopName,
        'desktop_pubkey': desktopPubkey,
        'lan_ip': lanIp,
        'lan_port': lanPort,
        'session_token': sessionToken,
        'otp': otp,
        'phone_name': phoneName,
        'created_at': createdAt.toIso8601String(),
      };

  String toJson() => json.encode(toMap());

  static DesktopSession fromMap(Map<String, dynamic> map) {
    return DesktopSession(
      desktopId: map['desktop_id'] as String,
      desktopName: map['desktop_name'] as String,
      desktopPubkey: map['desktop_pubkey'] as String,
      lanIp: map['lan_ip'] as String,
      lanPort: map['lan_port'] as int,
      sessionToken: map['session_token'] as String,
      otp: map['otp'] as String,
      phoneName: map['phone_name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static DesktopSession? tryFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return DesktopSession.fromMap(map);
    } catch (_) {
      return null;
    }
  }
}
