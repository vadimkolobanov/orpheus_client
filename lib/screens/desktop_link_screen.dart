import 'package:flutter/material.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/models/desktop_session_model.dart';
import 'package:orpheus_project/qr_scan_screen.dart';
import 'package:orpheus_project/services/desktop_link_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

class DesktopLinkScreen extends StatefulWidget {
  const DesktopLinkScreen({super.key});

  @override
  State<DesktopLinkScreen> createState() => _DesktopLinkScreenState();
}

class _DesktopLinkScreenState extends State<DesktopLinkScreen> {
  DesktopSession? _session;
  String? _error;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final session = await DesktopLinkService.instance.loadSession();
    if (!mounted) return;
    setState(() => _session = session);
  }

  Future<void> _startPairing() async {
    final qrValue = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScanScreen()),
    );

    if (qrValue == null || qrValue.isEmpty) return;

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      final result = await DesktopLinkService.instance.pairFromQr(qrValue);
      if (!mounted) return;
      setState(() => _session = result.session);
    } on DesktopLinkException catch (e) {
      if (!mounted) return;
      setState(() => _error = _mapError(context, e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = L10n.of(context).desktopLinkUnknownError);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _mapError(BuildContext context, DesktopLinkException e) {
    final l10n = L10n.of(context);
    switch (e.code) {
      case DesktopLinkErrorCode.expired:
        return l10n.desktopLinkExpired;
      case DesktopLinkErrorCode.invalidPayload:
        return l10n.desktopLinkInvalidQr;
      case DesktopLinkErrorCode.network:
        return l10n.desktopLinkNetworkError;
      case DesktopLinkErrorCode.unknown:
        return l10n.desktopLinkUnknownError;
    }
  }

  Future<void> _resetSession() async {
    await DesktopLinkService.instance.clearSession();
    if (!mounted) return;
    setState(() {
      _session = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(l10n.desktopLinkTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(
              session: _session,
              error: _error,
              isBusy: _isBusy,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isBusy ? null : _startPairing,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(l10n.desktopLinkScanQr),
            ),
            const SizedBox(height: 12),
            if (_session != null)
              OutlinedButton(
                onPressed: _isBusy ? null : _resetSession,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(l10n.desktopLinkReset),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.session,
    required this.error,
    required this.isBusy,
  });

  final DesktopSession? session;
  final String? error;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final hasSession = session != null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lg,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.desktopLinkStatusTitle,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (isBusy)
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(l10n.desktopLinkConnecting),
              ],
            )
          else if (error != null)
            Text(
              error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.danger),
            )
          else if (!hasSession)
            Text(l10n.desktopLinkNotPaired)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.desktopLinkPaired),
                const SizedBox(height: 12),
                Text(
                  l10n.desktopLinkOtpLabel,
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  session!.otp,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.desktopLinkOtpHint,
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
