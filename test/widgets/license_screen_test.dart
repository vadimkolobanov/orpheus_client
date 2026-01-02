import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/license_screen.dart';

void main() {
  testWidgets('LicenseScreen: рендерится и показывает кнопку активации', (tester) async {
    final controller = StreamController<String>.broadcast();
    addTearDown(controller.close);

    var confirmed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LicenseScreen(
          onLicenseConfirmed: () => confirmed = true,
          debugWsStreamOverride: controller.stream,
        ),
      ),
    );

    expect(find.text('АКТИВАЦИЯ'), findsOneWidget);
    expect(find.text('АКТИВИРОВАТЬ'), findsOneWidget);
    expect(confirmed, isFalse);
  });
}






