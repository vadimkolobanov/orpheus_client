import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/screens/debug_logs_screen.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';

void main() {
  setUp(() {
    DebugLogger.clear();
  });

  testWidgets('DebugLogsScreen: пустое состояние', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DebugLogsScreen()));
    expect(find.text('DEBUG LOGS'), findsOneWidget);
    expect(find.text('Нет логов'), findsOneWidget);
  });

  testWidgets('DebugLogsScreen: показывает логи и фильтры по тегам', (tester) async {
    DebugLogger.info('WS', 'hello');
    DebugLogger.error('DB', 'boom');

    await tester.pumpWidget(const MaterialApp(home: DebugLogsScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('ВСЕ ('), findsOneWidget);
    expect(find.textContaining('WS ('), findsOneWidget);
    expect(find.textContaining('DB ('), findsOneWidget);

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
  });
}




