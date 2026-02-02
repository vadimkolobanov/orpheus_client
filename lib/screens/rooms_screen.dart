import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/models/room_model.dart';
import 'package:orpheus_project/screens/room_chat_screen.dart';
import 'package:orpheus_project/services/rooms_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:orpheus_project/widgets/app_states.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  static const String _orpheusRoomId = 'orpheus';

  final RoomsService _service = RoomsService();
  late Future<List<Room>> _roomsFuture;

  @override
  void initState() {
    super.initState();
    _roomsFuture = _service.loadRooms();
  }

  void _refreshRooms() {
    setState(() {
      _roomsFuture = _service.loadRooms();
    });
  }

  Future<void> _showCreateRoomDialog() async {
    final l10n = L10n.of(context);
    final name = await AppInputDialog.show(
      context: context,
      icon: Icons.forum_outlined,
      title: l10n.createRoom,
      hintText: l10n.roomNameHint,
      primaryLabel: l10n.create,
      secondaryLabel: l10n.cancel,
    );

    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;

    try {
      final result = await _service.createRoom(trimmed);
      if (!mounted) return;
      _showInviteCodeDialog(result.inviteCode);
      _refreshRooms();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.roomCreated)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.connectionError)),
      );
    }
  }

  Future<void> _showJoinRoomDialog() async {
    final l10n = L10n.of(context);
    final code = await AppInputDialog.show(
      context: context,
      icon: Icons.vpn_key_outlined,
      title: l10n.joinRoom,
      hintText: l10n.inviteCodeHint,
      primaryLabel: l10n.join,
      secondaryLabel: l10n.cancel,
    );

    final trimmed = code?.trim() ?? '';
    if (trimmed.isEmpty) return;

    try {
      await _service.joinRoom(trimmed);
      if (!mounted) return;
      _refreshRooms();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.roomJoined)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.connectionError)),
      );
    }
  }

  Future<void> _showInviteCodeDialog(String inviteCode) async {
    final l10n = L10n.of(context);
    final ok = await AppDialog.show(
      context: context,
      icon: Icons.vpn_key_outlined,
      title: l10n.inviteCodeTitle,
      content: inviteCode,
      primaryLabel: l10n.copy,
      secondaryLabel: l10n.close,
    );

    if (!ok) return;
    await Clipboard.setData(ClipboardData(text: inviteCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.inviteCodeCopied)),
    );
  }

  void _showRoomActionsSheet() {
    final l10n = L10n.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: Text(l10n.createRoom),
                onTap: () {
                  Navigator.pop(context);
                  _showCreateRoomDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(l10n.joinRoom),
                onTap: () {
                  Navigator.pop(context);
                  _showJoinRoomDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppScaffold(
      safeArea: false,
      appBar: AppBar(
        title: Text(l10n.rooms),
        actions: [
          AppIconButton(
            icon: Icons.refresh,
            tooltip: l10n.refreshTooltip,
            onPressed: _refreshRooms,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showRoomActionsSheet,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Room>>(
        future: _roomsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ErrorState(
              title: l10n.loadingError,
              message: l10n.connectionError,
              onRetry: _refreshRooms,
              retryLabel: l10n.retry,
            );
          }

          final rawRooms = snapshot.data ?? const <Room>[];
          final rooms = _ensureOrpheusRoom(rawRooms, l10n);
          if (rooms.isEmpty) {
            return EmptyState(
              title: l10n.noRooms,
              subtitle: l10n.noRoomsDesc,
              icon: Icons.forum_outlined,
              actionLabel: l10n.createRoom,
              onAction: _showRoomActionsSheet,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 100),
            itemCount: rooms.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final room = rooms[index];
              return _RoomRow(
                room: room,
                isOrpheus: room.id == _orpheusRoomId,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => RoomChatScreen(room: room)),
                  );
                  _refreshRooms();
                },
              );
            },
          );
        },
      ),
    );
  }

  List<Room> _ensureOrpheusRoom(List<Room> rooms, L10n l10n) {
    final hasOrpheus = rooms.any((room) => room.id == _orpheusRoomId);
    if (hasOrpheus) {
      return rooms;
    }

    return [
      Room(
        id: _orpheusRoomId,
        name: l10n.orpheusRoomName,
        membersCount: 0,
      ),
      ...rooms,
    ];
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({
    required this.room,
    required this.onTap,
    required this.isOrpheus,
  });

  final Room room;
  final VoidCallback onTap;
  final bool isOrpheus;

  @override
  Widget build(BuildContext context) {
    final subtitle = room.lastMessagePreview ?? '';
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.md,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.md,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isOrpheus
                      ? AppColors.primary.withOpacity(0.18)
                      : AppColors.primary.withOpacity(0.12),
                  borderRadius: AppRadii.sm,
                ),
                child: isOrpheus
                    ? Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 26,
                            height: 26,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    : const Icon(Icons.forum_outlined,
                        color: AppColors.primary),
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
                            room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (isOrpheus) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: AppColors.primary.withOpacity(0.35)),
                            ),
                            child: Text(
                              L10n.of(context).orpheusOfficialBadge,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: AppColors.primary),
                            ),
                          ),
                        ],
                        if (room.isOwner) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.shield, size: 16, color: AppColors.warning),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
