// lib/widgets/badge_widget.dart
// GLASS GEMSTONE BADGE SYSTEM
// Настоящее цветное стекло с полупрозрачностью

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:orpheus_project/services/badge_service.dart';

/// Цвета стеклянных камней
class GlassColors {
  // CORE - Красный кристалл (рубин)
  static const Color coreGlass = Color(0xFFFF1744);
  static const Color coreGlow = Color(0xFFFF5252);

  // OWNER - Тёмный рубин (гранат)
  static const Color ownerGlass = Color(0xFFD32F2F);
  static const Color ownerGlow = Color(0xFFEF5350);

  // PATRON - Фиолетовый аметист
  static const Color patronGlass = Color(0xFF9C27B0);
  static const Color patronGlow = Color(0xFFBA68C8);

  // BENEFACTOR - Золотой топаз / янтарь
  static const Color benefactorGlass = Color(0xFFFFB300);
  static const Color benefactorGlow = Color(0xFFFFD54F);

  // EARLY - Дымчатый кварц (серый)
  static const Color earlyGlass = Color(0xFF546E7A);
  static const Color earlyGlow = Color(0xFF78909C);
}

/// Стеклянный бейдж-камень
class LuxuryBadgeWidget extends StatefulWidget {
  final BadgeInfo badge;
  final bool compact;
  final bool enableAnimations;

  const LuxuryBadgeWidget({
    super.key,
    required this.badge,
    this.compact = false,
    this.enableAnimations = true,
  });

  @override
  State<LuxuryBadgeWidget> createState() => _LuxuryBadgeWidgetState();
}

