// lib/contacts_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orpheus_project/chat_screen.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/notification_service.dart'; // Импорт для токена
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/updates_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late Future<List<Contact>> _contactsFuture;
  StreamSubscription? _updateSubscription;

  @override
  void initState() {
    super.initState();
    _refreshContacts();

    // Подписываемся на поток обновлений сообщений.
    // Когда приходит новое сообщение (в main.dart), вызывается _refreshContacts,
    // что заставляет перерисоваться список и обновить красные кружки.
    _updateSubscription = messageUpdateController.stream.listen((_) {
      _refreshContacts();
    });
  }

  @override
  void dispose() {
    _updateSubscription?.cancel();
    super.dispose();
  }

  void _refreshContacts() {
    if (mounted) {
      setState(() {
        _contactsFuture = DatabaseService.instance.getContacts();
      });
    }
  }

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final keyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить контакт'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(hintText: 'Имя'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(hintText: 'Публичный ключ'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty && keyController.text.isNotEmpty) {
                final newContact = Contact(
                  name: nameController.text,
                  publicKey: keyController.text,
                );
                await DatabaseService.instance.addContact(newContact);
                Navigator.pop(context);
                _refreshContacts();
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showMyIdDialog() {
    final myPublicKey = cryptoService.publicKeyBase64 ?? 'Ключ еще не сгенерирован';
    // Берем токен из нашего нового сервиса
    final myFcmToken = NotificationService().fcmToken ?? 'Токен еще не получен';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Мои Данные'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Публичный ключ (Ваш ID):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  myPublicKey,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'FCM Токен (для пушей):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  myFcmToken,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.blueGrey),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Коп. Ключ'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: myPublicKey));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ключ скопирован!')),
              );
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            child: const Text('Коп. Токен'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: myFcmToken));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Токен скопирован!')),
              );
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            child: const Text('Закрыть'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _showDeleteContactDialog(Contact contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить ${contact.name}?'),
        content: const Text('Вся история переписки с этим контактом будет также удалена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              if (!mounted) return;
              await DatabaseService.instance.deleteContact(contact.id!, contact.publicKey);
              Navigator.pop(context);
              _refreshContacts();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orpheus'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'О приложении',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const UpdatesScreen()));
            },
          ),
          StreamBuilder<ConnectionStatus>(
            stream: websocketService.status,
            initialData: ConnectionStatus.Disconnected,
            builder: (context, snapshot) {
              IconData icon;
              Color color;
              String tooltip;
              switch (snapshot.data!) {
                case ConnectionStatus.Connected:
                  icon = Icons.cloud_done_outlined;
                  color = const Color(0xFF6AD394);
                  tooltip = 'Сервер: подключено';
                  break;
                case ConnectionStatus.Connecting:
                  icon = Icons.cloud_upload_outlined;
                  color = Colors.orangeAccent;
                  tooltip = 'Сервер: подключение...';
                  break;
                case ConnectionStatus.Disconnected:
                  icon = Icons.cloud_off_outlined;
                  color = Colors.redAccent;
                  tooltip = 'Сервер: отключено. Нажмите для переподключения.';
                  break;
              }

              return IconButton(
                icon: Icon(icon, color: color, size: 28),
                tooltip: tooltip,
                onPressed: () {
                  if (cryptoService.publicKeyBase64 != null) {
                    websocketService.connect(cryptoService.publicKeyBase64!);
                  }
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined, size: 26),
            tooltip: 'Показать мой ID',
            onPressed: _showMyIdDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<Contact>>(
        future: _contactsFuture,
        builder: (context, snapshot) {
          // 1. ОБРАБОТКА ОЖИДАНИЯ
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // 2. ОБРАБОТКА ОШИБКИ (ВАЖНО!)
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Ошибка базы данных:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _refreshContacts,
                      child: const Text("Повторить"),
                    )
                  ],
                ),
              ),
            );
          }

          final contacts = snapshot.data ?? [];

          // 3. ПУСТОЙ СПИСОК
          if (contacts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline, size: 60, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      'Контактов нет.\nНажмите "+", чтобы добавить первый.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            );
          }

          // 4. СПИСОК КОНТАКТОВ
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];

              return FutureBuilder<int>(
                future: DatabaseService.instance.getUnreadCount(contact.publicKey),
                builder: (context, countSnapshot) {
                  final unreadCount = countSnapshot.data ?? 0;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 5.0),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                      leading: CircleAvatar(
                        radius: 28,
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        child: Text(
                          contact.name.isNotEmpty ? contact.name[0].toUpperCase() : "?",
                          style: TextStyle(
                            fontSize: 24,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                          contact.name,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: unreadCount > 0 ? FontWeight.w900 : FontWeight.bold
                          )
                      ),
                      subtitle: Text(
                          'ID: ${contact.publicKey.length > 12 ? contact.publicKey.substring(0, 12) : contact.publicKey}...',
                          style: TextStyle(color: Colors.grey[600])
                      ),
                      trailing: unreadCount > 0
                          ? Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          unreadCount.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      )
                          : null,
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(contact: contact)));
                        _refreshContacts();
                      },
                      onLongPress: () => _showDeleteContactDialog(contact),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        child: const Icon(Icons.add),
      ),
    );
  }}