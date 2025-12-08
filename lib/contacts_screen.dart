import 'dart:async';
import 'package:flutter/material.dart';
import 'package:orpheus_project/chat_screen.dart';
import 'package:orpheus_project/main.dart'; // messageUpdateController
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/qr_scan_screen.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/update_service.dart';

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
    _contactsFuture = _loadContactsWithTimeout();
    _updateSubscription = messageUpdateController.stream.listen((_) {
      _refreshContacts();
    });

    // Проверка обновлений (оставим здесь при старте)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        UpdateService.checkForUpdate(context);
      }
    });
  }

  Future<List<Contact>> _loadContactsWithTimeout() async {
    try {
      return await DatabaseService.instance.getContacts().timeout(
        const Duration(seconds: 10),
        onTimeout: () => <Contact>[],
      );
    } catch (e) {
      print("Ошибка загрузки контактов: $e");
      return <Contact>[];
    }
  }

  @override
  void dispose() {
    _updateSubscription?.cancel();
    super.dispose();
  }

  void _refreshContacts() {
    if (mounted) {
      setState(() {
        _contactsFuture = _loadContactsWithTimeout();
      });
    }
  }

  // Диалог добавления
  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final keyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ДОБАВИТЬ КОНТАКТ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Имя (псевдоним)',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              decoration: InputDecoration(
                labelText: 'Публичный ключ',
                prefixIcon: const Icon(Icons.vpn_key),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFB0BEC5)),
                  onPressed: () async {
                    final scannedKey = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const QrScanScreen()),
                    );
                    if (scannedKey != null) {
                      keyController.text = scannedKey;
                    }
                  },
                ),
              ),
              maxLines: 2,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ОТМЕНА'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty && keyController.text.isNotEmpty) {
                final newContact = Contact(
                  name: nameController.text,
                  publicKey: keyController.text.trim(),
                );
                await DatabaseService.instance.addContact(newContact);
                Navigator.pop(context);
                _refreshContacts();
              }
            },
            child: const Text('ДОБАВИТЬ'),
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
        content: const Text('История переписки будет удалена безвозвратно.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ОТМЕНА')),
          TextButton(
            child: const Text('УДАЛИТЬ', style: TextStyle(color: Colors.red)),
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
        title: const Text('КОНТАКТЫ'),
        centerTitle: false,
        automaticallyImplyLeading: false, // Убираем кнопку назад
      ),
      body: FutureBuilder<List<Contact>>(
        future: _contactsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Ошибка: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
          }

          final contacts = snapshot.data ?? [];

          if (contacts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_person, size: 60, color: Colors.grey[800]),
                    const SizedBox(height: 24),
                    const Text(
                      "НЕТ КОНТАКТОВ",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Нажмите +, чтобы добавить собеседника.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return FutureBuilder<int>(
                future: DatabaseService.instance.getUnreadCount(contact.publicKey),
                builder: (context, countSnapshot) {
                  final unreadCount = countSnapshot.data ?? 0;
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFFB0BEC5),
                        child: Text(
                          contact.name.isNotEmpty ? contact.name[0].toUpperCase() : "?",
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
                        ),
                      ),
                      title: Text(
                        contact.name,
                        style: TextStyle(
                            fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                            color: unreadCount > 0 ? Colors.white : Colors.white70
                        ),
                      ),
                      subtitle: Text(
                        '...${contact.publicKey.length > 8 ? contact.publicKey.substring(contact.publicKey.length - 8) : ""}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12, fontFamily: 'monospace'),
                      ),
                      trailing: unreadCount > 0
                          ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: Text(unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                          : const Icon(Icons.chevron_right, color: Colors.grey),
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
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.black, size: 32),
      ),
    );
  }
}