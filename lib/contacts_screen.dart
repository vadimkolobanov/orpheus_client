import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orpheus_project/chat_screen.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/qr_scan_screen.dart';
import 'package:orpheus_project/services/badge_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/update_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:orpheus_project/widgets/app_shimmer.dart';
import 'package:orpheus_project/widgets/app_states.dart';
import 'package:orpheus_project/widgets/app_text_field.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/badge_widget.dart';

class ContactsScreen extends StatefulWidget {
  /// В тестах можно отключить async-запросы счётчиков, чтобы не зависеть от SQLite/таймеров.
  final bool enableUnreadCounters;

  const ContactsScreen({super.key, this.enableUnreadCounters = true});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late Future<({List<Contact> contacts, Map<String, int> unreadCounts})>
      _modelFuture;
  StreamSubscription? _updateSubscription;
  Timer? _updateCheckTimer;

  @override
  void initState() {
    super.initState();

    _modelFuture = _loadModel();
    _updateSubscription =
        messageUpdateController.stream.listen((_) => _refreshContacts());

    // В тестах не запускаем фоновые проверки обновлений (иначе появятся таймеры/сетевые запросы).
    if (!const bool.fromEnvironment('FLUTTER_TEST')) {
      _updateCheckTimer?.cancel();
      _updateCheckTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        UpdateService.checkForUpdate(context);
      });
    }
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    _updateSubscription?.cancel();
    super.dispose();
  }

  void _refreshContacts() {
    if (!mounted) return;
    setState(() {
      _modelFuture = _loadModel();
    });
  }

  Future<({List<Contact> contacts, Map<String, int> unreadCounts})>
      _loadModel() async {
    final contacts = await DatabaseService.instance.getContacts();

    // Presence: подписываемся на статусы всех контактов (diff внутри сервиса).
    presenceService.setWatchedPubkeys(contacts.map((c) => c.publicKey));

    // Предзагрузка бейджей для всех контактов (в фоне, не блокируем UI)
    BadgeService.instance
        .preloadBadges(contacts.map((c) => c.publicKey).toList());

    final Map<String, int> unreadCounts;
    if (!widget.enableUnreadCounters) {
      unreadCounts = const <String, int>{};
    } else {
      unreadCounts = await DatabaseService.instance.getUnreadCountsForContacts(
        contacts.map((c) => c.publicKey).toList(),
      );
    }

    return (contacts: contacts, unreadCounts: unreadCounts);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppScaffold(
      safeArea: false,
      appBar: AppBar(
        title: Text(l10n.contactsTitle),
        actions: [
          AppIconButton(
            icon: Icons.qr_code_scanner,
            tooltip: l10n.scanQrTooltip,
            onPressed: () async {
              final scannedKey = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const QrScanScreen()),
              );
              if (scannedKey != null) {
                _showAddContactDialogWithKey(scannedKey);
              }
            },
          ),
          AppIconButton(
            icon: Icons.refresh,
            tooltip: l10n.refreshTooltip,
            onPressed: _refreshContacts,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<
          ({List<Contact> contacts, Map<String, int> unreadCounts})>(
        future: _modelFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ContactsListSkeleton();
          }

          if (snapshot.hasError) {
            return ErrorState(
              title: l10n.loadingError,
              message: snapshot.error.toString(),
              onRetry: _refreshContacts,
            );
          }

          final data = snapshot.data ??
              (contacts: <Contact>[], unreadCounts: const <String, int>{});
          final contacts = data.contacts;
          final unreadCounts = data.unreadCounts;

          if (contacts.isEmpty) {
            return EmptyState(
              title: l10n.noContacts,
              subtitle: l10n.addFirstContact,
              icon: Icons.people_outline,
              actionLabel: l10n.addContact,
              onAction: _showAddContactDialog,
            );
          }

          return StreamBuilder<Map<String, bool>>(
            stream: presenceService.stream,
            initialData: const <String, bool>{},
            builder: (context, presenceSnapshot) {
              final presence = presenceSnapshot.data ?? const <String, bool>{};
              return _buildContactsList(
                contacts: contacts,
                presence: presence,
                unreadCounts: unreadCounts,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildContactsList({
    required List<Contact> contacts,
    required Map<String, bool> presence,
    required Map<String, int> unreadCounts,
  }) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 100),
      itemCount: contacts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final c = contacts[index];
        final isOnline = presence[c.publicKey] == true;
        final unread = unreadCounts[c.publicKey] ?? 0;

        return _ContactRow(
          contact: c,
          isOnline: isOnline,
          unreadCount: unread,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ChatScreen(contact: c)),
            );
            _refreshContacts();
          },
          onLongPress: () => _showContactActionsSheet(c),
        );
      },
    );
  }

  void _showAddContactDialog() {
    _showAddContactDialogWithKey(null);
  }

  void _showAddContactDialogWithKey(String? initialKey) {
    final nameController = TextEditingController();
    final keyController = TextEditingController(text: initialKey);

    showDialog(
      context: context,
      builder: (context) => _AddContactDialog(
        nameController: nameController,
        keyController: keyController,
        onAdd: () async {
          if (nameController.text.isNotEmpty && keyController.text.isNotEmpty) {
            HapticFeedback.selectionClick();
            final newContact = Contact(
              name: nameController.text.trim(),
              publicKey: keyController.text.trim(),
            );
            await DatabaseService.instance.addContact(newContact);
            if (!context.mounted) return;
            Navigator.pop(context);
            _refreshContacts();
          }
        },
        onScanQR: () async {
          final scannedKey = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const QrScanScreen()),
          );
          if (scannedKey != null) {
            keyController.text = scannedKey;
          }
        },
      ),
    );
  }

  void _showContactActionsSheet(Contact contact) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ContactActionsSheet(
        contact: contact,
        onRename: () {
          Navigator.pop(context);
          _showRenameContactDialog(contact);
        },
        onDelete: () {
          Navigator.pop(context);
          _showDeleteContactDialog(contact);
        },
      ),
    );
  }

  void _showRenameContactDialog(Contact contact) async {
    final l10n = L10n.of(context);
    final newName = await AppInputDialog.show(
      context: context,
      icon: Icons.edit,
      title: l10n.renameContact,
      hintText: l10n.enterNewName,
      initialValue: contact.name,
      prefixIcon: Icons.person_outline,
      primaryLabel: l10n.save,
      secondaryLabel: l10n.cancel,
    );

    if (!mounted) return;
    if (newName != null && newName.isNotEmpty && newName != contact.name) {
      HapticFeedback.selectionClick();
      await DatabaseService.instance.updateContactName(contact.id!, newName);
      if (!mounted) return;
      _refreshContacts();
    }
  }

  void _showDeleteContactDialog(Contact contact) {
    showDialog(
      context: context,
      builder: (context) => _DeleteContactDialog(
        contactName: contact.name,
        onDelete: () async {
          HapticFeedback.lightImpact();
          await DatabaseService.instance
              .deleteContact(contact.id!, contact.publicKey);
          if (!context.mounted) return;
          Navigator.pop(context);
          _refreshContacts();
        },
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.isOnline,
    required this.unreadCount,
    required this.onTap,
    required this.onLongPress,
  });

  final Contact contact;
  final bool isOnline;
  final int unreadCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0;
    final subtitle = contact.publicKey.length > 8
        ? '…${contact.publicKey.substring(contact.publicKey.length - 8)}'
        : contact.publicKey;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: AppRadii.md,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.md,
            border: Border.all(
                color: hasUnread
                    ? AppColors.accent.withOpacity(0.22)
                    : AppColors.outline),
          ),
          child: Row(
            children: [
              _Avatar(
                name: contact.name,
                isOnline: isOnline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contact.name,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: hasUnread
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        UserBadge(pubkey: contact.publicKey, compact: true),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.textTertiary,
                            fontFamily: 'monospace',
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (hasUnread)
                _UnreadPill(count: unreadCount)
              else
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.isOnline,
  });

  final String name;
  final bool isOnline;

  String get letter => name.isNotEmpty ? name[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    final gradientColors = AppAvatarColors.gradientFromName(name);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            border: Border.all(color: AppColors.outline),
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
          ),
        ),
        if (isOnline)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.black,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _AddContactDialog extends StatelessWidget {
  const _AddContactDialog({
    required this.nameController,
    required this.keyController,
    required this.onAdd,
    required this.onScanQR,
  });

  final TextEditingController nameController;
  final TextEditingController keyController;
  final VoidCallback onAdd;
  final VoidCallback onScanQR;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: AppRadii.lg,
          side: BorderSide(color: AppColors.outline)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.10),
                    borderRadius: AppRadii.sm,
                  ),
                  child: const Icon(Icons.person_add,
                      color: AppColors.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Text(l10n.newContact,
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 18),
            Text(l10n.contactName, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            AppTextField(
              controller: nameController,
              hintText: l10n.enterName,
              prefixIcon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 14),
            Text(l10n.publicKey,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            AppTextField(
              controller: keyController,
              hintText: l10n.pasteOrScanKey,
              prefixIcon: Icons.key,
              maxLines: 2,
              suffixIcon: IconButton(
                icon:
                    const Icon(Icons.qr_code_scanner, color: AppColors.accent),
                onPressed: onScanQR,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: l10n.cancel,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: l10n.add,
                    onPressed: onAdd,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactActionsSheet extends StatelessWidget {
  const _ContactActionsSheet({
    required this.contact,
    required this.onRename,
    required this.onDelete,
  });

  final Contact contact;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Индикатор
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Заголовок с именем контакта
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: AppAvatarColors.gradientFromName(contact.name),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      contact.name.isNotEmpty
                          ? contact.name[0].toUpperCase()
                          : '?',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '…${contact.publicKey.substring(contact.publicKey.length - 8)}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.textTertiary,
                                    fontFamily: 'monospace',
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            // Действия
            Builder(
              builder: (context) {
                final l10n = L10n.of(context);
                return Column(
                  children: [
                    _ActionTile(
                      icon: Icons.edit_outlined,
                      label: l10n.rename,
                      onTap: onRename,
                    ),
                    _ActionTile(
                      icon: Icons.delete_outline,
                      label: l10n.delete,
                      color: AppColors.danger,
                      onTap: onDelete,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, color: effectiveColor, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: effectiveColor,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteContactDialog extends StatelessWidget {
  const _DeleteContactDialog(
      {required this.contactName, required this.onDelete});

  final String contactName;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.lg,
        side: BorderSide(color: AppColors.danger.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever,
                  color: AppColors.danger, size: 28),
            ),
            const SizedBox(height: 16),
            Text(l10n.deleteContactFull(contactName),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              l10n.deleteContactFullWarning,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: l10n.cancel,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: l10n.delete,
                    variant: AppButtonVariant.danger,
                    onPressed: onDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
