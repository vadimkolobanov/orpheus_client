import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:orpheus_project/main.dart'; // cryptoService
import 'package:orpheus_project/screens/debug_logs_screen.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/device_settings_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/updates_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Счётчик тапов для скрытого меню отладки
  int _secretTapCount = 0;
  DateTime? _lastTapTime;

  /// Обработчик секретного тапа для открытия логов
  void _handleSecretTap() {
    final now = DateTime.now();
    
    // Сбрасываем счётчик если прошло больше 2 секунд
    if (_lastTapTime != null && now.difference(_lastTapTime!).inSeconds > 2) {
      _secretTapCount = 0;
    }
    
    _lastTapTime = now;
    _secretTapCount++;
    
    if (_secretTapCount >= 5) {
      _secretTapCount = 0;
      DebugLogger.info('UI', 'Debug logs screen opened via secret tap');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const DebugLogsScreen()),
      );
    }
  }
  // Экспорт приватного ключа с биометрией
  Future<void> _exportAccount() async {
    final LocalAuthentication auth = LocalAuthentication();

    // Проверка доступности биометрии
    final bool canAuth = await auth.canCheckBiometrics || await auth.isDeviceSupported();

    if (!canAuth) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Биометрия недоступна. Настройте безопасность устройства.")),
        );
      }
      return;
    }

    try {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Подтвердите личность для экспорта ключей',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );

      if (didAuthenticate) {
        final privateKey = await cryptoService.getPrivateKeyBase64();
        if (!mounted) return;

        // Показываем ключ в диалоге с предупреждением
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF200000), // Темно-красный фон опасности
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 10),
                Text("ПРИВАТНЫЙ КЛЮЧ", style: TextStyle(color: Colors.red)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Никому не показывайте этот ключ. Владение им дает полный доступ к вашему аккаунту.",
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.redAccent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    privateKey,
                    style: const TextStyle(fontFamily: 'monospace', color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  icon: const Icon(Icons.copy, color: Colors.white),
                  label: const Text("КОПИРОВАТЬ", style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: privateKey));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Ключ скопирован в буфер обмена")),
                    );
                  },
                )
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("ЗАКРЫТЬ", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print("Auth error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ошибка аутентификации")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myKey = cryptoService.publicKeyBase64 ?? "Ошибка";

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _handleSecretTap,
          child: const Text("ПРОФИЛЬ"),
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // QR КОД
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: QrImageView(
                data: myKey,
                version: QrVersions.auto,
                size: 220.0,
                backgroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 30),

            const Text(
              "ВАШ ID",
              style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),

            // ТЕКСТОВЫЙ КЛЮЧ
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: myKey));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ID скопирован")));
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12)
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        myKey,
                        style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFECEFF1), fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // КНОПКА ПОДЕЛИТЬСЯ
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.share, size: 20),
                label: const Text("ПОДЕЛИТЬСЯ КОНТАКТОМ"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB0BEC5), // Серебро
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Share.share("Привет! Добавь меня в Orpheus.\nМой ключ:\n$myKey");
                },
              ),
            ),

            const SizedBox(height: 40),

            // МЕНЮ НАСТРОЕК
            _buildSettingsItem(
              icon: Icons.notifications_active_outlined,
              title: "Настройка уведомлений",
              subtitle: "Помощь для Android (Vivo, Xiaomi и др.)",
              onTap: () => DeviceSettingsService.showSetupDialog(context),
            ),
            
            _buildSettingsItem(
              icon: Icons.bug_report_outlined,
              title: "Тест уведомлений",
              subtitle: "Проверить работу FCM",
              onTap: () async {
                final service = NotificationService();
                final token = service.fcmToken;
                
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: const Text("Диагностика FCM", style: TextStyle(color: Colors.white)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("FCM Token: ${token ?? 'НЕ ПОЛУЧЕН'}", 
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () async {
                            // Тестовое локальное уведомление
                            await NotificationService.showTestNotification();
                            if (context.mounted) Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Тестовое уведомление отправлено")),
                            );
                          },
                          child: const Text("Отправить тестовое уведомление"),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Закрыть"),
                      ),
                    ],
                  ),
                );
              },
            ),
            
            _buildSettingsItem(
              icon: Icons.history,
              title: "История обновлений",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UpdatesScreen())),
            ),

            _buildSettingsItem(
              icon: Icons.shield_outlined,
              title: "Экспорт аккаунта",
              subtitle: "Показать Приватный ключ",
              isDestructive: true,
              onTap: _exportAccount,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        leading: Icon(icon, color: isDestructive ? Colors.redAccent : Colors.white70),
        title: Text(title, style: TextStyle(color: isDestructive ? Colors.redAccent : Colors.white)),
        subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)) : null,
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}