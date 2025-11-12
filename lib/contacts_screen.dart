// lib/contacts_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orpheus_project/chat_screen.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late Future<List<Contact>> _contactsFuture;

  @override
  void initState() {
    super.initState();
    _refreshContacts();
  }

  void _refreshContacts() {
    setState(() {
      _contactsFuture = DatabaseService.instance.getContacts();
    });
  }

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final keyController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить контакт'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameController, decoration: const InputDecoration(hintText: 'Имя')),
          const SizedBox(height: 12),
          TextField(controller: keyController, decoration: const InputDecoration(hintText: 'Публичный ключ')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty && keyController.text.isNotEmpty) {
                final newContact = Contact(name: nameController.text, publicKey: keyController.text);
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Мой ID'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Поделитесь этим ключом, чтобы вас могли добавить в контакты:', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              myPublicKey,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ]),
        actions: [
          TextButton(
            child: const Text('Копировать'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: myPublicKey));
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ключ скопирован!')));
            },
          ),
          TextButton(child: const Text('Закрыть'), onPressed: () => Navigator.of(context).pop()),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
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
        title: const Text('Контакты'),
        actions: [
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
                  color = const Color(0xFF6AD394); // Зеленый
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
                  // По нажатию мы просто просим сервис подключиться.
                  // "Умный" метод connect сам решит, нужно ли что-то делать.
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
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final contacts = snapshot.data ?? [];
          if (contacts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Контактов нет.\nНажмите "+", чтобы добавить первый.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 5.0),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                  leading: CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    child: Text(
                      contact.name[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 24,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(contact.name, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: ${contact.publicKey.substring(0, 12)}...', style: TextStyle(color: Colors.grey[600])),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(contact: contact))),
                  onLongPress: () => _showDeleteContactDialog(contact),
                ),
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
  }
}