// lib/screens/security_settings_screen.dart
// Экран настроек безопасности

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:orpheus_project/models/message_retention_policy.dart';
import 'package:orpheus_project/screens/pin_setup_screen.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/message_cleanup_service.dart';

class SecuritySettingsScreen extends StatefulWidget {
  final AuthService auth;

  SecuritySettingsScreen({super.key, AuthService? auth})
      : auth = auth ?? AuthService.instance;

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> with SingleTickerProviderStateMixin {
  late final AuthService _auth;
  final _localAuth = LocalAuthentication();
  
  bool _canUseBiometrics = false;
  late AnimationController _revealController;

  @override
  void initState() {
    super.initState();
    _auth = widget.auth;
    
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    
    _checkBiometrics();
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    try {
      final canAuth = await _localAuth.canCheckBiometrics || 
                      await _localAuth.isDeviceSupported();
      if (mounted) {
        setState(() => _canUseBiometrics = canAuth);
      }
    } catch (e) {
      print("Biometrics check error: $e");
    }
  }

  void _refresh() {
    setState(() {});
  }

  Future<void> _openPinSetup(PinSetupMode mode) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PinSetupScreen(
          mode: mode,
          onSuccess: _refresh,
        ),
      ),
    );
    
    if (result == true && mounted) {
      _refresh();
    }
  }

  Future<void> _onRetentionPolicyChanged(MessageRetentionPolicy newPolicy) async {
    // Получаем preview количества сообщений для удаления
    final toDelete = await MessageCleanupService.instance.getCleanupPreview(newPolicy);
    
    // Если будут удалены сообщения — запрашиваем подтверждение
    if (toDelete > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Подтверждение'),
          content: Text(
            'При включении этой политики будет удалено $toDelete сообщений.\n\n'
            'Это действие необратимо. Продолжить?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Удалить'),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
    }
    
    // Применяем новую политику
    await _auth.setMessageRetention(newPolicy);
    
    // Запускаем очистку по новой политике
    final result = await MessageCleanupService.instance.onRetentionPolicyChanged(newPolicy);
    
    if (mounted) {
      _refresh();
      
      // Показываем результат
      final message = result.isSuccess && result.deletedCount > 0
          ? 'Удалено ${result.deletedCount} сообщений'
          : 'Политика применена: ${newPolicy.displayName}';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _toggleBiometrics(bool enabled) async {
    if (enabled) {
      // Проверяем, что биометрия доступна
      try {
        final didAuth = await _localAuth.authenticate(
          localizedReason: 'Подтвердите для включения биометрии',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
          ),
        );
        
        if (didAuth) {
          // TODO: Сохранить настройку биометрии в AuthService
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Биометрия включена')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось включить биометрию')),
        );
      }
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final config = _auth.config;
    final isPinEnabled = config.isPinEnabled;
    final isDuressEnabled = config.isDuressEnabled;
    final isWipeCodeEnabled = config.isWipeCodeEnabled;
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'БЕЗОПАСНОСТЬ',
          style: TextStyle(fontSize: 16, letterSpacing: 1),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Секция PIN-кода
            _buildSectionHeader('PIN-КОД', Icons.lock_outline),
            const SizedBox(height: 12),
            
            if (!isPinEnabled) ...[
              _buildInfoCard(
                icon: Icons.info_outline,
                text: 'PIN-код не установлен. Приложение открывается без защиты.',
                color: Colors.orange,
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                icon: Icons.add,
                title: 'Установить PIN-код',
                subtitle: '4 или 6-значный код для защиты входа',
                onTap: () => _openPinSetup(PinSetupMode.setPin),
              ),
            ] else ...[
              _buildPinStatusCard(config.pinLength),
              const SizedBox(height: 12),
              _buildActionButton(
                icon: Icons.edit,
                title: 'Изменить PIN-код',
                subtitle: '${config.pinLength}-значный код',
                onTap: () => _openPinSetup(PinSetupMode.changePin),
              ),
              const SizedBox(height: 8),
              _buildActionButton(
                icon: Icons.lock_open,
                title: 'Отключить PIN-код',
                isDestructive: true,
                onTap: () => _openPinSetup(PinSetupMode.disablePin),
              ),
            ],
            
            const SizedBox(height: 32),
            
            // Секция биометрии (только если PIN включен)
            if (isPinEnabled && _canUseBiometrics) ...[
              _buildSectionHeader('БИОМЕТРИЯ', Icons.fingerprint),
              const SizedBox(height: 12),
              _buildSwitchTile(
                icon: Icons.fingerprint,
                title: 'Разблокировка по отпечатку/лицу',
                subtitle: 'Быстрый вход без ввода PIN',
                value: config.isBiometricEnabled,
                onChanged: _toggleBiometrics,
              ),
              const SizedBox(height: 32),
            ],
            
            // Секция кода принуждения (только если PIN включен)
            if (isPinEnabled) ...[
              _buildSectionHeader('КОД ПРИНУЖДЕНИЯ', Icons.shield_outlined),
              const SizedBox(height: 12),
              
              _buildInfoCard(
                icon: Icons.warning_amber,
                text: 'Код принуждения — второй PIN, который показывает пустой профиль. '
                      'Используйте, если вынуждены разблокировать приложение под давлением.',
                color: Colors.amber,
                isMultiLine: true,
              ),
              const SizedBox(height: 12),
              
              if (!isDuressEnabled) ...[
                _buildActionButton(
                  icon: Icons.add,
                  title: 'Установить код принуждения',
                  subtitle: '${config.pinLength}-значный код для экстренных ситуаций',
                  onTap: () => _openPinSetup(PinSetupMode.setDuress),
                  accentColor: Colors.amber,
                ),
              ] else ...[
                _buildInfoCard(
                  icon: Icons.check_circle_outline,
                  text: 'Код принуждения установлен (${config.pinLength} цифр).',
                  color: const Color(0xFF6AD394),
                ),
                const SizedBox(height: 12),
                _buildActionButton(
                  icon: Icons.delete_outline,
                  title: 'Отключить код принуждения',
                  isDestructive: true,
                  onTap: () => _openPinSetup(PinSetupMode.disableDuress),
                ),
              ],
              
              const SizedBox(height: 32),
            ],

            // Секция кода удаления (только если PIN включен)
            if (isPinEnabled) ...[
              _buildSectionHeader('КОД УДАЛЕНИЯ', Icons.delete_forever),
              const SizedBox(height: 12),

              _buildInfoCard(
                icon: Icons.warning_amber,
                text: 'Код удаления — отдельный PIN, который запускает полное удаление данных. '
                      'После ввода потребуется подтверждение удержанием (защита от случайного запуска).',
                color: Colors.red,
                isMultiLine: true,
              ),
              const SizedBox(height: 12),

              if (!isWipeCodeEnabled) ...[
                _buildActionButton(
                  icon: Icons.add,
                  title: 'Установить код удаления',
                  subtitle: '${config.pinLength}-значный panic wipe код',
                  onTap: () => _openPinSetup(PinSetupMode.setWipeCode),
                  accentColor: Colors.red,
                ),
              ] else ...[
                _buildInfoCard(
                  icon: Icons.check_circle_outline,
                  text: 'Код удаления установлен (${config.pinLength} цифр).',
                  color: const Color(0xFF6AD394),
                ),
                const SizedBox(height: 12),
                _buildActionButton(
                  icon: Icons.delete_outline,
                  title: 'Отключить код удаления',
                  isDestructive: true,
                  onTap: () => _openPinSetup(PinSetupMode.disableWipeCode),
                ),
              ],

              const SizedBox(height: 32),
            ],
            
            // Секция автоматического удаления
            if (isPinEnabled) ...[
              _buildSectionHeader('ЗАЩИТА ОТ ПОДБОРА', Icons.delete_forever),
              const SizedBox(height: 12),
              
              _buildSwitchTile(
                icon: Icons.delete_sweep,
                title: 'Удалить данные после 10 попыток',
                subtitle: 'Автоматический wipe при неверном PIN',
                value: config.isAutoWipeEnabled,
                onChanged: (enabled) async {
                  await _auth.setAutoWipe(enabled);
                  _refresh();
                },
                isDestructive: true,
              ),
              
              if (config.isAutoWipeEnabled) ...[
                const SizedBox(height: 8),
                _buildInfoCard(
                  icon: Icons.warning,
                  text: 'После 10 неверных попыток все данные будут удалены безвозвратно!',
                  color: Colors.red,
                ),
              ],
              
              const SizedBox(height: 32),
            ],
            
            // Экстренное удаление (жест) — выключено по умолчанию
            _buildSectionHeader('ЭКСТРЕННОЕ УДАЛЕНИЕ', Icons.bolt),
            const SizedBox(height: 12),
            _buildSwitchTile(
              icon: Icons.touch_app,
              title: 'Включить жест panic wipe',
              subtitle: '3 быстрых ухода приложения в фон → wipe (по умолчанию выключено)',
              value: config.isPanicGestureEnabled,
              onChanged: (enabled) async {
                await _auth.setPanicGestureEnabled(enabled);
                _refresh();
              },
              isDestructive: true,
            ),
            const SizedBox(height: 10),
            _buildInfoCard(
              icon: Icons.info_outline,
              text: 'Важно: этот жест основан на быстрых уходах приложения в фон '
                    '(например, блокировка/разблокировка экрана или быстрое переключение приложений) '
                    'и может быть менее предсказуем, чем код удаления.',
              color: Colors.orange,
              isMultiLine: true,
            ),
            
            const SizedBox(height: 32),
            
            // Секция автоудаления сообщений
            _buildSectionHeader('АВТОУДАЛЕНИЕ СООБЩЕНИЙ', Icons.auto_delete),
            const SizedBox(height: 12),
            
            _buildInfoCard(
              icon: Icons.info_outline,
              text: 'Автоматическое удаление старых сообщений повышает приватность. '
                    'Сообщения старше выбранного периода будут удалены безвозвратно.',
              color: Colors.blue,
              isMultiLine: true,
            ),
            const SizedBox(height: 12),
            
            _MessageRetentionSelector(
              currentPolicy: _auth.messageRetention,
              onPolicyChanged: _onRetentionPolicyChanged,
            ),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade500, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String text,
    required Color color,
    bool isMultiLine = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: isMultiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withOpacity(0.9),
                fontSize: 13,
                height: isMultiLine ? 1.4 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Карточка статуса PIN с индикатором длины — вау-эффект ✨
  Widget _buildPinStatusCard(int pinLength) {
    const color = Color(0xFF6AD394);
    final isShortPin = pinLength == 4;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.verified_user,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'PIN-код установлен',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isShortPin 
                            ? Colors.amber.withOpacity(0.2)
                            : color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$pinLength цифр',
                        style: TextStyle(
                          color: isShortPin ? Colors.amber : color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isShortPin 
                      ? 'Быстрый ввод • ~10 000 комбинаций'
                      : 'Повышенная защита • ~1 000 000 комбинаций',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
    Color? accentColor,
  }) {
    final color = accentColor ?? (isDestructive ? Colors.red.shade400 : const Color(0xFFB0BEC5));
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDestructive 
                  ? Colors.red.withOpacity(0.2) 
                  : Colors.white.withOpacity(0.05),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
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
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
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
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? Colors.red.shade400 : const Color(0xFFB0BEC5);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDestructive 
              ? Colors.red.withOpacity(0.2) 
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
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
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: isDestructive ? Colors.red : const Color(0xFF6AD394),
            activeTrackColor: (isDestructive ? Colors.red : const Color(0xFF6AD394)).withOpacity(0.3),
          ),
        ],
      ),
    );
  }
}