class _LuxuryBadgeWidgetState extends State<LuxuryBadgeWidget>
    with TickerProviderStateMixin {
  late AnimationController _shimmerController;
  late AnimationController _glowController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2800),
      vsync: this,
    );

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    if (widget.enableAnimations) {
      _shimmerController.repeat();
      _glowController.repeat(reverse: true);
      if (widget.badge.typeString == 'core') {
        _pulseController.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _glowController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Color _getGlassColor() {
    switch (widget.badge.typeString) {
      case 'core':
        return GlassColors.coreGlass;
      case 'owner':
        return GlassColors.ownerGlass;
      case 'patron':
        return GlassColors.patronGlass;
      case 'benefactor':
        return GlassColors.benefactorGlass;
      case 'early':
        return GlassColors.earlyGlass;
      default:
        return GlassColors.earlyGlass;
    }
  }

  Color _getGlowColor() {
    switch (widget.badge.typeString) {
      case 'core':
        return GlassColors.coreGlow;
      case 'owner':
        return GlassColors.ownerGlow;
      case 'patron':
        return GlassColors.patronGlow;
      case 'benefactor':
        return GlassColors.benefactorGlow;
      case 'early':
        return GlassColors.earlyGlow;
      default:
        return GlassColors.earlyGlow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final glassColor = _getGlassColor();
    final glowColor = _getGlowColor();

    final hPad = widget.compact ? 10.0 : 14.0;
    final vPad = widget.compact ? 5.0 : 7.0;
    final fontSize = widget.compact ? 9.0 : 11.0;
    final radius = widget.compact ? 6.0 : 8.0;
    final blurAmount = widget.compact ? 8.0 : 12.0;

    // В компактном режиме (списки/аппбар) убираем blur + тяжелые слои.
    // “Стекло” остаётся только для крупного бейджа (вариант B: фирменный момент в 1-2 местах).
    if (widget.compact || !widget.enableAnimations) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: glassColor.withOpacity(0.14),
          border: Border.all(color: glassColor.withOpacity(0.30)),
          boxShadow: [
            BoxShadow(
              color: glowColor.withOpacity(0.12),
              blurRadius: 14,
              spreadRadius: -6,
            ),
          ],
        ),
        child: Text(
          widget.badge.label,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge(
          [_shimmerController, _glowController, _pulseController]),
      builder: (context, child) {
        final glowPulse = 0.5 + 0.5 * _glowController.value;
        final coreScale = widget.badge.typeString == 'core'
            ? 1.0 + 0.02 * _pulseController.value
            : 1.0;

        return Transform.scale(
          scale: coreScale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              // === ВНЕШНЕЕ СВЕЧЕНИЕ ===
              boxShadow: [
                // Дальнее цветное свечение
                BoxShadow(
                  color: glowColor.withOpacity(0.4 * glowPulse),
                  blurRadius: 20,
                  spreadRadius: -2,
                ),
                // Ближнее интенсивное
                BoxShadow(
                  color: glassColor.withOpacity(0.5 * glowPulse),
                  blurRadius: 10,
                  spreadRadius: -4,
                ),
                // Яркое ядро
                BoxShadow(
                  color: glowColor.withOpacity(0.3 * glowPulse),
                  blurRadius: 4,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                children: [
                  // === СЛОЙ 0: BLUR BACKGROUND ===
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: blurAmount,
                        sigmaY: blurAmount,
                      ),
                      child: Container(color: Colors.transparent),
                    ),
                  ),

                  // === СЛОЙ 1: ПОЛУПРОЗРАЧНОЕ СТЕКЛО ===
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                    decoration: BoxDecoration(
                      // Основа — очень прозрачный цвет
                      color: glassColor.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(radius),
                      // Градиентная "глубина"
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          glassColor.withOpacity(0.35),
                          glassColor.withOpacity(0.20),
                          glassColor.withOpacity(0.30),
                        ],
                      ),
                    ),
                    child: Text(
                      widget.badge.label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                        shadows: [
                          Shadow(
                            color: glassColor.withOpacity(0.8),
                            blurRadius: 8,
                          ),
                          Shadow(
                            color: Colors.white.withOpacity(0.5),
                            offset: const Offset(0, -0.5),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // === СЛОЙ 2: ВНУТРЕННЕЕ СВЕЧЕНИЕ ===
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        gradient: RadialGradient(
                          center: const Alignment(-0.5, -0.8),
                          radius: 1.8,
                          colors: [
                            glowColor.withOpacity(0.25 * glowPulse),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // === СЛОЙ 3: СТЕКЛЯННЫЙ БЛИК СВЕРХУ ===
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: vPad + fontSize * 0.6,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(radius)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0.55),
                            Colors.white.withOpacity(0.25),
                            Colors.white.withOpacity(0.08),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.25, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // === СЛОЙ 4: ГОРИЗОНТАЛЬНЫЙ БЛИК ===
                  Positioned(
                    top: 2,
                    left: hPad * 0.5,
                    right: hPad * 0.5,
                    child: Container(
                      height: 1.5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1),
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withOpacity(0.7),
                            Colors.white.withOpacity(0.9),
                            Colors.white.withOpacity(0.7),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // === СЛОЙ 5: ДИАГОНАЛЬНЫЕ ГРАНИ ===
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GlassFacetPainter(
                        color: Colors.white,
                        glowPulse: glowPulse,
                      ),
                    ),
                  ),

                  // === СЛОЙ 6: БЕГУЩИЙ SHIMMER ===
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: CustomPaint(
                        painter: _GlassShimmerPainter(
                          progress: _shimmerController.value,
                        ),
                      ),
                    ),
                  ),

                  // === СЛОЙ 7: СТЕКЛЯННАЯ РАМКА ===
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(
                          width: 1,
                          color: Colors.white.withOpacity(0.35),
                        ),
                      ),
                    ),
                  ),

                  // === СЛОЙ 8: ВНУТРЕННЯЯ ТОНКАЯ РАМКА ===
                  Positioned.fill(
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius - 1),
                        border: Border.all(
                          width: 0.5,
                          color: glassColor.withOpacity(0.4),
                        ),
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
}

/// Painter для стеклянных граней
class _GlassFacetPainter extends CustomPainter {
  final Color color;
  final double glowPulse;

  _GlassFacetPainter({required this.color, required this.glowPulse});

  @override
  void paint(Canvas canvas, Size size) {
    // Левая верхняя грань
    final path1 = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.4, 0)
      ..lineTo(0, size.height * 0.7)
      ..close();

    final paint1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color.withOpacity(0.12 * glowPulse),
          color.withOpacity(0.03),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width * 0.4, size.height * 0.7));

    canvas.drawPath(path1, paint1);

    // Правая нижняя грань
    final path2 = Path()
      ..moveTo(size.width, size.height)
      ..lineTo(size.width * 0.6, size.height)
      ..lineTo(size.width, size.height * 0.4)
      ..close();

    final paint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.topLeft,
        colors: [
          color.withOpacity(0.08 * glowPulse),
          color.withOpacity(0.02),
        ],
      ).createShader(Rect.fromLTWH(size.width * 0.6, size.height * 0.4,
          size.width * 0.4, size.height * 0.6));

    canvas.drawPath(path2, paint2);

    // Центральная вертикальная грань
    final path3 = Path()
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width * 0.55, 0)
      ..lineTo(size.width * 0.55, size.height)
      ..lineTo(size.width * 0.5, size.height)
      ..close();

    canvas.drawPath(
        path3, Paint()..color = color.withOpacity(0.04 * glowPulse));
  }

  @override
  bool shouldRepaint(_GlassFacetPainter oldDelegate) =>
      oldDelegate.glowPulse != glowPulse;
}

