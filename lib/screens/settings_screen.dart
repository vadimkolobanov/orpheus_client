import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/screens/debug_logs_screen.dart';
import 'package:orpheus_project/screens/help_screen.dart';
import 'package:orpheus_project/screens/security_settings_screen.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/device_settings_service.dart';
import 'package:orpheus_project/services/update_service.dart';
import 'package:orpheus_project/updates_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with TickerProviderStateMixin {
  // Счётчик тапов для скрытого меню отладки
  int _secretTapCount = 0;
  DateTime? _lastTapTime;
  
  // Анимации
  late AnimationController _qrGlowController;
  late AnimationController _revealController;
  late AnimationController _pulseController;
  late AnimationController _scanLineController;
  late AnimationController _statsCounterController;
  
  // Состояние копирования
  bool _isCopied = false;
  
  // Статистика
  Map<String, int> _stats = {'contacts': 0, 'messages': 0, 'sent': 0};

  // App info (реальная версия/билд из платформы)
  String? _appVersionLabel;

  @override
  void initState() {
    super.initState();
    
    // QR glow анимация
    _qrGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    
    // Reveal анимация
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    
    // Пульсация
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    // Scan line на QR
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    
    // Счётчик статистики
    _statsCounterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _loadStats();
    _loadAppInfo();
  }
  
  Future<void> _loadStats() async {
    final stats = await DatabaseService.instance.getProfileStats();
    if (mounted) {
      setState(() {
        _stats = stats;
      });
      _statsCounterController.forward();
    }
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        // Пример: 1.0.0+5
        _appVersionLabel = '${info.version}+${info.buildNumber}';
      });
    } catch (e) {
      // Не критично — просто остаёмся на fallback версии из AppConfig
      DebugLogger.warn('APPINFO', 'Не удалось получить версию приложения: $e');
    }
  }

  @override
  void dispose() {
    _qrGlowController.dispose();
    _revealController.dispose();
    _pulseController.dispose();
    _scanLineController.dispose();
    _statsCounterController.dispose();
    super.dispose();
  }

  void _handleSecretTap() {
    final now = DateTime.now();
    
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

  Future<void> _exportAccount() async {
    final LocalAuthentication auth = LocalAuthentication();

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

        showDialog(
          context: context,
          builder: (context) => _AnimatedExportDialog(privateKey: privateKey),
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

  void _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    setState(() => _isCopied = true);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF6AD394), size: 20),
            const SizedBox(width: 8),
            const Text("ID скопирован"),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _isCopied = false);
  }

  @override
  Widget build(BuildContext context) {
    final myKey = cryptoService.publicKeyBase64 ?? "Ошибка";

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _handleSecretTap,
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Icon(
                    Icons.person,
                    color: const Color(0xFFB0BEC5).withOpacity(0.5 + 0.5 * _pulseController.value),
                    size: 20,
                  );
                },
              ),
              const SizedBox(width: 8),
              const Text("ПРОФИЛЬ"),
            ],
          ),
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // QR КОД - главный элемент
            _buildAnimatedQRSection(myKey, 0),

            const SizedBox(height: 16),

            // ВАШ ID
            _buildAnimatedIdSection(myKey, 0.1),

            const SizedBox(height: 14),

            // КНОПКА ПОДЕЛИТЬСЯ
            _buildAnimatedShareButton(myKey, 0.2),

            const SizedBox(height: 20),
            
            // СТАТИСТИКА И ДАТА - компактная строка
            _buildCompactStatsRow(0.3),

            const SizedBox(height: 20),

            // МЕНЮ НАСТРОЕК - все пункты видны сразу
            _buildAnimatedSettingsItem(
              index: 0,
              delay: 0.4,
              icon: Icons.security,
              title: "Безопасность",
              subtitle: AuthService.instance.config.isPinEnabled 
                  ? "PIN-код включен" 
                  : "PIN-код не установлен",
              onTap: () => Navigator.push(
                context,
                _createPageRoute(const SecuritySettingsScreen()),
              ).then((_) {
                if (!mounted) return;
                setState(() {});
              }),
              accentColor: AuthService.instance.config.isPinEnabled 
                  ? const Color(0xFF6AD394) 
                  : Colors.orange,
            ),

            _buildAnimatedSettingsItem(
              index: 1,
              delay: 0.45,
              icon: Icons.help_outline,
              title: "Как пользоваться",
              subtitle: "Краткая инструкция по функциям",
              onTap: () => Navigator.push(
                context,
                _createPageRoute(const HelpScreen()),
              ),
              isSubtle: true,
            ),

            _buildAnimatedSettingsItem(
              index: 2,
              delay: 0.5,
              icon: Icons.history,
              title: "История обновлений",
              onTap: () => Navigator.push(
                context,
                _createPageRoute(const UpdatesScreen()),
              ),
            ),

            _buildAnimatedSettingsItem(
              index: 3,
              delay: 0.55,
              icon: Icons.shield_outlined,
              title: "Экспорт аккаунта",
              subtitle: "Показать Приватный ключ",
              isDestructive: true,
              onTap: _exportAccount,
            ),
            
            _buildAnimatedSettingsItem(
              index: 4,
              delay: 0.6,
              icon: Icons.notifications_none,
              title: "Настройка уведомлений",
              subtitle: "Для Android (Vivo, Xiaomi и др.)",
              onTap: () => DeviceSettingsService.showSetupDialog(context),
              isSubtle: true,
            ),
            
            const SizedBox(height: 20),
            
            // ВЕРСИЯ ПРИЛОЖЕНИЯ
            _buildVersionSection(0.55),
            
            const SizedBox(height: 24),
            
            // КНОПКА УДАЛЕНИЯ АККАУНТА
            _buildDeleteAccountButton(0.6),
            
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
  
  // Секция версии приложения
  Widget _buildVersionSection(double delay) {
    return AnimatedBuilder(
      animation: _revealController,
      builder: (context, child) {
        final progress = ((_revealController.value - delay) / (1 - delay)).clamp(0.0, 1.0);
        
        return Opacity(
          opacity: progress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.withOpacity(0.08),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade600, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Orpheus ${_appVersionLabel ?? AppConfig.appVersion}",
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (cryptoService.registrationDate != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          "Аккаунт создан ${DateFormat('dd.MM.yyyy').format(cryptoService.registrationDate!)}",
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => UpdateService.checkForUpdate(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    "Обновить",
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  // Кнопка удаления аккаунта
  Widget _buildDeleteAccountButton(double delay) {
    return AnimatedBuilder(
      animation: _revealController,
      builder: (context, child) {
        final progress = ((_revealController.value - delay) / (1 - delay)).clamp(0.0, 1.0);
        
        return Transform.translate(
          offset: Offset(0, 10 * (1 - progress)),
          child: Opacity(
            opacity: progress,
            child: TextButton(
              onPressed: _showDeleteAccountDialog,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    "Удалить аккаунт",
                    style: TextStyle(
                      color: Colors.red.shade400,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  // Диалог удаления аккаунта
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => _AnimatedDeleteAccountDialog(
        onDelete: () async {
          // Удаляем все данные
          await cryptoService.deleteAccount();
          await DatabaseService.instance.close();
          
          // Перезапуск приложения - выход на экран приветствия
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            // Показываем сообщение и закрываем приложение
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Аккаунт удалён. Перезапустите приложение."),
                duration: Duration(seconds: 3),
              ),
            );
          }
        },
      ),
    );
  }
  
  // Компактная строка статистики с анимацией
  Widget _buildCompactStatsRow(double delay) {
    return AnimatedBuilder(
      animation: Listenable.merge([_revealController, _statsCounterController]),
      builder: (context, child) {
        final progress = ((_revealController.value - delay) / (1 - delay)).clamp(0.0, 1.0);
        final counterProgress = Curves.easeOutCubic.transform(_statsCounterController.value);
        
        return Transform.translate(
          offset: Offset(0, 15 * (1 - progress)),
          child: Opacity(
            opacity: progress,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCompactStat(
                    value: (_stats['contacts']! * counterProgress).round(),
                    label: "контактов",
                    icon: Icons.people_outline,
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: Colors.white.withOpacity(0.08),
                  ),
                  _buildCompactStat(
                    value: (_stats['messages']! * counterProgress).round(),
                    label: "сообщений",
                    icon: Icons.chat_outlined,
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: Colors.white.withOpacity(0.08),
                  ),
                  _buildCompactStat(
                    value: (_stats['sent']! * counterProgress).round(),
                    label: "отправлено",
                    icon: Icons.send_outlined,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildCompactStat({
    required int value,
    required String label,
    required IconData icon,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.grey.shade500, size: 14),
            const SizedBox(width: 6),
            Text(
              value.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedQRSection(String myKey, double delay) {
    return AnimatedBuilder(
      animation: Listenable.merge([_revealController, _qrGlowController, _scanLineController]),
      builder: (context, child) {
        final progress = ((_revealController.value - delay) / (1 - delay)).clamp(0.0, 1.0);
        
        return Transform.translate(
          offset: Offset(0, 30 * (1 - progress)),
          child: Opacity(
            opacity: progress,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB0BEC5).withOpacity(0.2 + 0.15 * _qrGlowController.value),
                    blurRadius: 30 + 15 * _qrGlowController.value,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  QrImageView(
                    data: myKey,
                    version: QrVersions.auto,
                    size: 160.0,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF1A1A1A),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  // Scan line
                  Positioned(
                    top: _scanLineController.value * 160,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            const Color(0xFF6AD394).withOpacity(0.8),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6AD394).withOpacity(0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedIdSection(String myKey, double delay) {
    return AnimatedBuilder(
      animation: _revealController,
      builder: (context, child) {
        final progress = ((_revealController.value - delay) / (1 - delay)).clamp(0.0, 1.0);
        
        return Transform.translate(
          offset: Offset(0, 20 * (1 - progress)),
          child: Opacity(
            opacity: progress,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6AD394).withOpacity(0.5 + 0.5 * _pulseController.value),
                            shape: BoxShape.circle,
                          ),
                        );
                      },
                    ),
                    const Text(
                      "ВАШ ID",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6AD394).withOpacity(0.5 + 0.5 * _pulseController.value),
                            shape: BoxShape.circle,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ТЕКСТОВЫЙ КЛЮЧ
                AnimatedBuilder(
                  animation: _qrGlowController,
                  builder: (context, child) {
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _copyToClipboard(myKey),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121212),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _isCopied
                                  ? const Color(0xFF6AD394).withOpacity(0.5)
                                  : const Color(0xFFB0BEC5).withOpacity(0.1 + 0.1 * _qrGlowController.value),
                              width: _isCopied ? 2 : 1,
                            ),
                            boxShadow: _isCopied
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF6AD394).withOpacity(0.2),
                                      blurRadius: 15,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  myKey,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Color(0xFFECEFF1),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 12),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: _isCopied
                                    ? const Icon(Icons.check, size: 18, color: Color(0xFF6AD394), key: ValueKey('check'))
                                    : Icon(Icons.copy, size: 18, color: Colors.grey.shade600, key: const ValueKey('copy')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedShareButton(String myKey, double delay) {
    return AnimatedBuilder(
      animation: Listenable.merge([_revealController, _pulseController]),
      builder: (context, child) {
        final progress = ((_revealController.value - delay) / (1 - delay)).clamp(0.0, 1.0);
        
        return Transform.translate(
          offset: Offset(0, 20 * (1 - progress)),
          child: Opacity(
            opacity: progress,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB0BEC5).withOpacity(0.15 + 0.1 * _pulseController.value),
                    blurRadius: 15,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.share, size: 20),
                  label: const Text("ПОДЕЛИТЬСЯ КОНТАКТОМ", style: TextStyle(letterSpacing: 1)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB0BEC5),
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Share.share("Привет! Добавь меня в Orpheus.\nМой ключ:\n$myKey");
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedSettingsItem({
    required int index,
    required double delay,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
    bool isSubtle = false,
    Color? accentColor,
  }) {
    final effectiveColor = accentColor ?? (isDestructive 
        ? Colors.red.shade400 
        : isSubtle 
            ? Colors.grey.shade600 
            : const Color(0xFFB0BEC5));
    
    return AnimatedBuilder(
      animation: Listenable.merge([_revealController, _qrGlowController]),
      builder: (context, child) {
        final progress = ((_revealController.value - delay) / (1 - delay)).clamp(0.0, 1.0);
        
        return Transform.translate(
          offset: Offset(0, 20 * (1 - progress)),
          child: Opacity(
            opacity: progress,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDestructive
                      ? Colors.red.withOpacity(0.1 + 0.05 * _qrGlowController.value)
                      : Colors.white.withOpacity(0.05),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: effectiveColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, color: effectiveColor.withOpacity(0.8), size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: isDestructive ? Colors.red.shade300 : Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: Colors.grey.shade700, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  PageRouteBuilder _createPageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}

// Анимированный диалог экспорта
class _AnimatedExportDialog extends StatefulWidget {
  final String privateKey;
  const _AnimatedExportDialog({required this.privateKey});

  @override
  State<_AnimatedExportDialog> createState() => _AnimatedExportDialogState();
}

class _AnimatedExportDialogState extends State<_AnimatedExportDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: AlertDialog(
              backgroundColor: const Color(0xFF150505),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.red.withOpacity(0.3)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.warning, color: Colors.red, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text("ПРИВАТНЫЙ КЛЮЧ", style: TextStyle(color: Colors.red)),
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
                      border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      widget.privateKey,
                      style: const TextStyle(fontFamily: 'monospace', color: Colors.redAccent, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text("КОПИРОВАТЬ"),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: widget.privateKey));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Ключ скопирован в буфер обмена")),
                        );
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("ЗАКРЫТЬ", style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Анимированный диалог удаления аккаунта
class _AnimatedDeleteAccountDialog extends StatefulWidget {
  final VoidCallback onDelete;
  const _AnimatedDeleteAccountDialog({required this.onDelete});

  @override
  State<_AnimatedDeleteAccountDialog> createState() => _AnimatedDeleteAccountDialogState();
}

class _AnimatedDeleteAccountDialogState extends State<_AnimatedDeleteAccountDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      ),
      child: FadeTransition(
        opacity: _controller,
        child: AlertDialog(
          backgroundColor: const Color(0xFF120505),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.red.withOpacity(0.3)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete_forever, color: Colors.red, size: 24),
              ),
              const SizedBox(width: 14),
              const Text(
                'Удалить аккаунт?',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Это действие удалит:',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              ),
              const SizedBox(height: 12),
              _buildDeleteItem(Icons.key, "Ваши криптографические ключи"),
              _buildDeleteItem(Icons.chat_bubble_outline, "Всю историю сообщений"),
              _buildDeleteItem(Icons.people_outline, "Список контактов"),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.red.shade300, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Восстановить данные будет невозможно!',
                        style: TextStyle(
                          color: Colors.red.shade300,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Чекбокс подтверждения
              GestureDetector(
                onTap: () => setState(() => _confirmed = !_confirmed),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _confirmed ? Colors.red : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _confirmed ? Colors.red : Colors.grey.shade600,
                          width: 2,
                        ),
                      ),
                      child: _confirmed
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Я понимаю, что это необратимо',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _confirmed ? Colors.red.shade700 : Colors.grey.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _confirmed
                        ? () {
                            Navigator.pop(context);
                            widget.onDelete();
                          }
                        : null,
                    child: const Text('Удалить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 16),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
