// lib/services/database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/models/chat_message_model.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('orpheus.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // Увеличиваем версию до 3
    return await openDatabase(path, version: 3, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future _createDB(Database db, int version) async {
    await _createContactsTable(db);
    await _createMessagesTable(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createMessagesTable(db);
    }
    if (oldVersion < 3) {
      // Миграция для версии 3: Добавляем колонки status и isRead
      await db.execute("ALTER TABLE messages ADD COLUMN status INTEGER DEFAULT 1"); // 1 = sent
      await db.execute("ALTER TABLE messages ADD COLUMN isRead INTEGER DEFAULT 1"); // 1 = true
    }
  }

  Future<void> _createContactsTable(Database db) async {
    await db.execute('''
      CREATE TABLE contacts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        publicKey TEXT NOT NULL UNIQUE
      )
    ''');
  }

  Future<void> _createMessagesTable(Database db) async {
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
  }

  // --- Контакты ---
  Future<void> addContact(Contact contact) async {
    final db = await instance.database;
    await db.insert('contacts', contact.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Contact>> getContacts() async {
    final db = await instance.database;
    final maps = await db.query('contacts', orderBy: 'name');
    return List.generate(maps.length, (i) {
      return Contact(
        id: maps[i]['id'] as int,
        name: maps[i]['name'] as String,
        publicKey: maps[i]['publicKey'] as String,
      );
    });
  }

  Future<void> deleteContact(int id, String publicKey) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'contactPublicKey = ?', whereArgs: [publicKey]);
      await txn.delete('contacts', where: 'id = ?', whereArgs: [id]);
    });
  }

  // --- Сообщения ---

  // Сохранить сообщение
  Future<void> addMessage(ChatMessage message, String contactKey) async {
    final db = await instance.database;
    await db.insert('messages', message.toMap(contactKey));
  }

  // Получить сообщения (с маппингом новых полей)
  Future<List<ChatMessage>> getMessagesForContact(String contactKey) async {
    final db = await instance.database;
    final maps = await db.query(
      'messages',
      where: 'contactPublicKey = ?',
      whereArgs: [contactKey],
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) {
      return ChatMessage(
        id: maps[i]['id'] as int,
        text: maps[i]['text'] as String,
        isSentByMe: (maps[i]['isSentByMe'] as int) == 1,
        timestamp: DateTime.fromMillisecondsSinceEpoch(maps[i]['timestamp'] as int),
        status: MessageStatus.values[(maps[i]['status'] as int?) ?? 1],
        isRead: ((maps[i]['isRead'] as int?) ?? 1) == 1,
      );
    });
  }

  // Пометить все сообщения от контакта как прочитанные
  Future<void> markMessagesAsRead(String contactKey) async {
    final db = await instance.database;
    await db.update(
      'messages',
      {'isRead': 1},
      where: 'contactPublicKey = ? AND isRead = 0',
      whereArgs: [contactKey],
    );
  }

  // Получить количество непрочитанных для контакта
  Future<int> getUnreadCount(String contactKey) async {
    final db = await instance.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) FROM messages WHERE contactPublicKey = ? AND isRead = 0',
        [contactKey]
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> clearChatHistory(String contactKey) async {
    final db = await instance.database;
    await db.delete('messages', where: 'contactPublicKey = ?', whereArgs: [contactKey]);
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}