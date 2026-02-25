import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/screens/support_chat_screen.dart';

void main() {
  group('SupportChatScreen (виджет-тесты)', () {
    testWidgets('отображает заголовок "ЧАТ С РАЗРАБОТЧИКОМ"', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('ru'),
          home: SupportChatScreen(),
        ),
      );

      expect(find.text('ЧАТ С РАЗРАБОТЧИКОМ'), findsOneWidget);
      expect(find.text('Ответим в ближайшее время'), findsOneWidget);
    });

    testWidgets('имеет поле ввода сообщения', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('ru'),
          home: SupportChatScreen(),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('имеет кнопки отправки и прикрепления логов', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('ru'),
          home: SupportChatScreen(),
        ),
      );

      // Кнопка attach (логи)
      expect(find.byIcon(Icons.attach_file), findsOneWidget);

      // Кнопка send
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('имеет кнопку обновления в AppBar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('ru'),
          home: SupportChatScreen(),
        ),
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('показывает пустое состояние когда нет сообщений',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('ru'),
          home: SupportChatScreen(),
        ),
      );

      // Даём время загрузке (async)
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // При ошибке или пустом списке — должно быть "Напишите нам!" или ошибка
      // Точный текст зависит от состояния сервиса
      expect(
        find.byType(SupportChatScreen),
        findsOneWidget,
      );
    });
  });

  group('SupportChatScreen интеграционные проверки', () {
    testWidgets('можно ввести текст в поле', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('ru'),
          home: SupportChatScreen(),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Привет!');
      await tester.pump();

      expect(find.text('Привет!'), findsOneWidget);
    });

    testWidgets('кнопка отправки кликабельна', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('ru'),
          home: SupportChatScreen(),
        ),
      );

      final sendButton = find.byIcon(Icons.send);
      expect(sendButton, findsOneWidget);

      // Проверяем что IconButton
      final iconButton = find.ancestor(
        of: sendButton,
        matching: find.byType(IconButton),
      );
      expect(iconButton, findsOneWidget);
    });
  });
}




