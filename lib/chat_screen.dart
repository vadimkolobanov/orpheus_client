// lib/chat_screen.dart
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orpheus_project/call_screen.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/widgets/badge_widget.dart';

class ChatScreen extends StatefulWidget {
  final Contact contact;
  const ChatScreen({super.key, required this.contact});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _messageController = TextEditingController();
  List<ChatMessage> _chatHistory = [];
  late StreamSubscription _messageUpdateSubscription;
  final ScrollController _scrollController = ScrollController();
  
  // Анимации
  late AnimationController _encryptionController;
  late AnimationController _inputGlowController;
  late AnimationController _headerPulseController;
  late AnimationController _sendButtonController;
  late AnimationController _backgroundController;
  late AnimationController _floatingIconsController;
  
  bool _isEncrypting = false;
  bool _inputFocused = false;
  
  // Для отслеживания уже показанных сообщений
  final Set<int> _animatedMessageIds = {};

  @override
  void initState() {
    super.initState();
    // Presence: гарантируем, что собеседник находится в watched-наборе.
    presenceService.addWatchedPubkeys([widget.contact.publicKey]);

    _encryptionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _inputGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _headerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _sendButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    
    _floatingIconsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    
    _loadChatHistory();
    _markAsRead();

    _messageUpdateSubscription = messageUpdateController.stream.listen((senderKey) {
      if (senderKey == widget.contact.publicKey) {
        _loadChatHistory();
        _markAsRead();
      }
    });
  }

