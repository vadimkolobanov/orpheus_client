import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/screens/help_screen.dart';

void main() {
  testWidgets('HelpScreen: рендерится и показывает ключевые секции',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));

    expect(find.text('Как пользоваться'), findsOneWidget);
    expect(find.text('Быстрый старт'), findsOneWidget);
    expect(find.text('PIN‑код'), findsOneWidget);
    expect(find.text('Auto‑wipe'), findsOneWidget);
  });
}