/// Виджет выбора политики автоудаления сообщений
class _MessageRetentionSelector extends StatelessWidget {
  const _MessageRetentionSelector({
    required this.currentPolicy,
    required this.onPolicyChanged,
  });  final MessageRetentionPolicy currentPolicy;
  final ValueChanged<MessageRetentionPolicy> onPolicyChanged;  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < MessageRetentionPolicy.values.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Colors.white.withOpacity(0.05)),
            _buildOption(MessageRetentionPolicy.values[i]),
          ],
        ],
      ),
    );
  }  Widget _buildOption(MessageRetentionPolicy policy) {
    final isSelected = policy == currentPolicy;
    final icon = _getIconForPolicy(policy);
    final color = _getColorForPolicy(policy);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onPolicyChanged(policy),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(isSelected ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      policy.displayName,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      policy.subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6AD394).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Color(0xFF6AD394),
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }  IconData _getIconForPolicy(MessageRetentionPolicy policy) {
    switch (policy) {
      case MessageRetentionPolicy.all:
        return Icons.all_inclusive;
      case MessageRetentionPolicy.day:
        return Icons.today;
      case MessageRetentionPolicy.week:
        return Icons.date_range;
      case MessageRetentionPolicy.month:
        return Icons.calendar_month;
    }
  }  Color _getColorForPolicy(MessageRetentionPolicy policy) {
    switch (policy) {
      case MessageRetentionPolicy.all:
        return const Color(0xFFB0BEC5);
      case MessageRetentionPolicy.day:
        return Colors.red.shade400;
      case MessageRetentionPolicy.week:
        return Colors.orange.shade400;
      case MessageRetentionPolicy.month:
        return Colors.blue.shade400;
    }
  }
}
