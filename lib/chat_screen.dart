import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:orpheus_project/call_screen.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/locale_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:orpheus_project/widgets/app_text_field.dart';
import 'package:orpheus_project/widgets/badge_widget.dart';

class ChatScreen extends StatefulWidget {
  final Contact contact;
  const ChatScreen({super.key, required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();

  List<ChatMessage> _chatHistory = const <ChatMessage>[];
  StreamSubscription<String>? _messageUpdateSubscription;

  late final AnimationController _encryptionController;
  bool _isEncrypting = false;

  // Для отслеживания уже показанных сообщений (анимация появления только один раз)
  final Set<int> _animatedMessageIds = <int>{};

  @override
  void initState() {
    super.initState();

    // Presence: гарантируем, что собеседник находится в watched-наборе.
    presenceService.addWatchedPubkeys([widget.contact.publicKey]);

    _encryptionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _loadChatHistory();
    _markAsRead();

    _messageUpdateSubscription =
        messageUpdateController.stream.listen((senderKey) {
      if (senderKey == widget.contact.publicKey) {
        _loadChatHistory();
        _markAsRead();
      }
    });
  }

  @override
  void dispose() {
    _messageUpdateSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _encryptionController.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    final history = await DatabaseService.instance
        .getMessagesForContact(widget.contact.publicKey);
    if (!mounted) return;
    setState(() => _chatHistory = history);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    });
  }

  Future<void> _markAsRead() async {
    await DatabaseService.instance.markMessagesAsRead(widget.contact.publicKey);
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    HapticFeedback.selectionClick();
    setState(() => _isEncrypting = true);
    _encryptionController.reset();
    _encryptionController.forward();

    final sentMessage = ChatMessage(
      text: messageText,
      isSentByMe: true,
      status: MessageStatus.sent,
      isRead: true,
    );

    await DatabaseService.instance
        .addMessage(sentMessage, widget.contact.publicKey);
    try {
      final payload =
          await cryptoService.encrypt(widget.contact.publicKey, messageText);
      websocketService.sendChatMessage(widget.contact.publicKey, payload);
    } catch (_) {
      // UI не блокируем — сообщение уже сохранено локально.
    }

    _messageController.clear();
    _inputFocusNode.requestFocus();
    await _loadChatHistory();

    if (!mounted) return;
    // Короткая "шифрую" анимация, затем сброс.
    await Future.delayed(const Duration(milliseconds: 250));
    if (mounted) setState(() => _isEncrypting = false);
  }

