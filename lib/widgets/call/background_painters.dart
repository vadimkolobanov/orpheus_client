import 'package:flutter/material.dart';

// Рисует частицы на фоне
class ParticlesPainter extends CustomPainter {
  final double animationValue;
  ParticlesPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 30; i++) {
      final x = (i * 137.5) % size.width;
      final y = (i * 197.3 + animationValue * 200) % size.height;
      final radius = 1.5 + (i % 3) * 0.5;

      canvas.drawCircle(
        Offset(x, y),
        radius,
        paint..color = const Color(0xFF6AD394).withOpacity(0.2 + (i % 3) * 0.1),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Рисует волны вокруг аватара
class WavePainter extends CustomPainter {
  final double animationValue;
  WavePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2 - 100;
    final paint = Paint()
      ..color = const Color(0xFF6AD394)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < 3; i++) {
      final radius = 80 + (animationValue * 100) + (i * 30);
      final opacity = (1.0 - animationValue - i * 0.2).clamp(0.0, 0.5);

      canvas.drawCircle(
        Offset(centerX, centerY),
        radius,
        paint..color = const Color(0xFF6AD394).withOpacity(opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Градиентный фон
class CallBackground extends StatelessWidget {
  final AnimationController controller;
  const CallBackground({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(
                  const Color(0xFF1A1A1A),
                  const Color(0xFF0A1A2A),
                  (0.5 + 0.5 * (0.5 + 0.5 * controller.value)).clamp(0.0, 1.0),
                )!,
                const Color(0xFF000000),
              ],
            ),
          ),
        );
      },
    );
  }
}