import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/screens/debug_logs_screen.dart';
import 'package:orpheus_project/screens/desktop_link_screen.dart';
import 'package:orpheus_project/screens/help_screen.dart';
import 'package:orpheus_project/screens/security_settings_screen.dart';
import 'package:orpheus_project/screens/support_chat_screen.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/device_settings_service.dart';
import 'package:orpheus_project/services/locale_service.dart';
import 'package:orpheus_project/services/update_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/updates_screen.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/language_selector.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:orpheus_project/widgets/badge_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Счётчик тапов для скрытого меню отладки
  int _secretTapCount = 0;
  DateTime? _lastTapTime;

  // Состояние копирования
  bool _isCopied = false;

  // Статистика
  Map<String, int> _stats = const {'contacts': 0, 'messages': 0, 'sent': 0};

  // App info (реальная версия/билд из платформы)
  String? _appVersionLabel;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadAppInfo();
    LocaleService.instance.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  Future<void> _showNotificationSettingsDialog() async {
    final l10n = L10n.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        icon: Icons.notifications_none,
        title: l10n.notificationSettings,
        contentWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  DeviceSettingsService.showSetupDialog(context);
                },
                child: Text(l10n.systemNotificationSettings),
              ),
            ),
          ],
        ),
        primaryLabel: l10n.close,
      ),
    );
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStats() async {
    final stats = await DatabaseService.instance.getProfileStats();
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersionLabel = '${info.version}+${info.buildNumber}');
    } catch (e) {
      DebugLogger.warn('APPINFO', 'Не удалось получить версию приложения: $e');
    }
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
      DebugLogger.info('UI', 'Открыт экран логов через секретный тап');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const DebugLogsScreen()),
      );
    }
  }

  Future<void> _exportAccount() async {
    final l10n = L10n.of(context);
    final LocalAuthentication auth = LocalAuthentication();
    final bool canAuth =
        await auth.canCheckBiometrics || await auth.isDeviceSupported();

    if (!canAuth) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.biometryUnavailable)),
        );
      }
      return;
    }

    try {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: l10n.confirmIdentity,
        options:
            const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );

      if (!didAuthenticate) return;

      final privateKey = await cryptoService.getPrivateKeyBase64();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => _ExportKeyDialog(privateKey: privateKey),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.authError)),
        );
      }
    }
  }

  Future<void> _copyToClipboard(String text) async {
    final l10n = L10n.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _isCopied = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.idCopied)),
    );

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _isCopied = false);
  }

  Future<void> _showDeleteAccountDialog() async {
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteAccountDialog(),
    );

    if (confirmed != true) return;

    await authService.performWipe();

    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.accountDeleted)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final myKey = cryptoService.publicKeyBase64 ?? l10n.error;
    final versionLabel = _appVersionLabel ?? AppConfig.appVersion;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _handleSecretTap,
          child: Text(l10n.profile),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: UserBadge(pubkey: myKey, compact: true),
            ),
          ),
        ],
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            _QrCard(myKey: myKey, l10n: l10n),
            const SizedBox(height: 12),
            _IdCard(
                myKey: myKey,
                l10n: l10n,
                isCopied: _isCopied,
                onCopy: () => _copyToClipboard(myKey)),
            const SizedBox(height: 12),
            _PrimaryActions(
              myKey: myKey,
              l10n: l10n,
              onShare: () => Share.share(l10n.shareMessage(myKey)),
            ),
            const SizedBox(height: 14),
            _StatsCard(stats: _stats, l10n: l10n),
            const SizedBox(height: 14),
            _MenuCard(
              l10n: l10n,
              onDesktopLink: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DesktopLinkScreen()),
              ),
              onSecurity: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => SecuritySettingsScreen()),
              ).then((_) => setState(() {})),
              onSupport: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SupportChatScreen()),
              ),
              onHelp: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HelpScreen()),
              ),
              onUpdates: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const UpdatesScreen()),
              ),
              onExport: _exportAccount,
              onNotifications: _showNotificationSettingsDialog,
              onLanguageChanged: () => setState(() {}),
            ),
            const SizedBox(height: 14),
            _VersionCard(
              versionLabel: versionLabel,
              l10n: l10n,
              registrationDate: cryptoService.registrationDate,
              onCheckUpdates: () => UpdateService.checkForUpdate(context),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: _showDeleteAccountDialog,
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              label: Text(l10n.deleteAccount,
                  style: const TextStyle(color: AppColors.danger)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.myKey, required this.l10n});
  final String myKey;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lg,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.qrCode, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadii.md,
              ),
              child: QrImageView(
                data: myKey,
                version: QrVersions.auto,
                size: 170,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square, color: Color(0xFF111111)),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF111111),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdCard extends StatelessWidget {
  const _IdCard({
    required this.myKey,
    required this.l10n,
    required this.isCopied,
    required this.onCopy,
  });

  final String myKey;
  final L10n l10n;
  final bool isCopied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lg,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.yourId, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 10),
          InkWell(
            onTap: onCopy,
            borderRadius: AppRadii.md,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: AppRadii.md,
                border: Border.all(
                  color: isCopied
                      ? AppColors.success.withOpacity(0.45)
                      : AppColors.outline,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      myKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            color: AppColors.textPrimary,
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    isCopied ? Icons.check : Icons.copy,
                    size: 18,
                    color:
                        isCopied ? AppColors.success : AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({
    required this.myKey,
    required this.l10n,
    required this.onShare,
  });
  final String myKey;
  final L10n l10n;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.share, size: 18),
              label: Text(l10n.share),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats, required this.l10n});
  final Map<String, int> stats;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lg,
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _stat(context, Icons.people_outline, stats['contacts'] ?? 0,
              l10n.contactsCount(stats['contacts'] ?? 0)),
          _divider(),
          _stat(context, Icons.chat_outlined, stats['messages'] ?? 0,
              l10n.messagesCount(stats['messages'] ?? 0)),
          _divider(),
          _stat(context, Icons.send_outlined, stats['sent'] ?? 0, l10n.sentCount),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 30, color: AppColors.divider);

  Widget _stat(BuildContext context, IconData icon, int value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              '$value',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.l10n,
    required this.onDesktopLink,
    required this.onSecurity,
    required this.onSupport,
    required this.onHelp,
    required this.onUpdates,
    required this.onExport,
    required this.onNotifications,
    required this.onLanguageChanged,
  });

  final L10n l10n;
  final VoidCallback onDesktopLink;
  final VoidCallback onSecurity;
  final VoidCallback onSupport;
  final VoidCallback onHelp;
  final VoidCallback onUpdates;
  final VoidCallback onExport;
  final VoidCallback onNotifications;
  final VoidCallback onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lg,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          _tile(context, Icons.desktop_windows, l10n.desktopLinkTitle,
              l10n.desktopLinkDesc, onDesktopLink),
          _divider(),
          _tile(context, Icons.security, l10n.security, l10n.securityDesc,
              onSecurity),
          _divider(),
          // Выбор языка
          LanguageSelector(
            compact: false,
            onChanged: onLanguageChanged,
          ),
          _divider(),
          _tile(context, Icons.support_agent, l10n.support,
              l10n.supportDesc, onSupport),
          _divider(),
          _tile(context, Icons.help_outline, l10n.howToUse,
              l10n.howToUseDesc, onHelp),
          _divider(),
          _tile(context, Icons.history, l10n.updateHistory, null, onUpdates),
          _divider(),
          _tile(context, Icons.shield_outlined, l10n.exportAccount,
              l10n.exportAccountDesc, onExport,
              isDanger: true),
          _divider(),
          _tile(
            context,
            Icons.notifications_none,
            l10n.notificationSettings,
            l10n.notificationSettingsDesc,
            onNotifications,
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, thickness: 1, color: AppColors.divider);

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String? subtitle,
    VoidCallback onTap, {
    bool isDanger = false,
  }) {
    final accent = isDanger ? AppColors.danger : AppColors.accent;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: accent.withOpacity(0.10),
          borderRadius: AppRadii.sm,
        ),
        child: Icon(icon, color: accent, size: 20),
      ),
      title: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.versionLabel,
    required this.l10n,
    required this.registrationDate,
    required this.onCheckUpdates,
  });

  final String versionLabel;
  final L10n l10n;
  final DateTime? registrationDate;
  final VoidCallback onCheckUpdates;

  @override
  Widget build(BuildContext context) {
    final locale = LocaleService.instance.effectiveLocale.languageCode;
    final dateFormat = locale == 'ru' ? 'dd.MM.yyyy' : 'MMM d, yyyy';
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lg,
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Orpheus $versionLabel",
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (registrationDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.accountCreated(DateFormat(dateFormat).format(registrationDate!)),
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          TextButton(onPressed: onCheckUpdates, child: Text(l10n.checkUpdates)),
        ],
      ),
    );
  }
}

class _ExportKeyDialog extends StatelessWidget {
  const _ExportKeyDialog({required this.privateKey});
  final String privateKey;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.privateKey),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.privateKeyWarning,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: AppRadii.md,
              border: Border.all(color: AppColors.danger.withOpacity(0.25)),
            ),
            child: SelectableText(
              privateKey,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: AppColors.danger,
                  ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close)),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: privateKey));
            Navigator.pop(context);
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.keyCopied)));
          },
          child: Text(l10n.copy),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.deleteAccountTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.deleteAccountWarning),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            title: Text(l10n.deleteAccountConfirm),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel)),
        TextButton(
          onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: Text(l10n.delete),
        ),
      ],
    );
  }
}
