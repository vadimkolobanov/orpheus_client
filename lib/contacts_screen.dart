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
import 'package:orpheus_project/qr_scan_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
    _refreshContacts();
    _updateSubscription = messageUpdateController.stream.listen((_) {
      _refreshContacts();
    });

    // ---> ЗАПУСК ПРОВЕРКИ ОБНОВЛЕНИЙ <---
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        UpdateService.checkForUpdate(context);
      }
    });
    // ------------------------------------
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

        // Закрываем BottomSheet перед показом алерта, если он открыт
        if (Navigator.canPop(context)) Navigator.pop(context);

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

  // --- ДОБАВЛЕНИЕ КОНТАКТА ---
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
                  tooltip: "Сканировать QR",
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

  // --- НИЖНЯЯ ПАНЕЛЬ: МОЯ ВИЗИТКА ---
  void _showMyIdentitySheet() {
    final myKey = cryptoService.publicKeyBase64 ?? "Ошибка";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Разрешаем скролл если экран маленький
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Маркер для свайпа
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
            ),

            const Text(
              "МОЙ ID",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white),
            ),
            const SizedBox(height: 20),

            // QR КОД
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: myKey,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 20),

            // ТЕКСТОВЫЙ КЛЮЧ
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
                style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFECEFF1), fontSize: 12),
              ),
            ),

            const SizedBox(height: 20),

            // КНОПКИ
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
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ID скопирован")));
                      Navigator.pop(context);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text("ОТПРАВИТЬ"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      try {
                        Share.share("Привет! Добавь меня в Orpheus.\nМой ключ:\n$myKey");
                      } catch (e) {
                        Clipboard.setData(ClipboardData(text: myKey));
                      }
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // КНОПКА БЕЗОПАСНОСТИ (ЭКСПОРТ)
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                icon: const Icon(Icons.shield, size: 16, color: Colors.redAccent),
                label: const Text("ЭКСПОРТ АККАУНТА", style: TextStyle(color: Colors.redAccent)),
                onPressed: _exportAccount,
              ),
            ),

            const SizedBox(height: 20),
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
              final color = snapshot.data == ConnectionStatus.Connected ? const Color(0xFF6AD394) : Colors.redAccent;
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Icon(Icons.circle, color: color, size: 10),
              );
            },
          ),
          // ГЛАВНАЯ КНОПКА ВИЗИТКИ (ВМЕСТО ОГРОМНОЙ КАРТОЧКИ)
          IconButton(
            icon: const Icon(Icons.badge_outlined, size: 28), // Иконка ID карты
            tooltip: "Мой ID",
            color: Theme.of(context).colorScheme.primary,
            onPressed: _showMyIdentitySheet, // Вызывает шторку снизу
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
                      "НЕТ КОНТАКТОВ",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Нажмите +, чтобы добавить друга.\nОбменяйтесь ключами любым способом.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          // --- СПИСОК КОНТАКТОВ ---
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
                        'ID: ...${contact.publicKey.length > 8 ? contact.publicKey.substring(contact.publicKey.length - 8) : ""}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12, fontFamily: 'monospace'),
                      ),
                      trailing: unreadCount > 0
                          ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: Text(unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                          : const Icon(Icons.chevron_right, color: Colors.grey),

                      // ЗВОНКИ НЕ ТРОГАЛИ, ПЕРЕХОД В ЧАТ РАБОТАЕТ
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
        child: const Icon(Icons.add, color: Colors.black, size: 32), // Кнопка "+"
      ),
    );
  }
}