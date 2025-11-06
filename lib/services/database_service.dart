// lib/services/database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/models/chat_message_model.dart'; // <-- Импортируем модель сообщения

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('orpheus.db'); // Переименуем для ясности
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    // При изменении схемы БД (добавлении таблиц) нужно увеличить версию
    return await openDatabase(path, version: 2, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  // Этот метод вызывается только при самом первом создании БД
  Future _createDB(Database db, int version) async {
    await _createContactsTable(db);
    await _createMessagesTable(db);
  }

  // Этот метод вызывается, если мы увеличили версию БД
  // Полезно для добавления новых таблиц в уже существующую БД
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createMessagesTable(db);
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

  // НОВЫЙ МЕТОД: Создание таблицы для сообщений
  Future<void> _createMessagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        contactPublicKey TEXT NOT NULL, 
        text TEXT NOT NULL,
        isSentByMe INTEGER NOT NULL, -- 1 для true, 0 для false
        timestamp INTEGER NOT NULL -- Время в миллисекундах
      )
    ''');
  }

  // --- Методы для работы с контактами ---
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

  // НОВЫЙ МЕТОД: Удаление контакта И ВСЕХ ЕГО СООБЩЕНИЙ
  Future<void> deleteContact(int id, String publicKey) async {
    final db = await instance.database;
    // Используем транзакцию, чтобы обе операции выполнились успешно, либо ни одна
    await db.transaction((txn) async {
      // Сначала удаляем все сообщения, связанные с этим контактом
      await txn.delete('messages', where: 'contactPublicKey = ?', whereArgs: [publicKey]);
      // Затем удаляем сам контакт
      await txn.delete('contacts', where: 'id = ?', whereArgs: [id]);
    });
  }

  // --- НОВЫЕ МЕТОДЫ для работы с сообщениями ---

  // Сохранить новое сообщение
  Future<void> addMessage(ChatMessage message, String contactKey) async {
    final db = await instance.database;
    final messageMap = {
      'contactPublicKey': contactKey,
      'text': message.text,
      'isSentByMe': message.isSentByMe ? 1 : 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await db.insert('messages', messageMap);
  }

  // Получить все сообщения для конкретного контакта
  Future<List<ChatMessage>> getMessagesForContact(String contactKey) async {
    final db = await instance.database;
    final maps = await db.query(
      'messages',
      where: 'contactPublicKey = ?',
      whereArgs: [contactKey],
      orderBy: 'timestamp ASC', // Сортируем по времени, чтобы чат был в правильном порядке
    );

    return List.generate(maps.length, (i) {
      return ChatMessage(
        text: maps[i]['text'] as String,
        isSentByMe: (maps[i]['isSentByMe'] as int) == 1,
      );
    });
  }

  // Удалить всю историю чата для контакта
  Future<void> clearChatHistory(String contactKey) async {
    final db = await instance.database;
    await db.delete('messages', where: 'contactPublicKey = ?', whereArgs: [contactKey]);
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}