  Future<void> _confirmClearHistory() async {
    final l10n = L10n.of(context);
    final ok = await AppDialog.show(
      context: context,
      icon: Icons.delete_forever,
      title: l10n.clearHistory,
      content: l10n.clearHistoryWarning,
      primaryLabel: l10n.delete,
      secondaryLabel: l10n.cancel,
      isDanger: true,
    );

    if (!ok) return;
    await DatabaseService.instance.clearChatHistory(widget.contact.publicKey);
    await _loadChatHistory();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    
    return AppScaffold(
      safeArea: false,
      appBar: AppBar(
        titleSpacing: 0,
        title: StreamBuilder<Map<String, bool>>(
          stream: presenceService.stream,
          initialData: const <String, bool>{},
          builder: (context, snapshot) {
            final isOnline = presenceService.isOnline(widget.contact.publicKey);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.contact.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: UserBadge(
                          pubkey: widget.contact.publicKey, compact: true),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? AppColors.success
                            : AppColors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? l10n.online : l10n.offline,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          AppIconButton(
            icon: Icons.call,
            tooltip: l10n.call,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    CallScreen(contactPublicKey: widget.contact.publicKey),
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.more_horiz,
            tooltip: l10n.menu,
            onPressed: _confirmClearHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _chatHistory.isEmpty ? _EmptyChat() : _buildMessagesList(),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    // UI: reverse=true, поэтому "низ" = offset 0.
    final reversedMessages = _chatHistory.reversed.toList(growable: false);
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      itemCount: reversedMessages.length,
      itemBuilder: (context, index) {
        final message = reversedMessages[index];
        final prevMessage = index > 0 ? reversedMessages[index - 1] : null;
        final nextMessage = index < reversedMessages.length - 1
            ? reversedMessages[index + 1]
            : null;

        final showDateDivider = nextMessage == null ||
            !_isSameDay(message.timestamp, nextMessage.timestamp);
        final hideTime = prevMessage != null &&
            _isSameMinute(message.timestamp, prevMessage.timestamp) &&
            message.isSentByMe == prevMessage.isSentByMe;

        return Column(
          children: [
            if (showDateDivider) _DateDivider(date: message.timestamp),
            _buildMessageItem(message, hideTime: hideTime),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }

  Widget _buildMessageItem(ChatMessage message, {required bool hideTime}) {
    final l10n = L10n.of(context);
    final isMyMessage = message.isSentByMe;
    final timeStr = DateFormat('HH:mm').format(message.timestamp);
    final messageId = message.timestamp.millisecondsSinceEpoch;

    final shouldAnimate = !_animatedMessageIds.contains(messageId);
    if (shouldAnimate) _animatedMessageIds.add(messageId);

    final callUi = _callStatusUiFor(message, l10n);
    if (callUi != null) {
      final callWidget = _CallStatusPill(
        ui: callUi,
        timeStr: timeStr,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                CallScreen(contactPublicKey: widget.contact.publicKey),
          ),
        ),
      );

      if (!shouldAnimate) return callWidget;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: callWidget,
        builder: (context, v, child) => Opacity(opacity: v, child: child),
      );
    }

    final bubble = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          child: Column(
            crossAxisAlignment:
                isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMyMessage
                      ? AppColors.info.withOpacity(0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMyMessage ? 18 : 8),
                    bottomRight: Radius.circular(isMyMessage ? 8 : 18),
                  ),
                  border: ContainerBorder(isMyMessage: isMyMessage).border,
                ),
                child: Text(
                  message.text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              if (!hideTime)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 6, right: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                      if (isMyMessage) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.done_all,
                          size: 14,
                          color: AppColors.info.withOpacity(0.85),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (!shouldAnimate) return bubble;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final dx = isMyMessage ? 12.0 * (1 - v) : -12.0 * (1 - v);
        return Transform.translate(
          offset: Offset(dx, 6 * (1 - v)),
          child: Opacity(opacity: v, child: bubble),
        );
      },
    );
  }

  Widget _buildInputBar() {
    final l10n = L10n.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AppTextField(
                controller: _messageController,
                hintText: l10n.messagePlaceholder,
                prefixIcon: Icons.lock_outline,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 10),
            _SendButton(
              isEncrypting: _isEncrypting,
              encryptionController: _encryptionController,
              onTap: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isSameMinute(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;

  String _formatDateDivider(DateTime date) {
    final l10n = L10n.of(context);
    final locale = LocaleService.instance.effectiveLocale.languageCode;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) return l10n.today;
    if (messageDate == yesterday) return l10n.yesterday;
    if (date.year == now.year) return DateFormat('d MMMM', locale).format(date);
    return DateFormat('d MMMM y', locale).format(date);
  }

  _CallStatusUi? _callStatusUiFor(ChatMessage message, L10n l10n) {
    final text = message.text.trim();
    // Совместимость: проверяем и русские и английские варианты
    if (text == 'Входящий звонок' || text == 'Incoming call') {
      return _CallStatusUi(
          icon: Icons.call_received,
          accent: AppColors.success,
          title: l10n.callLabel,
          subtitle: l10n.incoming);
    }
    if (text == 'Исходящий звонок' || text == 'Outgoing call') {
      return _CallStatusUi(
          icon: Icons.call_made,
          accent: AppColors.info,
          title: l10n.callLabel,
          subtitle: l10n.outgoing);
    }
    if (text == 'Пропущен звонок' || text == 'Missed call') {
      final isOutgoing = message.isSentByMe;
      return _CallStatusUi(
        icon: isOutgoing ? Icons.call_made : Icons.call_missed,
        accent: AppColors.danger,
        title: l10n.missedCall,
        subtitle: isOutgoing ? l10n.outgoing : l10n.incoming,
      );
    }
    return null;
  }
}

class ContainerBorder {
  const ContainerBorder({required this.isMyMessage});
  final bool isMyMessage;

  Border get border => Border.all(
        color:
            isMyMessage ? AppColors.info.withOpacity(0.20) : AppColors.outline,
        width: 1,
      );
}

class _EmptyChat extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 44, color: AppColors.textTertiary),
            const SizedBox(height: 14),
            Text(l10n.startConversation,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              l10n.messagesEncrypted,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final label = (context.findAncestorStateOfType<_ChatScreenState>())
            ?._formatDateDivider(date) ??
        '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.divider)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              border: Border.all(color: AppColors.outline),
            ),
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: AppColors.divider)),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isEncrypting,
    required this.encryptionController,
    required this.onTap,
  });

  final bool isEncrypting;
  final AnimationController encryptionController;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: encryptionController,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(encryptionController.value);
        return SizedBox(
          width: 46,
          height: 46,
          child: Material(
            color: AppColors.accent,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            child: InkWell(
              onTap: isEncrypting ? null : onTap,
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              child: Center(
                child: isEncrypting
                    ? Transform.rotate(
                        angle: t * 6.0,
                        child: const Icon(Icons.lock,
                            color: Colors.black, size: 20),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.black, size: 20),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CallStatusUi {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  const _CallStatusUi({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
  });
}

class _CallStatusPill extends StatelessWidget {
  const _CallStatusPill({
    required this.ui,
    required this.timeStr,
    required this.onTap,
  });

  final _CallStatusUi ui;
  final String timeStr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.86),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadii.md,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadii.md,
                  border: Border.all(color: ui.accent.withOpacity(0.30)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: ui.accent.withOpacity(0.12),
                        borderRadius: AppRadii.sm,
                        border: Border.all(color: ui.accent.withOpacity(0.22)),
                      ),
                      child: Icon(ui.icon, color: ui.accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(ui.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(ui.subtitle,
                              style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(timeStr,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
