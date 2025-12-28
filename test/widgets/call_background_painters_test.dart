import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/widgets/call/background_painters.dart';

void main() {
  group('Call background painters widget tests', () {
    testWidgets('Smoke: CallBackground/ParticlesPainter/WavePainter не падают при отрисовке', (tester) async {
      final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(seconds: 1));
      addTearDown(controller.dispose);
      controller.value = 0.5;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                CallBackground(controller: controller),
                CustomPaint(painter: ParticlesPainter(0.25), child: const SizedBox.expand()),
                CustomPaint(painter: WavePainter(0.75), child: const SizedBox.expand()),
              ],
            ),
          ),
        ),
      );

      // Просто подтверждаем, что дерево построилось и есть CustomPaint.
      expect(find.byType(CustomPaint).evaluate().length, greaterThanOrEqualTo(2));
      expect(find.byType(CallBackground), findsOneWidget);
    });
  });
}


