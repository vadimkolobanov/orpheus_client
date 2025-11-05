// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';

// Глобальные экземпляры сервисов для простоты в MVP.
// В более крупном приложении для этого лучше использовать Provider или GetIt.
final cryptoService = CryptoService();
final websocketService = WebSocketService();

void main() async {
  // Убедимся, что Flutter готов к работе, прежде чем выполнять асинхронный код.
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализируем крипто-сервис (загружаем или генерируем ключи).
  await cryptoService.init();

  // Сразу после получения ключа подключаемся к WebSocket серверу, идентифицируя себя.
  if (cryptoService.publicKeyBase64 != null) {
    websocketService.connect(cryptoService.publicKeyBase64!);
  }

  // Запускаем Flutter-приложение.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orpheus Client',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Контроллеры для полей ввода текста
  final _recipientKeyController = TextEditingController();
  final _messageController = TextEditingController();

  // Список для хранения сообщений чата
  final List<String> _messages = [];

  // Подписка на поток сообщений из WebSocket
  StreamSubscription? _socketSubscription;

  @override
  void initState() {
    super.initState();
    // Подписываемся на поток сообщений от WebSocket сервиса
    _socketSubscription = websocketService.stream.listen((payload) async {
      // ВАЖНО: В MVP мы предполагаем, что отправитель - тот,
      // чей ключ введен в поле "Ключ получателя", чтобы мы могли его использовать
      // для расшифровки. В реальном приложении сервер должен сообщать, от кого пришло сообщение.
      if (_recipientKeyController.text.isNotEmpty) {
        try {
          // Добавляем await, так как decrypt теперь асинхронный
          final decryptedMessage = await cryptoService.decrypt(
            _recipientKeyController.text,
            payload,
          );

          // Проверяем, что виджет все еще существует, прежде чем обновлять состояние
          if (mounted) {
            setState(() {
              _messages.add("Собеседник: $decryptedMessage");
            });
          }
        } catch (e) {
          print("Ошибка расшифровки: $e");
          if (mounted) {
            setState(() {
              _messages.add("--- Ошибка: не удалось расшифровать сообщение ---");
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _messages.add("--- Получено сообщение, но ключ получателя не указан для расшифровки ---");
          });
        }
      }
    });
  }

  @override
  void dispose() {
    // Чистим ресурсы при уничтожении виджета
    websocketService.disconnect();
    _socketSubscription?.cancel();
    _recipientKeyController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // Метод для отправки сообщения
  void _sendMessage() async {
    final recipientKey = _recipientKeyController.text;
    final message = _messageController.text;

    if (recipientKey.isNotEmpty && message.isNotEmpty) {
      try {
        // 1. Шифруем сообщение (добавляем await)
        final payload = await cryptoService.encrypt(recipientKey, message);

        // 2. Отправляем через WebSocket
        websocketService.sendMessage(recipientKey, payload);

        // 3. Обновляем UI, добавляя наше сообщение в список
        setState(() {
          _messages.add("Вы: $message");
        });

        // 4. Очищаем поле ввода
        _messageController.clear();
      } catch (e) {
        // Показываем ошибку, если, например, ключ получателя некорректный
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка шифрования: $e')),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите ключ получателя и сообщение')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myPublicKey = cryptoService.publicKeyBase64 ?? 'Генерация...';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orpheus Messenger'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- Блок с ID пользователя ---
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Ваш ID (публичный ключ для шифрования):", style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(myPublicKey, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: myPublicKey));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Ключ скопирован!')),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- Поля для ввода ---
            TextField(
              controller: _recipientKeyController,
              decoration: const InputDecoration(
                labelText: 'Публичный ключ получателя',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      labelText: 'Сообщение',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(), // Отправка по Enter
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],
            ),
            const Divider(height: 30),

            // --- "Экран" чата ---
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text(_messages[index]),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}