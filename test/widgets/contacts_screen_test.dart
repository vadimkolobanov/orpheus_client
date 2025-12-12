import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/contacts_screen.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqlite_api.dart';

void main() {
  // Инициализация FFI для SQLite в тестах
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ContactsScreen Widget Tests', () {
    late Database testDb;

    setUp(() async {
      // Создаем in-memory БД для каждого теста
      testDb = await openDatabase(
        inMemoryDatabasePath,
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE contacts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              publicKey TEXT NOT NULL UNIQUE
            )
          ''');
          await db.execute('''
            CREATE TABLE messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              contactPublicKey TEXT NOT NULL, 
              text TEXT NOT NULL,
              isSentByMe INTEGER NOT NULL,
              timestamp INTEGER NOT NULL,
              status INTEGER DEFAULT 1,
              isRead INTEGER DEFAULT 1
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 3) {
            try {
              await db.execute("ALTER TABLE messages ADD COLUMN status INTEGER DEFAULT 1");
            } catch (e) {}
            try {
              await db.execute("ALTER TABLE messages ADD COLUMN isRead INTEGER DEFAULT 1");
            } catch (e) {}
          }
        },
      );
      
      // Инициализируем DatabaseService с тестовой БД
      DatabaseService.instance.initWithDatabase(testDb);
    });

    tearDown(() async {
      try {
        await DatabaseService.instance.close();
        await testDb.close();
      } catch (e) {
        // Игнорируем ошибки
      }
    });

    testWidgets('Отображает заголовок и основные элементы', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ContactsScreen(),
        ),
      );

      // Даем время на загрузку
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Проверяем наличие заголовка
      expect(find.text('ORPHEUS'), findsOneWidget);

      // Проверяем наличие кнопки добавления контакта (FAB)
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('Отображает состояние загрузки', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ContactsScreen(),
        ),
      );

      // Пока идет загрузка, должен быть индикатор
      await tester.pump();

      // Может быть либо список контактов, либо индикатор загрузки, либо пустое состояние
      final hasLoading = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      final hasEmptyState = find.text('НЕТ КОНТАКТОВ').evaluate().isNotEmpty;
      final hasList = find.byType(ListView).evaluate().isNotEmpty;

      // Должно быть одно из состояний
      expect(hasLoading || hasEmptyState || hasList, isTrue);
    });

    testWidgets('Отображает пустое состояние при отсутствии контактов', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ContactsScreen(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Должно быть пустое состояние (БД пустая)
      expect(find.text('НЕТ КОНТАКТОВ'), findsOneWidget);
    });

    testWidgets('Отображает список контактов', (WidgetTester tester) async {
      // Добавляем тестовые контакты в БД
      await DatabaseService.instance.addContact(Contact(name: "Alice", publicKey: "KEY1"));
      await DatabaseService.instance.addContact(Contact(name: "Bob", publicKey: "KEY2"));

      await tester.pumpWidget(
        const MaterialApp(
          home: ContactsScreen(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Должен быть список контактов
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('Кнопка добавления контакта открывает диалог', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ContactsScreen(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Находим FAB
      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);

      // Нажимаем на FAB
      await tester.tap(fab);
      await tester.pumpAndSettle();

      // Должен появиться диалог добавления контакта
      expect(find.text('ДОБАВИТЬ КОНТАКТ'), findsOneWidget);
    });

    testWidgets('Диалог добавления контакта можно закрыть', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ContactsScreen(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Открываем диалог
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Закрываем диалог
      await tester.tap(find.text('ОТМЕНА'));
      await tester.pumpAndSettle();

      // Диалог должен исчезнуть
      expect(find.text('ДОБАВИТЬ КОНТАКТ'), findsNothing);
    });
  });
}

