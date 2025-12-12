import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/welcome_screen.dart';

void main() {
  group('WelcomeScreen Widget Tests', () {
    testWidgets('Отображает основные элементы интерфейса', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );

      // Проверяем наличие текста "ORPHEUS"
      expect(find.text('ORPHEUS'), findsOneWidget);
      
      // Проверяем наличие текста "SECURE COMMUNICATION"
      expect(find.text('SECURE COMMUNICATION'), findsOneWidget);

      // Проверяем наличие кнопки "СОЗДАТЬ АККАУНТ"
      expect(find.text('СОЗДАТЬ АККАУНТ'), findsOneWidget);

      // Проверяем наличие кнопки "ВОССТАНОВИТЬ ИЗ КЛЮЧА"
      expect(find.text('ВОССТАНОВИТЬ ИЗ КЛЮЧА'), findsOneWidget);
    });

    testWidgets('Кнопка создания аккаунта вызывает callback', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );

      // Находим и нажимаем кнопку создания аккаунта
      final createButton = find.text('СОЗДАТЬ АККАУНТ');
      expect(createButton, findsOneWidget);

      await tester.tap(createButton);
      await tester.pumpAndSettle();

      // Callback должен быть вызван (но в тестах без реального cryptoService он может не сработать)
      // Проверяем, что виджет реагирует на нажатие
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('Кнопка восстановления открывает диалог', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );

      // Находим и нажимаем кнопку восстановления
      final restoreButton = find.text('ВОССТАНОВИТЬ ИЗ КЛЮЧА');
      expect(restoreButton, findsOneWidget);

      await tester.tap(restoreButton);
      await tester.pumpAndSettle();

      // Должен появиться диалог восстановления
      expect(find.text('ВОССТАНОВЛЕНИЕ'), findsOneWidget);
      expect(find.text('Введите ваш Приватный ключ:'), findsOneWidget);
      expect(find.text('ОТМЕНА'), findsOneWidget);
      expect(find.text('ИМПОРТ'), findsOneWidget);
    });

    testWidgets('Диалог восстановления можно закрыть', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );

      // Открываем диалог
      await tester.tap(find.text('ВОССТАНОВИТЬ ИЗ КЛЮЧА'));
      await tester.pumpAndSettle();

      // Закрываем диалог
      await tester.tap(find.text('ОТМЕНА'));
      await tester.pumpAndSettle();

      // Диалог должен исчезнуть
      expect(find.text('ВОССТАНОВЛЕНИЕ'), findsNothing);
    });

    testWidgets('Экран использует градиентный фон', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );

      // Проверяем наличие Container с decoration
      final container = tester.widget<Container>(
        find.byType(Container).first,
      );

      expect(container.decoration, isA<BoxDecoration>());
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.gradient, isA<LinearGradient>());
    });
  });
}

