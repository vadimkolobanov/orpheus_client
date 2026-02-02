import 'package:flutter/material.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_card.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    
    return AppScaffold(
      safeArea: false,
      appBar: AppBar(title: Text(l10n.howToUse)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Section(
              title: l10n.helpQuickStart,
              bullets: [
                l10n.helpQuickStartBullet1,
                l10n.helpQuickStartBullet2,
                l10n.helpQuickStartBullet3,
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: l10n.helpExportTitle,
              bullets: [
                l10n.helpExportBullet1,
                l10n.helpExportBullet2,
                l10n.helpExportBullet3,
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: l10n.helpPinTitle,
              bullets: [
                l10n.helpPinBullet1,
                l10n.helpPinBullet2,
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: l10n.helpDuressTitle,
              bullets: [
                l10n.helpDuressBullet1,
                l10n.helpDuressBullet2,
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: l10n.helpWipeCodeTitle,
              bullets: [
                l10n.helpWipeCodeBullet1,
                l10n.helpWipeCodeBullet2,
                l10n.helpWipeCodeBullet3,
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: l10n.helpAutoWipeTitle,
              bullets: [
                l10n.helpAutoWipeBullet1,
                l10n.helpAutoWipeBullet2,
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: l10n.helpPanicGestureTitle,
              bullets: [
                l10n.helpPanicGestureBullet1,
                l10n.helpPanicGestureBullet2,
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: l10n.helpRegionsTitle,
              bullets: [
                l10n.helpRegionsBullet1,
                l10n.helpRegionsBullet2,
                l10n.helpRegionsBullet3,
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      radius: AppRadii.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...bullets.map((b) => _Bullet(text: b)),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 6, color: AppColors.textTertiary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: t.bodyMedium?.copyWith(height: 1.35)),
          ),
        ],
      ),
    );
  }
}
