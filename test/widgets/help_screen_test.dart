import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/screens/help_screen.dart';

void main() {
  testWidgets('HelpScreen: рендерится и показывает ключевые секции', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));

    expect(find.text('КАК ПОЛЬЗОВАТЬСЯ'), findsOneWidget);
    expect(find.textContaining('БЫСТРЫЙ СТАРТ'), findsOneWidget);
    expect(find.textContaining('PIN-КОД'), findsOneWidget);
    expect(find.textContaining('AUTO-WIPE'), findsOneWidget);
  });
}




