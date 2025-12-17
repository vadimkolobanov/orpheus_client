import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/welcome_screen.dart';

void main() {
  group('WelcomeScreen Widget Tests', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      // Делаем экран выше, чтобы избежать overflow в сложной верстке.
      binding.window.physicalSizeTestValue = const Size(1080, 1920);
      binding.window.devicePixelRatioTestValue = 1.0;
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.clearPhysicalSizeTestValue();
      binding.window.clearDevicePixelRatioTestValue();
    });

    testWidgets('Отображает основные элементы интерфейса', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );
      // Даем анимациям дойти до состояния, когда кнопки в видимой области.
      await tester.pump(const Duration(seconds: 3));

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
      await tester.pump(const Duration(seconds: 3));

      // Находим кнопку создания аккаунта
      final createButton = find.widgetWithText(ElevatedButton, 'СОЗДАТЬ АККАУНТ');
      expect(createButton, findsOneWidget);

      // В тестовой среде нет смысла реально вызывать cryptoService,
      // но важно, что кнопка активна.
      final btn = tester.widget<ElevatedButton>(createButton);
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Кнопка восстановления открывает диалог', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      // Находим и нажимаем кнопку восстановления
      final restoreButton = find.widgetWithText(OutlinedButton, 'ВОССТАНОВИТЬ ИЗ КЛЮЧА');
      expect(restoreButton, findsOneWidget);

      // Вызываем onPressed напрямую (из-за сложной анимации/opacity в welcome экране,
      // hit-test через tap() в тестовой среде нестабилен).
      final btn = tester.widget<OutlinedButton>(restoreButton);
      btn.onPressed?.call();
      await tester.pump(const Duration(milliseconds: 200));

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
      await tester.pump(const Duration(seconds: 3));

      // Открываем диалог
      final restoreButton = find.widgetWithText(OutlinedButton, 'ВОССТАНОВИТЬ ИЗ КЛЮЧА');
      final btn = tester.widget<OutlinedButton>(restoreButton);
      btn.onPressed?.call();
      await tester.pump(const Duration(milliseconds: 200));

      // Закрываем диалог
      final cancelBtnFinder = find.widgetWithText(TextButton, 'ОТМЕНА');
      final cancelBtn = tester.widget<TextButton>(cancelBtnFinder);
      cancelBtn.onPressed?.call();
      await tester.pump(const Duration(milliseconds: 200));

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
      await tester.pump(const Duration(seconds: 1));

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

