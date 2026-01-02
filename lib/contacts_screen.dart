import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:orpheus_project/chat_screen.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/qr_scan_screen.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/update_service.dart';
import 'package:orpheus_project/services/badge_service.dart';
import 'package:orpheus_project/widgets/badge_widget.dart';

class ContactsScreen extends StatefulWidget {
  /// В тестах можно отключить async-запросы счётчиков, чтобы не зависеть от SQLite/таймеров.
  final bool enableUnreadCounters;

  const ContactsScreen({super.key, this.enableUnreadCounters = true});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with TickerProviderStateMixin {
  late Future<List<Contact>> _contactsFuture;
  StreamSubscription? _updateSubscription;
  Timer? _updateCheckTimer;
  
  // Анимации
  late AnimationController _fabController;
  late AnimationController _pulseController;
  late AnimationController _backgroundController;
  late AnimationController _floatingController;
  late AnimationController _shimmerController;
  late AnimationController _glowController;
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    
    _floatingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    
    _contactsFuture = _loadContactsWithTimeout();
    _updateSubscription = messageUpdateController.stream.listen((_) {
      _refreshContacts();
    });

    // В тестах не запускаем фоновые проверки обновлений (иначе появятся таймеры/сетевые запросы).
    if (!const bool.fromEnvironment('FLUTTER_TEST')) {
      _updateCheckTimer?.cancel();
      _updateCheckTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        UpdateService.checkForUpdate(context);
      });
    }
  }

  Future<List<Contact>> _loadContactsWithTimeout() async {
    setState(() => _isLoading = true);
    try {
      // Важно: это локальная БД. Таймаут здесь создаёт Timer и ухудшает стабильность widget-тестов.
      // Если будут реальные зависания — лучше решать на уровне DatabaseService/инициализации, а не UI.
      final contacts = await DatabaseService.instance.getContacts();

      // Presence: подписываемся на статусы всех контактов (diff внутри сервиса).
      presenceService.setWatchedPubkeys(contacts.map((c) => c.publicKey));
      
      // Предзагрузка бейджей для всех контактов (в фоне, не блокируем UI)
      BadgeService.instance.preloadBadges(contacts.map((c) => c.publicKey).toList());
      
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return contacts;
    } catch (e) {
      print("Ошибка загрузки контактов: $e");
      if (mounted) setState(() => _isLoading = false);
      return <Contact>[];
    }
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    _updateSubscription?.cancel();
    _fabController.dispose();
    _pulseController.dispose();
    _backgroundController.dispose();
    _floatingController.dispose();
    _shimmerController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _refreshContacts() {
    if (mounted) {
      setState(() {
        _contactsFuture = _loadContactsWithTimeout();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050508),
      body: Stack(
        children: [
          // Анимированный фон
          _buildAnimatedBackground(),
          
          // Плавающие элементы
          _buildFloatingElements(),
          
          // Основной контент
          SafeArea(
            child: Column(
              children: [
                // Кастомный хедер
                _buildHeader(),
                
                // Отступ между хедером и списком
                const SizedBox(height: 8),
                
                // Список контактов
                Expanded(
                  child: FutureBuilder<List<Contact>>(
                    future: _contactsFuture,
                    builder: (context, snapshot) {
                      if (_isLoading) {
                        return _buildLoadingShimmer();
                      }

                      if (snapshot.hasError) {
                        return _buildErrorState(snapshot.error.toString());
                      }

                      final contacts = snapshot.data ?? [];

                      if (contacts.isEmpty) {
                        return _buildEmptyState();
                      }

                      return StreamBuilder<Map<String, bool>>(
                        stream: presenceService.stream,
                        initialData: const <String, bool>{},
                        builder: (context, presenceSnapshot) {
                          final presence = presenceSnapshot.data ?? const <String, bool>{};
                          return _buildContactsList(contacts, presence);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildModernFAB(),
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
                const Color(0xFF08080C),
                Color.lerp(
                  const Color(0xFF0A1018),
                  const Color(0xFF100A18),
                  (sin(_backgroundController.value * 2 * pi) + 1) / 2,
                )!,
                const Color(0xFF050508),
              ],
            ),
          ),
          child: CustomPaint(
            size: Size.infinite,
            painter: _ContactsBackgroundPainter(_backgroundController.value),
          ),
        );
      },
    );
  }

  Widget _buildFloatingElements() {
    return AnimatedBuilder(
      animation: _floatingController,
      builder: (context, child) {
        return Stack(
          children: List.generate(8, (index) {
            final baseX = (index * 0.12 + 0.05) * MediaQuery.of(context).size.width;
            final baseY = (index * 0.1 + 0.1) * MediaQuery.of(context).size.height;
            final offset = sin(_floatingController.value * 2 * pi + index) * 15;
            
            return Positioned(
              left: baseX + offset * 0.5,
              top: baseY + offset,
              child: Opacity(
                opacity: 0.03 + 0.02 * sin(_floatingController.value * 2 * pi + index),
                child: Icon(
                  index % 3 == 0 
                      ? Icons.person_outline 
                      : index % 3 == 1 
                          ? Icons.lock_outline 
                          : Icons.chat_bubble_outline,
                  size: 20 + (index % 4) * 6,
                  color: const Color(0xFFB0BEC5),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildHeader() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              // Лого/иконка
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFB0BEC5).withOpacity(0.15),
                      const Color(0xFFB0BEC5).withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFB0BEC5).withOpacity(0.1),
                  ),
                ),
                child: Icon(
                  Icons.people_alt,
                  color: const Color(0xFFB0BEC5).withOpacity(0.8),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              
              // Заголовок
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "КОНТАКТЫ",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6AD394).withOpacity(
                              0.6 + 0.4 * _pulseController.value
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6AD394).withOpacity(0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Защищённые диалоги",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Кнопка QR
              _buildHeaderButton(
                icon: Icons.qr_code_scanner,
                onTap: () async {
                  final scannedKey = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const QrScanScreen()),
                  );
                  if (scannedKey != null) {
                    _showAddContactDialogWithKey(scannedKey);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          child: Icon(
            icon,
            color: const Color(0xFFB0BEC5).withOpacity(0.8),
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: 5,
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: _shimmerController,
          builder: (context, child) {
            final shimmerPosition = (_shimmerController.value + index * 0.1) % 1.0;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              child: Row(
                children: [
                  // Avatar shimmer
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment(-1 + 2 * shimmerPosition, 0),
                        end: Alignment(1 + 2 * shimmerPosition, 0),
                        colors: [
                          const Color(0xFF1A1A1E),
                          const Color(0xFF252528),
                          const Color(0xFF1A1A1E),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 18,
                          width: 130,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            gradient: LinearGradient(
                              begin: Alignment(-1 + 2 * shimmerPosition, 0),
                              end: Alignment(1 + 2 * shimmerPosition, 0),
                              colors: [
                                const Color(0xFF1A1A1E),
                                const Color(0xFF252528),
                                const Color(0xFF1A1A1E),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 12,
                          width: 90,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              begin: Alignment(-1 + 2 * shimmerPosition, 0),
                              end: Alignment(1 + 2 * shimmerPosition, 0),
                              colors: [
                                const Color(0xFF1A1A1E),
                                const Color(0xFF252528),
                                const Color(0xFF1A1A1E),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline, size: 48, color: Colors.red),
          ),
          const SizedBox(height: 20),
          Text(
            "Ошибка загрузки",
            style: TextStyle(
              color: Colors.grey.shade300,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refreshContacts,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text("Повторить"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB0BEC5),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Анимированная иконка
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFB0BEC5).withOpacity(0.08 + 0.04 * _pulseController.value),
                        Colors.transparent,
                      ],
                    ),
                    border: Border.all(
                      color: const Color(0xFFB0BEC5).withOpacity(0.1 + 0.05 * _pulseController.value),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF12121A),
                      border: Border.all(
                        color: const Color(0xFFB0BEC5).withOpacity(0.15),
                      ),
                    ),
                    child: Icon(
                      Icons.people_outline,
                      size: 48,
                      color: Colors.grey.shade600,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            
            const Text(
              "Нет контактов",
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            
            Text(
              "Добавьте первого собеседника,\nчтобы начать защищённое общение",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            
            const SizedBox(height: 36),
            
            // Кнопка добавления
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB0BEC5).withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: -5,
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _showAddContactDialog,
                icon: const Icon(Icons.person_add, size: 20),
                label: const Text("Добавить контакт"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB0BEC5),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Альтернативный способ
            TextButton.icon(
              onPressed: () async {
                final scannedKey = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const QrScanScreen()),
                );
                if (scannedKey != null) {
                  _showAddContactDialogWithKey(scannedKey);
                }
              },
              icon: Icon(Icons.qr_code, size: 18, color: Colors.grey.shade500),
              label: Text(
                "Сканировать QR-код",
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList(List<Contact> contacts, Map<String, bool> presence) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final isOnline = presence[contact.publicKey] == true;
        
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 400 + index * 60),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 25 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: _buildContactCard(contact, index, isOnline: isOnline),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContactCard(Contact contact, int index, {required bool isOnline}) {
    if (!widget.enableUnreadCounters) {
      return AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _glowController]),
        builder: (context, child) {
          return Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: const [
                    Color(0xFF0E0E12),
                    Color(0xFF0A0A0E),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.05),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      _createPageRoute(ChatScreen(contact: contact)),
                    );
                    _refreshContacts();
                  },
                  onLongPress: () => _showDeleteContactDialog(contact),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Аватар
                        _buildContactAvatar(contact, false, isOnline: isOnline),
                        const SizedBox(width: 16),
                        
                        // Информация
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                contact.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6AD394).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.lock,
                                          size: 9,
                                          color: const Color(0xFF6AD394).withOpacity(0.7),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'E2E',
                                          style: TextStyle(
                                            color: const Color(0xFF6AD394).withOpacity(0.7),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '...${contact.publicKey.length > 8 ? contact.publicKey.substring(contact.publicKey.length - 8) : ""}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // Badge или стрелка
                        _buildArrowButton(),
                      ],
                    ),
                  ),
                ),
              ),
            );
        },
      );
    }

    return FutureBuilder<int>(
      future: DatabaseService.instance.getUnreadCount(contact.publicKey),
      builder: (context, countSnapshot) {
        final unreadCount = countSnapshot.data ?? 0;
        final hasUnread = unreadCount > 0;

        return AnimatedBuilder(
          animation: Listenable.merge([_pulseController, _glowController]),
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: hasUnread
                      ? [
                          const Color(0xFF141420),
                          const Color(0xFF0F0F18),
                        ]
                      : [
                          const Color(0xFF0E0E12),
                          const Color(0xFF0A0A0E),
                        ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: hasUnread
                      ? const Color(0xFFB0BEC5).withOpacity(0.25 + 0.1 * _pulseController.value)
                      : Colors.white.withOpacity(0.05),
                  width: hasUnread ? 1.5 : 1,
                ),
                boxShadow: hasUnread
                    ? [
                        BoxShadow(
                          color: const Color(0xFFB0BEC5).withOpacity(0.08 + 0.05 * _glowController.value),
                          blurRadius: 20,
                          spreadRadius: -5,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      _createPageRoute(ChatScreen(contact: contact)),
                    );
                    _refreshContacts();
                  },
                  onLongPress: () => _showDeleteContactDialog(contact),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Аватар
                        _buildContactAvatar(contact, hasUnread, isOnline: isOnline),
                        const SizedBox(width: 16),

                        // Информация
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      contact.name,
                                      style: TextStyle(
                                        fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                                        color: hasUnread ? Colors.white : Colors.white.withOpacity(0.85),
                                        fontSize: 16,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Бейдж пользователя
                                  UserBadge(pubkey: contact.publicKey, compact: true),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6AD394).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.lock,
                                          size: 9,
                                          color: const Color(0xFF6AD394).withOpacity(0.7),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'E2E',
                                          style: TextStyle(
                                            color: const Color(0xFF6AD394).withOpacity(0.7),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '...${contact.publicKey.length > 8 ? contact.publicKey.substring(contact.publicKey.length - 8) : ""}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Badge или стрелка
                        if (hasUnread) _buildUnreadBadge(unreadCount) else _buildArrowButton(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContactAvatar(Contact contact, bool hasUnread, {required bool isOnline}) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: hasUnread
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFFB0BEC5).withOpacity(0.6 + 0.2 * _pulseController.value),
                          const Color(0xFF6AD394).withOpacity(0.4 + 0.2 * _pulseController.value),
                        ],
                      )
                    : null,
                boxShadow: hasUnread
                    ? [
                        BoxShadow(
                          color: const Color(0xFFB0BEC5).withOpacity(0.25),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: hasUnread
                        ? [
                            const Color(0xFFB0BEC5),
                            const Color(0xFF8A9BA8),
                          ]
                        : [
                            const Color(0xFF1E1E24),
                            const Color(0xFF16161A),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    contact.name.isNotEmpty ? contact.name[0].toUpperCase() : "?",
                    style: TextStyle(
                      color: hasUnread ? Colors.black : Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
            ),
            if (isOnline)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6AD394),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF050508),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6AD394).withOpacity(0.35),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildUnreadBadge(int count) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFB0BEC5),
                const Color(0xFF8A9BA8),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB0BEC5).withOpacity(0.35 + 0.15 * _pulseController.value),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  Widget _buildArrowButton() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Icon(
        Icons.arrow_forward_ios,
        color: Colors.grey.shade600,
        size: 14,
      ),
    );
  }

  Widget _buildModernFAB() {
    return AnimatedBuilder(
      animation: _fabController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB0BEC5).withOpacity(0.25 + 0.15 * _fabController.value),
                blurRadius: 20 + 10 * _fabController.value,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showAddContactDialog,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFB0BEC5),
                      const Color(0xFF8A9BA8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.add,
                  color: Colors.black,
                  size: 28,
                ),
              ),
            ),
          ),
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
      builder: (context) => _ModernAddContactDialog(
        nameController: nameController,
        keyController: keyController,
        onAdd: () async {
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

  void _showDeleteContactDialog(Contact contact) {
    showDialog(
      context: context,
      builder: (context) => _ModernDeleteDialog(
        contactName: contact.name,
        onDelete: () async {
          await DatabaseService.instance.deleteContact(contact.id!, contact.publicKey);
          Navigator.pop(context);
          _refreshContacts();
        },
      ),
    );
  }

  PageRouteBuilder _createPageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}

// Background painter
class _ContactsBackgroundPainter extends CustomPainter {
  final double animationValue;
  _ContactsBackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final random = Random(42);
    
    // Сетка
    final linePaint = Paint()
      ..color = const Color(0xFFB0BEC5).withOpacity(0.015)
      ..strokeWidth = 0.5;
    
    for (int i = 0; i < 25; i++) {
      final y = (i * size.height / 25);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    
    // Частицы
    for (int i = 0; i < 35; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.1 + random.nextDouble() * 0.2;
      final particleSize = 1.0 + random.nextDouble() * 1.5;
      
      final y = (baseY + animationValue * size.height * speed) % size.height;
      final x = baseX + sin(animationValue * 2 * pi + i * 0.4) * 12;
      
      final opacity = 0.015 + 0.03 * sin(animationValue * 2 * pi + i * 0.3);
      
      canvas.drawCircle(
        Offset(x, y),
        particleSize,
        paint..color = const Color(0xFFB0BEC5).withOpacity(opacity.clamp(0.01, 0.05)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Modern Add Contact Dialog
class _ModernAddContactDialog extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController keyController;
  final VoidCallback onAdd;
  final VoidCallback onScanQR;

  const _ModernAddContactDialog({
    required this.nameController,
    required this.keyController,
    required this.onAdd,
    required this.onScanQR,
  });

  @override
  State<_ModernAddContactDialog> createState() => _ModernAddContactDialogState();
}

class _ModernAddContactDialogState extends State<_ModernAddContactDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isUpdatingKey = false; // Флаг для предотвращения рекурсии при обновлении ключа

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

  /// Извлекает ключ из полного текста сообщения
  /// Ищет строку после "Мой ключ:" или "ключ:" или просто длинную строку, похожую на ключ
  String? _extractKeyFromText(String text) {
    if (text.trim().isEmpty) return null;
    
    final cleaned = text.trim();
    
    // Сначала проверяем, не является ли весь текст уже ключом (длинная строка без пробелов и без обычных слов)
    final singleLine = cleaned.replaceAll(RegExp(r'\s+'), '');
    if (singleLine.length > 20 && 
        !singleLine.toLowerCase().contains('привет') &&
        !singleLine.toLowerCase().contains('добавь') &&
        !singleLine.toLowerCase().contains('орфей') &&
        !singleLine.toLowerCase().contains('orpheus') &&
        !singleLine.toLowerCase().contains('мой') &&
        !singleLine.toLowerCase().contains('ключ')) {
      return singleLine;
    }
    
    // Ищем паттерн "Мой ключ:" или "ключ:" (с учетом регистра и возможных вариаций)
    final keyPattern = RegExp(r'(?:Мой\s+)?ключ\s*:?\s*', caseSensitive: false);
    final match = keyPattern.firstMatch(cleaned);
    
    if (match != null) {
      // Берем текст после "Мой ключ:" или "ключ:"
      var keyCandidate = cleaned.substring(match.end).trim();
      
      // Убираем все переносы строк, пробелы и другие символы форматирования
      keyCandidate = keyCandidate.replaceAll(RegExp(r'\s+'), '').trim();
      
      // Если получили что-то похожее на ключ (длинная строка без пробелов)
      if (keyCandidate.isNotEmpty && keyCandidate.length > 20) {
        return keyCandidate;
      }
      
      // Если после "ключ:" идет перенос строки, берем следующую строку
      final linesAfterKey = cleaned.substring(match.end).split('\n');
      for (final line in linesAfterKey) {
        final trimmed = line.trim().replaceAll(RegExp(r'\s+'), '');
        if (trimmed.length > 20 && 
            !trimmed.toLowerCase().contains('привет') &&
            !trimmed.toLowerCase().contains('добавь') &&
            !trimmed.toLowerCase().contains('орфей') &&
            !trimmed.toLowerCase().contains('orpheus')) {
          return trimmed;
        }
      }
    }
    
    // Если паттерн не найден, ищем самую длинную строку (вероятно, это ключ)
    final lines = cleaned.split('\n');
    String? longestLine;
    int maxLength = 0;
    
    for (final line in lines) {
      final trimmed = line.trim().replaceAll(RegExp(r'\s+'), '');
      // Игнорируем строки, которые явно не ключи (короткие или содержат обычный текст)
      if (trimmed.length > maxLength && 
          trimmed.length > 20 && 
          !trimmed.toLowerCase().contains('привет') &&
          !trimmed.toLowerCase().contains('добавь') &&
          !trimmed.toLowerCase().contains('орфей') &&
          !trimmed.toLowerCase().contains('orpheus') &&
          !trimmed.toLowerCase().contains('мой') &&
          !trimmed.toLowerCase().contains('ключ')) {
        longestLine = trimmed;
        maxLength = trimmed.length;
      }
    }
    
    return longestLine;
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      ),
      child: FadeTransition(
        opacity: _controller,
        child: Dialog(
          backgroundColor: const Color(0xFF0E0E14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: const Color(0xFFB0BEC5).withOpacity(0.15)),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB0BEC5).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.person_add, color: Color(0xFFB0BEC5), size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Новый контакт',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                
                const SizedBox(height: 24),
                
                // Name field
                _buildTextField(
                  controller: widget.nameController,
                  label: 'Имя',
                  hint: 'Введите имя контакта',
                  icon: Icons.person_outline,
                ),
                
                const SizedBox(height: 16),
                
                // Key field
                _buildTextField(
                  controller: widget.keyController,
                  label: 'Публичный ключ',
                  hint: 'Вставьте или отсканируйте ключ',
                  icon: Icons.key,
                  maxLines: 2,
                  isMonospace: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFB0BEC5)),
                    onPressed: widget.onScanQR,
                  ),
                  onChanged: (text) {
                    // Пропускаем обработку, если мы сами обновляем поле (предотвращение рекурсии)
                    if (_isUpdatingKey) return;
                    
                    // Автоматически извлекаем ключ из вставленного текста
                    final extractedKey = _extractKeyFromText(text);
                    if (extractedKey != null && extractedKey != text) {
                      // Обновляем поле только если извлеченный ключ отличается от вставленного текста
                      _isUpdatingKey = true;
                      widget.keyController.value = TextEditingValue(
                        text: extractedKey,
                        selection: TextSelection.collapsed(offset: extractedKey.length),
                      );
                      // Сбрасываем флаг после небольшой задержки
                      Future.microtask(() => _isUpdatingKey = false);
                    }
                  },
                ),
                
                const SizedBox(height: 24),
                
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                          ),
                        ),
                        child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: widget.onAdd,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB0BEC5),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Добавить'),
                      ),
                    ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    bool isMonospace = false,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          onChanged: onChanged,
          style: TextStyle(
            fontFamily: isMonospace ? 'monospace' : null,
            fontSize: isMonospace ? 12 : 14,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade600),
            prefixIcon: Icon(icon, color: Colors.grey.shade600, size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFF16161C),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFB0BEC5), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}

// Modern Delete Dialog
class _ModernDeleteDialog extends StatefulWidget {
  final String contactName;
  final VoidCallback onDelete;

  const _ModernDeleteDialog({
    required this.contactName,
    required this.onDelete,
  });

  @override
  State<_ModernDeleteDialog> createState() => _ModernDeleteDialogState();
}

class _ModernDeleteDialogState extends State<_ModernDeleteDialog> with SingleTickerProviderStateMixin {
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
        child: Dialog(
          backgroundColor: const Color(0xFF120808),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.red.withOpacity(0.2)),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_forever, color: Colors.red, size: 32),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  Text(
                    'Удалить ${widget.contactName}?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    softWrap: true,
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 12),
                  
                  Text(
                    'Контакт и вся история переписки\nбудут удалены безвозвратно',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                      height: 1.4,
                    ),
                    softWrap: true,
                  ),
                
                const SizedBox(height: 24),
                
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                          ),
                        ),
                        child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: widget.onDelete,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Удалить'),
                      ),
                    ),
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
}
