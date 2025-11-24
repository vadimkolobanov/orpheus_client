// lib/contacts_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:orpheus_project/chat_screen.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/updates_screen.dart';
import 'package:share_plus/share_plus.dart';

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

  // --- ЭКСПОРТ КЛЮЧА (БИОМЕТРИЯ) ---
  Future<void> _exportAccount() async {
    final LocalAuthentication auth = LocalAuthentication();
    bool canAuth = await auth.canCheckBiometrics || await auth.isDeviceSupported();

    if (!canAuth) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Защита не настроена")));
      return;
    }

    try {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Экспорт аккаунта',
        options: const AuthenticationOptions(stickyAuth: true),
      );

      if (didAuthenticate) {
        final privateKey = await cryptoService.getPrivateKeyBase64();
        if (!mounted) return;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("ПРИВАТНЫЙ КЛЮЧ", style: TextStyle(color: Colors.red)),
            content: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.red.withOpacity(0.1),
              child: SelectableText(
                privateKey,
                style: const TextStyle(fontFamily: 'monospace', color: Colors.redAccent),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("ЗАКРЫТЬ")),
            ],
          ),
        );
      }
    } catch (e) {
      print("Auth error: $e");
    }
  }

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
              decoration: const InputDecoration(
                labelText: 'Имя (псевдоним)',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'Публичный ключ собеседника',
                prefixIcon: Icon(Icons.vpn_key),
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

  // --- ВИДЖЕТ: КАРТОЧКА "МОЙ ID" ---
  Widget _buildMyIdentityCard() {
    final myKey = cryptoService.publicKeyBase64 ?? "Ошибка";

    return Card(
      margin: const EdgeInsets.all(12),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "МОЙ ПУБЛИЧНЫЙ ID",
                  style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold
                  ),
                ),
                GestureDetector(
                  onTap: _exportAccount,
                  child: const Icon(Icons.settings, color: Colors.grey, size: 20),
                )
              ],
            ),
            const SizedBox(height: 12),

            // Сам ключ
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10)
              ),
              child: SelectableText(
                myKey,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFFECEFF1),
                    fontSize: 13
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Кнопки действий
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text("КОПИРОВАТЬ"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF37474F),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: myKey));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("ID скопирован"))
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text("ОТПРАВИТЬ"),
                    onPressed: () {
                      // Поделиться через системный диалог
                      // Если пакет share_plus не установлен, просто копируем
                      // Но лучше добавить: flutter pub add share_plus
                      try {
                        Share.share("Мой Orpheus ID:\n$myKey");
                        Clipboard.setData(ClipboardData(text: myKey));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("ID скопирован. Отправьте его другу!"))
                        );
                      } catch (e) {
                        Clipboard.setData(ClipboardData(text: myKey));
                      }
                    },
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ORPHEUS'),
        leading: IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UpdatesScreen())),
        ),
        actions: [
          // Индикатор сети
          StreamBuilder<ConnectionStatus>(
            stream: websocketService.status,
            initialData: ConnectionStatus.Disconnected,
            builder: (context, snapshot) {
              final color = snapshot.data == ConnectionStatus.Connected
                  ? const Color(0xFF6AD394)
                  : Colors.redAccent;
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Icon(Icons.circle, color: color, size: 12),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Визитка ВСЕГДА сверху
          _buildMyIdentityCard(),

          // 2. Список контактов или Инструкция
          Expanded(
            child: FutureBuilder<List<Contact>>(
              future: _contactsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final contacts = snapshot.data ?? [];

                // --- ЕСЛИ НЕТ КОНТАКТОВ ---
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
                            "КАК НАЧАТЬ ОБЩЕНИЕ?",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          _buildInstructionStep("1", "Скопируйте ваш ID сверху"),
                          _buildInstructionStep("2", "Отправьте его другу (Telegram, SMS)"),
                          _buildInstructionStep("3", "Получите ID друга"),
                          _buildInstructionStep("4", "Нажмите + и добавьте его"),
                        ],
                      ),
                    ),
                  );
                }

                // --- ЕСТЬ КОНТАКТЫ ---
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
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
                                contact.name[0].toUpperCase(),
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
                              'ID: ...${contact.publicKey.substring(contact.publicKey.length - 8)}',
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.person_add_alt_1, color: Colors.black),
      ),
    );
  }

  Widget _buildInstructionStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
              radius: 12,
              backgroundColor: const Color(0xFF263238),
              child: Text(num, style: const TextStyle(fontSize: 12, color: Colors.white))
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.grey)))
        ],
      ),
    );
  }
}