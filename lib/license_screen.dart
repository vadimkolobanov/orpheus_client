import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';
import 'package:orpheus_project/widgets/app_card.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:orpheus_project/widgets/app_text_field.dart';

class LicenseScreen extends StatefulWidget {
  final VoidCallback onLicenseConfirmed;
  const LicenseScreen({
    super.key,
    required this.onLicenseConfirmed,
    Stream<String>? debugWsStreamOverride,
  }) : _debugWsStreamOverride = debugWsStreamOverride;

  final Stream<String>? _debugWsStreamOverride;

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final TextEditingController _promoController = TextEditingController();
  StreamSubscription? _wsSubscription;

  bool _isActivatingPromo = false;
  String? _promoError;

  @override
  void initState() {
    super.initState();

    final wsStream = widget._debugWsStreamOverride ?? websocketService.stream;
    _wsSubscription = wsStream.listen((message) {
      try {
        final data = json.decode(message);
        if (data['type'] == 'payment-confirmed' ||
            (data['type'] == 'license-status' && data['status'] == 'active')) {
          widget.onLicenseConfirmed();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _activatePromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) {
      setState(() => _promoError = "Введите код");
      return;
    }

    setState(() {
      _isActivatingPromo = true;
      _promoError = null;
    });

    try {
      final myPubkey = cryptoService.publicKeyBase64;
      if (myPubkey == null) throw Exception("Ключи не инициализированы");

      final url = Uri.parse(AppConfig.httpUrl('/api/activate-promo'));
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({"pubkey": myPubkey, "code": code}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['status'] == 'ok') {
        if (!mounted) return;
        await AppDialog.show(
          context: context,
          icon: Icons.check_circle,
          iconColor: AppColors.success,
          title: 'Готово',
          content: 'Лицензия успешно активирована.',
          primaryLabel: 'Ок',
        );
      } else {
        setState(() => _promoError = data['message'] ?? "Неверный код");
      }
    } catch (_) {
      setState(() => _promoError = "Ошибка соединения. Проверьте интернет.");
    } finally {
      if (mounted) setState(() => _isActivatingPromo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AppScaffold(
        safeArea: false,
        appBar: AppBar(
          title: const Text('Активация'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text('Введите код',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Код активации выдаётся при покупке лицензии.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              AppCard(
                radius: AppRadii.lg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Код активации',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 10),
                    AppTextField(
                      controller: _promoController,
                      hintText: 'XXXX-XXXX-XXXX',
                      prefixIcon: Icons.key,
                      textCapitalization: TextCapitalization.characters,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.visiblePassword,
                      onSubmitted: (_) => _activatePromo(),
                    ),
                    if (_promoError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _promoError!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.danger),
                      ),
                    ],
                    const SizedBox(height: 14),
                    AppButton(
                      label: _isActivatingPromo ? 'Проверка…' : 'Активировать',
                      icon: Icons.check_circle_outline,
                      onPressed: _isActivatingPromo ? null : _activatePromo,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                radius: AppRadii.lg,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        borderRadius: AppRadii.sm,
                      ),
                      child: const Icon(Icons.info_outline,
                          color: AppColors.success),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Формат',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: AppColors.success)),
                          const SizedBox(height: 4),
                          Text(
                            'Буквы, цифры, а также символы _ и -',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Если код не принимается — проверьте интернет и правильность ввода.',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
