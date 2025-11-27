import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/models/contact_model.dart';
// ВАЖНО: Нам придется немного подхачить DatabaseService для тестов,
// либо инициализировать фабрику FFI глобально.

void main() {
  // Инициализация FFI для SQLite в тестах
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    // Создаем чистую БД в памяти перед каждым тестом
    db = await openDatabase(inMemoryDatabasePath, version: 1,
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
        });
  });

  tearDown(() async {
    await db.close();
  });

  group('Database Logic Tests', () {
    test('CRUD Контактов', () async {
      final contact = Contact(name: "Elon", publicKey: "KEY123");

      // Insert
      await db.insert('contacts', contact.toMap());

      // Read
      final List<Map<String, dynamic>> maps = await db.query('contacts');
      expect(maps.length, 1);
      expect(maps.first['name'], "Elon");
      expect(maps.first['publicKey'], "KEY123");
    });

    test('Сохранение и чтение сообщений', () async {
      final msg = ChatMessage(
          text: "Hello Mars",
          isSentByMe: true,
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
          isRead: true
      );

      // Сохраняем (эмуляция метода addMessage)
      await db.insert('messages', msg.toMap("KEY123"));

      // Читаем
      final List<Map<String, dynamic>> maps = await db.query('messages');
      expect(maps.length, 1);

      final savedMsg = maps.first;
      expect(savedMsg['text'], "Hello Mars");
      expect(savedMsg['contactPublicKey'], "KEY123");
      expect(savedMsg['isSentByMe'], 1);
    });
  });
}