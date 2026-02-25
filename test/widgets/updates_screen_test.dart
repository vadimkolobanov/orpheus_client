import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/updates_screen.dart';

void main() {
  testWidgets('UpdatesScreen: рендерится и показывает список (через debug future)', (tester) async {
    final future = Future<List<Map<String, dynamic>>>.value([
      {
        'version': '1.2.3',
        'date': '01.01.2026',
        'changes': ['A', 'B'],
      }
    ]);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
      home: UpdatesScreen(debugEntriesFutureOverride: future),
    ));
    // В UpdatesScreen есть бесконечные анимации (repeat), поэтому pumpAndSettle() не подходит.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('ИСТОРИЯ ОБНОВЛЕНИЙ'), findsOneWidget);
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('01.01.2026'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });
}