  Future<void> _loadChatHistory() async {
    final history = await DatabaseService.instance.getMessagesForContact(widget.contact.publicKey);
    if (mounted) {
      setState(() {
        _chatHistory = history;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _markAsRead() async {
    await DatabaseService.instance.markMessagesAsRead(widget.contact.publicKey);
  }

  @override
  void dispose() {
    _messageUpdateSubscription.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _encryptionController.dispose();
    _inputGlowController.dispose();
    _headerPulseController.dispose();
    _sendButtonController.dispose();
    _backgroundController.dispose();
    _floatingIconsController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    setState(() => _isEncrypting = true);
    _encryptionController.reset();
    _encryptionController.forward();

    final sentMessage = ChatMessage(
        text: messageText,
        isSentByMe: true,
        status: MessageStatus.sent,
        isRead: true
    );

    await DatabaseService.instance.addMessage(sentMessage, widget.contact.publicKey);
    try {
      final payload = await cryptoService.encrypt(widget.contact.publicKey, messageText);
      websocketService.sendChatMessage(widget.contact.publicKey, payload);
    } catch (e) {
      print("Ошибка отправки: $e");
    }
    
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _isEncrypting = false);
    }
    
    _messageController.clear();
    _loadChatHistory();
  }

  void _showClearHistoryDialog() {
    showDialog(
        context: context,
        builder: (context) => _AnimatedDeleteDialog(
          onDelete: () async {
            await DatabaseService.instance.clearChatHistory(widget.contact.publicKey);
            Navigator.pop(context);
            _loadChatHistory();
          },
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050508),
      extendBodyBehindAppBar: true,
      appBar: _buildGlassAppBar(),
      body: Stack(
        children: [
          // Градиентный фон
          _buildAnimatedBackground(),
          
          // Плавающие иконки замков
          _buildFloatingSecurityIcons(),
          
          // Основной контент
          SafeArea(
            child: Column(
              children: [
                // Отступ для AppBar
                const SizedBox(height: 10),
                
                // Список сообщений
                Expanded(
                  child: _chatHistory.isEmpty
                      ? _buildEmptyChatState()
                      : _buildMessagesList(),
                ),
                
                // Поле ввода
                _buildModernInputArea(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _backgroundController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0A0A10),
                Color.lerp(
                  const Color(0xFF0A1020),
                  const Color(0xFF100A20),
                  (sin(_backgroundController.value * 2 * pi) + 1) / 2,
                )!,
                const Color(0xFF050508),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: CustomPaint(
            size: Size.infinite,
            painter: _ChatBackgroundPainter(_backgroundController.value),
          ),
        );
      },
    );
  }

  Widget _buildFloatingSecurityIcons() {
    return AnimatedBuilder(
      animation: _floatingIconsController,
      builder: (context, child) {
        return Stack(
          children: List.generate(6, (index) {
            final baseX = (index * 0.15 + 0.1) * MediaQuery.of(context).size.width;
            final baseY = (index * 0.12 + 0.15) * MediaQuery.of(context).size.height;
            final offset = sin(_floatingIconsController.value * 2 * pi + index) * 20;
            
            return Positioned(
              left: baseX + offset * 0.5,
              top: baseY + offset,
              child: Opacity(
                opacity: 0.03 + 0.02 * sin(_floatingIconsController.value * 2 * pi + index),
                child: Icon(
                  index % 2 == 0 ? Icons.lock_outline : Icons.shield_outlined,
                  size: 24 + (index % 3) * 8,
                  color: const Color(0xFFB0BEC5),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  PreferredSizeWidget _buildGlassAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: AnimatedBuilder(
        animation: _headerPulseController,
        builder: (context, child) {
          final isOnline = presenceService.isOnline(widget.contact.publicKey);
          return ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A10).withOpacity(0.8),
                  border: Border(
                    bottom: BorderSide(
                      color: const Color(0xFFB0BEC5).withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        // Кнопка назад
                        _buildGlassButton(
                          icon: Icons.arrow_back_ios_new,
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        
                        // Аватар
                        _buildAnimatedAvatar(),
                        const SizedBox(width: 14),
                        
                        // Имя и статус
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.contact.name,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Бейдж пользователя
                                  UserBadge(pubkey: widget.contact.publicKey, compact: true),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (isOnline)
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6AD394).withOpacity(
                                          0.6 + 0.4 * _headerPulseController.value,
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF6AD394).withOpacity(0.4),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    const SizedBox(width: 7, height: 7),
                                  const SizedBox(width: 6),
                                  Text(
                                    isOnline ? "В сети" : "Не в сети",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isOnline ? Colors.grey.shade500 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // Кнопки действий
                        _buildGlassButton(
                          icon: Icons.call,
                          color: const Color(0xFF6AD394),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CallScreen(contactPublicKey: widget.contact.publicKey),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildGlassButton(
                          icon: Icons.more_vert,
                          onTap: _showClearHistoryDialog,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          child: Icon(
            icon,
            color: color ?? Colors.white.withOpacity(0.8),
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedAvatar() {
    return AnimatedBuilder(
      animation: _headerPulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                const Color(0xFFB0BEC5).withOpacity(0.5 + 0.3 * _headerPulseController.value),
                const Color(0xFF6AD394).withOpacity(0.3 + 0.2 * _headerPulseController.value),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB0BEC5).withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF1A1A20),
            child: Text(
              widget.contact.name[0].toUpperCase(),
              style: const TextStyle(
                color: Color(0xFFB0BEC5),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyChatState() {
    return Center(
      child: AnimatedBuilder(
        animation: _headerPulseController,
        builder: (context, child) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFB0BEC5).withOpacity(0.05),
                  border: Border.all(
                    color: const Color(0xFFB0BEC5).withOpacity(0.1),
                  ),
                ),
                child: Icon(
                  Icons.chat_bubble_outline,
                  size: 48,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Начните диалог",
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMessagesList() {
    final reversedMessages = _chatHistory.reversed.toList();
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: reversedMessages.length,
      itemBuilder: (context, index) {
        final message = reversedMessages[index];
        // Предыдущее сообщение (визуально снизу) - это index - 1
        final prevMessage = index > 0 ? reversedMessages[index - 1] : null;
        // Следующее сообщение (визуально сверху) - это index + 1
        final nextMessage = index < reversedMessages.length - 1 
            ? reversedMessages[index + 1] 
            : null;
        
        // Показываем разделитель дат, если это первое сообщение дня
        // (следующее сообщение null или имеет другую дату)
        final showDateDivider = nextMessage == null || 
            !_isSameDay(message.timestamp, nextMessage.timestamp);
        
        // Скрываем время, если предыдущее сообщение отправлено в ту же минуту
        final hideTime = prevMessage != null && 
            _isSameMinute(message.timestamp, prevMessage.timestamp) &&
            message.isSentByMe == prevMessage.isSentByMe;
        
        return Column(
          children: [
            if (showDateDivider) _buildDateDivider(message.timestamp),
            _buildMessageItem(message, index, hideTime: hideTime),
          ],
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSameMinute(DateTime a, DateTime b) {
    return a.year == b.year && 
           a.month == b.month && 
           a.day == b.day && 
           a.hour == b.hour && 
           a.minute == b.minute;
  }

  String _formatDateDivider(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);
    
    if (messageDate == today) {
      return 'Сегодня';
    } else if (messageDate == yesterday) {
      return 'Вчера';
    } else if (date.year == now.year) {
      return DateFormat('d MMMM', 'ru').format(date);
    } else {
      return DateFormat('d MMMM y', 'ru').format(date);
    }
  }

  Widget _buildDateDivider(DateTime date) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 0.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    const Color(0xFFB0BEC5).withOpacity(0.2),
                  ],
                ),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF12121A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFB0BEC5).withOpacity(0.1),
              ),
            ),
            child: Text(
              _formatDateDivider(date),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 0.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFB0BEC5).withOpacity(0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage message, int index, {bool hideTime = false}) {
    final isMyMessage = message.isSentByMe;
    final timeStr = DateFormat('HH:mm').format(message.timestamp);
    final messageId = message.timestamp.millisecondsSinceEpoch;
    
    final shouldAnimate = !_animatedMessageIds.contains(messageId);
    if (shouldAnimate) {
      _animatedMessageIds.add(messageId);
    }

    final callUi = _callStatusUiFor(message);
    if (callUi != null) {
      final callWidget = _buildCallStatusItem(message, callUi, timeStr);
      if (shouldAnimate) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: callWidget,
          builder: (context, value, child) {
            return Transform.scale(
              scale: 0.96 + 0.04 * value,
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
        );
      }
      return callWidget;
    }

    Widget messageWidget = Align(
      alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: EdgeInsets.only(
          top: hideTime ? 2 : 4,
          bottom: hideTime ? 2 : 4,
          left: isMyMessage ? 50 : 0,
          right: isMyMessage ? 0 : 50,
        ),
        child: Column(
          crossAxisAlignment: isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Пузырь сообщения
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: isMyMessage ? Alignment.topRight : Alignment.topLeft,
                  end: isMyMessage ? Alignment.bottomLeft : Alignment.bottomRight,
                  colors: isMyMessage
                      ? [
                          const Color(0xFF1E3A5F),
                          const Color(0xFF162D4A),
                        ]
                      : [
                          const Color(0xFF1A1A22),
                          const Color(0xFF151518),
                        ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMyMessage ? 20 : 6),
                  bottomRight: Radius.circular(isMyMessage ? 6 : 20),
                ),
                border: Border.all(
                  color: isMyMessage
                      ? const Color(0xFF4A90D9).withOpacity(0.2)
                      : Colors.white.withOpacity(0.06),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isMyMessage
                        ? const Color(0xFF4A90D9).withOpacity(0.15)
                        : Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Текст сообщения
                  Text(
                    message.text,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            
            // Мета-информация под пузырём (скрываем если hideTime)
            if (!hideTime)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Иконка шифрования
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6AD394).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.lock,
                        size: 8,
                        color: Color(0xFF6AD394),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Время
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    // Галочки для своих сообщений
                    if (isMyMessage) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.done_all,
                        size: 14,
                        color: const Color(0xFF4A90D9).withOpacity(0.8),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    if (shouldAnimate) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(
              isMyMessage ? 40 * (1 - value) : -40 * (1 - value),
              10 * (1 - value),
            ),
            child: Opacity(
              opacity: value,
              child: messageWidget,
            ),
          );
        },
      );
    }

    return messageWidget;
  }

  _CallStatusUi? _callStatusUiFor(ChatMessage message) {
    final text = message.text.trim();

    if (text == 'Входящий звонок') {
      return const _CallStatusUi(
        icon: Icons.call_received,
        accent: Color(0xFF6AD394),
        title: 'Звонок',
        subtitle: 'Входящий',
      );
    }

    if (text == 'Исходящий звонок') {
      return const _CallStatusUi(
        icon: Icons.call_made,
        accent: Color(0xFF4A90D9),
        title: 'Звонок',
        subtitle: 'Исходящий',
      );
    }

    if (text == 'Пропущен звонок') {
      final isOutgoing = message.isSentByMe;
      return _CallStatusUi(
        icon: isOutgoing ? Icons.call_made : Icons.call_missed,
        accent: const Color(0xFFE57373),
        title: 'Пропущенный звонок',
        subtitle: isOutgoing ? 'Исходящий' : 'Входящий',
      );
    }

    return null;
  }

  Widget _buildCallStatusItem(ChatMessage message, _CallStatusUi ui, String timeStr) {
    final isMyMessage = message.isSentByMe;
    final accent = ui.accent;

    return Align(
      alignment: Alignment.center,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CallScreen(contactPublicKey: widget.contact.publicKey),
              ),
            ),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withOpacity(0.16),
                    const Color(0xFF12121A),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: accent.withOpacity(0.32),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: accent.withOpacity(0.28),
                      ),
                    ),
                    child: Icon(
                      ui.icon,
                      color: accent.withOpacity(0.95),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ui.title,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          ui.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (isMyMessage) ...[
                        const SizedBox(height: 2),
                        Icon(
                          Icons.done_all,
                          size: 14,
                          color: const Color(0xFF4A90D9).withOpacity(0.8),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernInputArea() {
    return AnimatedBuilder(
      animation: _inputGlowController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A10).withOpacity(0.95),
            border: Border(
              top: BorderSide(
                color: const Color(0xFFB0BEC5).withOpacity(0.08),
                width: 1,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Поле ввода
              Expanded(
                child: Focus(
                  onFocusChange: (focused) => setState(() => _inputFocused = focused),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12121A),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _inputFocused
                            ? const Color(0xFFB0BEC5).withOpacity(0.25)
                            : Colors.white.withOpacity(0.06),
                        width: 1.5,
                      ),
                      boxShadow: _inputFocused
                          ? [
                              BoxShadow(
                                color: const Color(0xFFB0BEC5).withOpacity(0.08),
                                blurRadius: 20,
                                spreadRadius: -5,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            maxLines: 4,
                            minLines: 1,
                            decoration: InputDecoration(
                              hintText: 'Напишите сообщение...',
                              hintStyle: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ),
                        // Иконка шифрования внутри поля
                        Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Кнопка отправки
              _buildSendButton(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSendButton() {
    return AnimatedBuilder(
      animation: Listenable.merge([_encryptionController, _sendButtonController]),
      builder: (context, child) {
        if (_isEncrypting) {
          return Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF6AD394).withOpacity(0.4),
                  const Color(0xFF6AD394).withOpacity(0.1),
                ],
              ),
              border: Border.all(
                color: const Color(0xFF6AD394),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6AD394).withOpacity(0.4 + 0.3 * _encryptionController.value),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: RotationTransition(
              turns: Tween(begin: 0.0, end: 2.0).animate(
                CurvedAnimation(
                  parent: _encryptionController,
                  curve: Curves.easeInOut,
                ),
              ),
              child: const Icon(Icons.lock, color: Color(0xFF6AD394), size: 22),
            ),
          );
        }
        
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFB0BEC5),
                const Color(0xFF8A9BA8),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB0BEC5).withOpacity(0.25 + 0.15 * _sendButtonController.value),
                blurRadius: 15,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _sendMessage,
              customBorder: const CircleBorder(),
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                child: Transform.rotate(
                  angle: -0.35,
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.black87,
                    size: 22,
                  ),
                ),
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

// Фоновый painter для чата
class _ChatBackgroundPainter extends CustomPainter {
  final double animationValue;
  _ChatBackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final random = Random(42);
    
    // Тонкие линии сетки
    final linePaint = Paint()
      ..color = const Color(0xFFB0BEC5).withOpacity(0.02)
      ..strokeWidth = 0.5;
    
    for (int i = 0; i < 20; i++) {
      final y = (i * size.height / 20);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        linePaint,
      );
    }
    
    // Частицы
    for (int i = 0; i < 30; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.15 + random.nextDouble() * 0.25;
      final particleSize = 1.0 + random.nextDouble() * 2;
      
      final y = (baseY + animationValue * size.height * speed) % size.height;
      final x = baseX + sin(animationValue * 2 * pi + i * 0.5) * 15;
      
      final opacity = 0.02 + 0.04 * sin(animationValue * 2 * pi + i * 0.3);
      
      canvas.drawCircle(
        Offset(x, y),
        particleSize,
        paint..color = const Color(0xFFB0BEC5).withOpacity(opacity.clamp(0.01, 0.06)),
      );
    }
    
    // Несколько более крупных светящихся точек
    for (int i = 0; i < 5; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final pulseOffset = sin(animationValue * 2 * pi + i * 1.5);
      
      canvas.drawCircle(
        Offset(x, y),
        3 + pulseOffset,
        paint..color = const Color(0xFF4A90D9).withOpacity(0.03 + 0.02 * pulseOffset),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Анимированный диалог удаления
class _AnimatedDeleteDialog extends StatefulWidget {
  final VoidCallback onDelete;
  const _AnimatedDeleteDialog({required this.onDelete});

  @override
  State<_AnimatedDeleteDialog> createState() => _AnimatedDeleteDialogState();
}

class _AnimatedDeleteDialogState extends State<_AnimatedDeleteDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      ),
      child: FadeTransition(
        opacity: _controller,
        child: AlertDialog(
          backgroundColor: const Color(0xFF120808),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.red.withOpacity(0.2)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete_forever, color: Colors.red, size: 22),
              ),
              const SizedBox(width: 14),
              const Text('Удалить историю?', style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: Text(
            'Все сообщения будут удалены безвозвратно. Это действие нельзя отменить.',
            style: TextStyle(color: Colors.grey.shade400, height: 1.4),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: widget.onDelete,
                    child: const Text('Удалить'),
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
