import 'package:shared_preferences/shared_preferences.dart';

/// Локальные настройки уведомлений (client-side, без сервера).
class NotificationPrefsService {
  static const String _orpheusOfficialEnabledKey =
      'notif_orpheus_official_enabled_v1';

  /// Уведомления о "Официальном ответе Орфея".
  static Future<bool> isOrpheusOfficialEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_orpheusOfficialEnabledKey) ?? true;
  }

  static Future<void> setOrpheusOfficialEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_orpheusOfficialEnabledKey, enabled);
  }
}
