import 'package:flutter/material.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

/// Shimmer-эффект для skeleton loaders.
/// Полностью локальный — никаких данных не передаётся.
class AppShimmer extends StatefulWidget {
  const AppShimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? AppColors.surface2;
    final highlight = widget.highlightColor ?? AppColors.surface;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [base, highlight, base],
              stops: [
                0.0,
                0.5 + _animation.value * 0.15,
                1.0,
              ],
              transform: _SlidingGradientTransform(_animation.value),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.slidePercent);
  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}

/// Placeholder для карточки контакта.
class ContactRowSkeleton extends StatelessWidget {
  const ContactRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.md,
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            // Аватар
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
              ),
            ),
            const SizedBox(width: 12),
            // Текст
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 120,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: AppRadii.sm,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 80,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: AppRadii.sm,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Chevron placeholder
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: AppRadii.sm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Список skeleton-ов для загрузки контактов.
class ContactsListSkeleton extends StatelessWidget {
  const ContactsListSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 100,
      ),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => const ContactRowSkeleton(),
    );
  }
}

/// Placeholder для карточки на экране статуса.
class StatusCardSkeleton extends StatelessWidget {
  const StatusCardSkeleton({super.key, this.height = 80});

  final double height;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        height: height,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.md,
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 80,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: AppRadii.sm,
              ),
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: AppRadii.sm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