/// Painter для стеклянного shimmer
class _GlassShimmerPainter extends CustomPainter {
  final double progress;

  _GlassShimmerPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final shimmerWidth = size.width * 0.6;
    final totalTravel = size.width + shimmerWidth * 2;
    final startX = -shimmerWidth + totalTravel * progress;

    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(0.03),
          Colors.white.withOpacity(0.15),
          Colors.white.withOpacity(0.35),
          Colors.white.withOpacity(0.15),
          Colors.white.withOpacity(0.03),
          Colors.transparent,
        ],
        stops: const [0.0, 0.15, 0.35, 0.5, 0.65, 0.85, 1.0],
      ).createShader(Rect.fromLTWH(startX, 0, shimmerWidth, size.height));

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.35); // Наклон блика
    canvas.translate(-size.width / 2, -size.height / 2);

    canvas.drawRect(
      Rect.fromLTWH(
          startX - size.width, -size.height, shimmerWidth, size.height * 3),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassShimmerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ============================================================================
// СОВМЕСТИМЫЕ ВИДЖЕТЫ
// ============================================================================

class BadgeWidget extends StatelessWidget {
  final BadgeInfo badge;
  final bool compact;

  const BadgeWidget({
    super.key,
    required this.badge,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return LuxuryBadgeWidget(badge: badge, compact: compact);
  }
}

class UserBadge extends StatefulWidget {
  final String pubkey;
  final bool compact;

  const UserBadge({super.key, required this.pubkey, this.compact = false});

  @override
  State<UserBadge> createState() => _UserBadgeState();
}

class _UserBadgeState extends State<UserBadge> {
  BadgeInfo? _badge;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBadge();
  }

  @override
  void didUpdateWidget(UserBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pubkey != widget.pubkey) _loadBadge();
  }

  Future<void> _loadBadge() async {
    final cached = BadgeService.instance.getBadgeCached(widget.pubkey);
    if (cached != null) {
      if (mounted)
        setState(() {
          _badge = cached;
          _loading = false;
        });
      return;
    }
    setState(() => _loading = true);
    final badge = await BadgeService.instance.getBadge(widget.pubkey);
    if (mounted)
      setState(() {
        _badge = badge;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _badge == null) return const SizedBox.shrink();
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    return LuxuryBadgeWidget(
      badge: _badge!,
      compact: widget.compact,
      enableAnimations: !disableAnimations && !widget.compact,
    );
  }
}

class AnimatedUserBadge extends StatefulWidget {
  final String pubkey;
  final bool compact;

  const AnimatedUserBadge(
      {super.key, required this.pubkey, this.compact = false});

  @override
  State<AnimatedUserBadge> createState() => _AnimatedUserBadgeState();
}

class _AnimatedUserBadgeState extends State<AnimatedUserBadge>
    with SingleTickerProviderStateMixin {
  BadgeInfo? _badge;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _loadBadge();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AnimatedUserBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pubkey != widget.pubkey) {
      _controller.reset();
      _loadBadge();
    }
  }

  Future<void> _loadBadge() async {
    final badge = await BadgeService.instance.getBadge(widget.pubkey);
    if (mounted && badge != null) {
      setState(() => _badge = badge);
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_badge == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final curve =
            Curves.elasticOut.transform(_controller.value.clamp(0.0, 1.0));
        final fade =
            Curves.easeOut.transform((_controller.value * 2).clamp(0.0, 1.0));

        return Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: 0.3 + 0.7 * curve,
            child: LuxuryBadgeWidget(badge: _badge!, compact: widget.compact),
          ),
        );
      },
    );
  }
}

class BadgeShowcase extends StatelessWidget {
  const BadgeShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        // Тёмный фон чтобы стекло было видно
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f0f23)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'GLASS COLLECTION',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 5,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              BadgeInfo.badges[BadgeType.core]!,
              BadgeInfo.badges[BadgeType.owner]!,
              BadgeInfo.badges[BadgeType.patron]!,
              BadgeInfo.badges[BadgeType.benefactor]!,
              BadgeInfo.badges[BadgeType.early]!,
            ].map((b) => LuxuryBadgeWidget(badge: b)).toList(),
          ),
        ],
      ),
    );
  }
}
