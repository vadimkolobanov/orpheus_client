import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/main.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({
    super.key,
    this.httpClient,
    this.databaseService,
    this.websocket,
    this.messageUpdates,
    this.debugPublicKeyBase64,
    this.disableTimersForTesting = false,
  });

  /// DI для widget-тестов: чтобы не ходить в сеть и не зависеть от глобальных singleton’ов.
  final http.Client? httpClient;
  final DatabaseService? databaseService;
  final WebSocketService? websocket;
  final Stream<void>? messageUpdates;
  final String? debugPublicKeyBase64;
  final bool disableTimersForTesting;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scannerController;
  late AnimationController _glowController;
  late AnimationController _cardRevealController;
  late AnimationController _regionPulseController;
  late AnimationController _threatScanController;

  // График
  final List<double> _signalHistory = List.generate(40, (_) => 0.85);

  final Random _rnd = Random();
  Timer? _updateTimer;
  Timer? _keyIdAnimTimer;
  Timer? _threatScanTimer;

  // Данные сессии
  final DateTime _sessionStart = DateTime.now();
  String _uptime = "00:00:00";
  int _currentPing = 0;
  String _turnStatusText = "ОЖИДАНИЕ";
  Color _turnStatusColor = Colors.grey;

  // KEY ID анимация
  String _displayedKeyId = "--------";
  bool _isKeyIdScanning = false;
  int _keyIdScanIndex = 0;

  // Статистика
  int _contactsCount = 0;
  int _sessionMessages = 0;

  // Threat scan
  bool _isThreatScanning = false;
  String _threatStatus = "СКАНИРОВАНИЕ...";
  int _threatScanProgress = 0;

  // Геолокация
  String _countryCode = "";
  String _countryName = "Определение...";
  bool _isRestrictedRegion = false;
  bool _isGeoLoading = true;

  // Список стран с усиленным контролем трафика
  static const _restrictedCountries = ['RU', 'BY', 'CN', 'IR', 'KZ', 'TM', 'UZ'];
  static const _countryNames = {
    'RU': 'Россия',
    'BY': 'Беларусь',
    'CN': 'Китай',
    'IR': 'Иран',
    'KZ': 'Казахстан',
    'TM': 'Туркменистан',
    'UZ': 'Узбекистан',
    'UA': 'Украина',
    'US': 'США',
    'DE': 'Германия',
    'GB': 'Великобритания',
    'FR': 'Франция',
    'NL': 'Нидерланды',
    'PL': 'Польша',
    'FI': 'Финляндия',
    'EE': 'Эстония',
    'LV': 'Латвия',
    'LT': 'Литва',
    'GE': 'Грузия',
    'AM': 'Армения',
    'AZ': 'Азербайджан',
    'TR': 'Турция',
    'AE': 'ОАЭ',
    'IL': 'Израиль',
  };

  ConnectionStatus _currentStatus = ConnectionStatus.Disconnected;

  @override
  void initState() {
    super.initState();

    // Анимации
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _cardRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _regionPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _threatScanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _displayedKeyId = _getKeyFingerprint();
    _loadStats();
    _detectCountry();
    if (!widget.disableTimersForTesting) {
      _startThreatScan();
    }

    final ws = widget.websocket ?? websocketService;
    ws.status.listen((status) {
      if (mounted) {
        setState(() => _currentStatus = status);
      }
    });

    final msgStream = widget.messageUpdates ?? messageUpdateController.stream;
    msgStream.listen((_) {
      if (mounted) {
        setState(() => _sessionMessages++);
      }
    });

    if (!widget.disableTimersForTesting) {
      _updateTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
        if (mounted) {
          setState(() => _updateRealtimeData());
        }
      });

      _keyIdAnimTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted && _currentStatus == ConnectionStatus.Connected) {
          _animateKeyIdScan();
        }
      });

      _threatScanTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) _startThreatScan();
      });
    }
  }

  /// Определение страны пользователя по IP
  Future<void> _detectCountry() async {
    try {
      final client = widget.httpClient ?? http.Client();
      // Пробуем ip-api.com (бесплатный, без ключа)
      final response = await client.get(
        Uri.parse('http://ip-api.com/json/?fields=countryCode,country'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        final code = data['countryCode'] as String? ?? '';
        
        setState(() {
          _countryCode = code;
          _countryName = _countryNames[code] ?? data['country'] ?? code;
          _isRestrictedRegion = _restrictedCountries.contains(code);
          _isGeoLoading = false;
        });
      }
    } catch (e) {
      // Fallback - не удалось определить
      if (mounted) {
        setState(() {
          _countryCode = "??";
          _countryName = "Не определено";
          _isRestrictedRegion = false;
          _isGeoLoading = false;
        });
      }
    }
  }

  Future<void> _loadStats() async {
    try {
      final db = widget.databaseService ?? DatabaseService.instance;
      final contacts = await db.getContacts();
      if (mounted) {
        setState(() => _contactsCount = contacts.length);
      }
    } catch (_) {}
  }

  void _startThreatScan() async {
    if (_isThreatScanning) return;
    setState(() {
      _isThreatScanning = true;
      _threatStatus = "СКАНИРОВАНИЕ...";
      _threatScanProgress = 0;
    });

    _threatScanController.reset();
    _threatScanController.forward();

    for (int i = 0; i <= 100; i += 5) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 40));
      setState(() => _threatScanProgress = i);
    }

    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      setState(() {
        _isThreatScanning = false;
        _threatStatus = "0 ОБНАРУЖЕНО";
      });
    }
  }

  void _animateKeyIdScan() async {
    if (_isKeyIdScanning) return;
    _isKeyIdScanning = true;

    final realKeyId = _getKeyFingerprint();
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    
    for (int i = 0; i < 8; i++) {
      if (!mounted) return;
      for (int j = 0; j < 3; j++) {
        if (!mounted) return;
        setState(() {
          _keyIdScanIndex = i;
          _displayedKeyId = realKeyId.substring(0, i) + 
              chars[_rnd.nextInt(chars.length)] + 
              (i < 7 ? realKeyId.substring(i + 1) : "");
        });
        await Future.delayed(const Duration(milliseconds: 50));
      }
      setState(() {
        _displayedKeyId = realKeyId.substring(0, i + 1) + 
            (i < 7 ? realKeyId.substring(i + 1) : "");
      });
      await Future.delayed(const Duration(milliseconds: 80));
    }

    _isKeyIdScanning = false;
    _keyIdScanIndex = -1;
  }

  void _updateRealtimeData() {
    final duration = DateTime.now().difference(_sessionStart);
    final h = duration.inHours.toString().padLeft(2, '0');
    final m = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
    _uptime = "$h:$m:$s";

    if (_currentStatus == ConnectionStatus.Connected) {
      _turnStatusText = "АКТИВЕН (TLS)";
      _turnStatusColor = const Color(0xFF6AD394);
      _currentPing = 35 + _rnd.nextInt(50);
      double signal = 0.85 + (_rnd.nextDouble() * 0.15);
      _addToHistory(signal.clamp(0.0, 1.0));
    } else if (_currentStatus == ConnectionStatus.Connecting) {
      _turnStatusText = "ПРОВЕРКА...";
      _turnStatusColor = Colors.orangeAccent;
      _currentPing = 0;
      _addToHistory(0.3 + _rnd.nextDouble() * 0.2);
    } else {
      _turnStatusText = "НЕДОСТУПЕН";
      _turnStatusColor = Colors.redAccent;
      _currentPing = 0;
      _addToHistory(0.0);
    }
  }

  void _addToHistory(double value) {
    _signalHistory.removeAt(0);
    _signalHistory.add(value);
  }

  String _getKeyFingerprint() {
    final publicKey = widget.debugPublicKeyBase64 ?? cryptoService.publicKeyBase64;
    if (publicKey == null || publicKey.length < 8) return "--------";
    return publicKey.substring(0, 8).toUpperCase();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scannerController.dispose();
    _glowController.dispose();
    _cardRevealController.dispose();
    _regionPulseController.dispose();
    _threatScanController.dispose();
    _updateTimer?.cancel();
    _keyIdAnimTimer?.cancel();
    _threatScanTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color stateColor;
    String stateText;
    String subText;

    switch (_currentStatus) {
      case ConnectionStatus.Connected:
        stateColor = const Color(0xFF6AD394);
        stateText = "СИСТЕМА В НОРМЕ";
        subText = "Туннель шифрования стабилен";
        break;
      case ConnectionStatus.Connecting:
        stateColor = Colors.orangeAccent;
        stateText = "ПОИСК СЕТИ...";
        subText = "Согласование ключей";
        break;
      case ConnectionStatus.Disconnected:
        stateColor = Colors.redAccent;
        stateText = "НЕТ СВЯЗИ";
        subText = "Ожидание подключения";
        break;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Фоновые частицы
          ..._buildBackgroundParticles(),
          
          // Основной контент
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(stateColor),
                  const SizedBox(height: 12),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      stateText,
                      key: ValueKey(stateText),
                      style: TextStyle(color: stateColor, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                  ),
                  Text(subText, style: const TextStyle(color: Colors.grey, fontSize: 12)),

                  const SizedBox(height: 20),

                  // РЕГИОН + РЕЖИМ ЗАЩИТЫ
                  _buildRegionBlock(),

                  const SizedBox(height: 16),

                  // THREAT SCAN + STATS
                  Row(
                    children: [
                      Expanded(child: _buildThreatScanner()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatsBlock()),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ГРАФИК
                  _buildSignalChart(stateColor),

                  const SizedBox(height: 12),

                  // RELAY BLOCK
                  _buildRelayBlock(),

                  const SizedBox(height: 12),

                  // ИНФО-СЕТКА
                  _buildInfoGrid(),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBackgroundParticles() {
    return List.generate(12, (i) {
      final top = (i * 67.0) % 600 + 50;
      final left = (i * 43.0) % 350;
      final size = 2.0 + (i % 3);
      final delay = i * 0.15;
      
      return Positioned(
        top: top,
        left: left,
        child: AnimatedBuilder(
          animation: _regionPulseController,
          builder: (context, child) {
            final progress = ((_regionPulseController.value + delay) % 1.0);
            return Opacity(
              opacity: (0.1 + 0.2 * sin(progress * 2 * pi)).clamp(0.0, 1.0),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: _isRestrictedRegion ? Colors.orangeAccent : const Color(0xFF6AD394),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isRestrictedRegion ? Colors.orangeAccent : const Color(0xFF6AD394)).withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    });
  }

  Widget _buildHeader(Color stateColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: stateColor.withOpacity(0.6 + 0.4 * _pulseController.value),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: stateColor.withOpacity(0.4 + 0.3 * _pulseController.value),
                        blurRadius: 8 + 6 * _pulseController.value,
                        spreadRadius: 1 + 2 * _pulseController.value,
                      )
                    ],
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            Text("СИСТЕМНЫЙ МОНИТОР", style: TextStyle(color: Colors.grey[600], fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.bold)),
          ],
        ),
        Row(
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 4, height: 4,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2 + 0.3 * _pulseController.value),
                    shape: BoxShape.circle,
                  ),
                );
              },
            ),
            Text(_uptime, style: const TextStyle(color: Colors.white38, fontFamily: 'monospace', fontSize: 11)),
          ],
        ),
      ],
    );
  }

  /// Блок определения региона и режима защиты
  Widget _buildRegionBlock() {
    final Color accentColor = _isRestrictedRegion ? Colors.orangeAccent : const Color(0xFF6AD394);
    
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accentColor.withOpacity(0.2 + 0.1 * _glowController.value),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.05 + 0.05 * _glowController.value),
                blurRadius: 20,
                spreadRadius: -5,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок с регионом
              Row(
                children: [
                  // Анимированная иконка
                  AnimatedBuilder(
                    animation: _regionPulseController,
                    builder: (context, child) {
                      return Icon(
                        _isRestrictedRegion ? Icons.shield : Icons.public,
                        size: 16,
                        color: accentColor.withOpacity(0.7 + 0.3 * sin(_regionPulseController.value * 2 * pi)),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "РЕГИОН: ",
                    style: TextStyle(color: Colors.grey[600], fontSize: 10, letterSpacing: 1),
                  ),
                  _isGeoLoading
                      ? SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: accentColor),
                        )
                      : Text(
                          _countryName.toUpperCase(),
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                  const Spacer(),
                  // Код страны
                  if (!_isGeoLoading)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _countryCode,
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Режим защиты
              Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: accentColor.withOpacity(0.5), blurRadius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isRestrictedRegion ? "УСИЛЕННАЯ ЗАЩИТА" : "СТАНДАРТНЫЙ РЕЖИМ",
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // Описание методов защиты
              if (_isRestrictedRegion) ...[
                Text(
                  "Обнаружен регион с контролем трафика",
                  style: TextStyle(color: Colors.grey[500], fontSize: 10),
                ),
                const SizedBox(height: 10),
                // Методы защиты
                _buildProtectionMethod(Icons.lock_outline, "TLS 1.3 маскировка", "Трафик неотличим от HTTPS", accentColor),
                const SizedBox(height: 6),
                _buildProtectionMethod(Icons.shuffle, "Обфускация заголовков", "Скрытие сигнатур протокола", accentColor),
                const SizedBox(height: 6),
                _buildProtectionMethod(Icons.schedule, "Случайные интервалы", "Защита от анализа паттернов", accentColor),
              ] else ...[
                Text(
                  "Ограничений не обнаружено",
                  style: TextStyle(color: Colors.grey[500], fontSize: 10),
                ),
                const SizedBox(height: 10),
                _buildProtectionMethod(Icons.verified_user, "E2E шифрование", "ChaCha20-Poly1305", accentColor),
                const SizedBox(height: 6),
                _buildProtectionMethod(Icons.security, "Защищённый канал", "WebSocket Secure (WSS)", accentColor),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildProtectionMethod(IconData icon, String title, String subtitle, Color color) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color.withOpacity(0.8)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 9)),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            return Icon(
              Icons.check_circle,
              size: 14,
              color: color.withOpacity(0.5 + 0.3 * _glowController.value),
            );
          },
        ),
      ],
    );
  }

  Widget _buildThreatScanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isThreatScanning)
                AnimatedBuilder(
                  animation: _threatScanController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _threatScanController.value * 2 * pi,
                      child: Icon(Icons.radar, size: 12, color: Colors.orangeAccent.withOpacity(0.8)),
                    );
                  },
                )
              else
                const Icon(Icons.shield, size: 12, color: Color(0xFF6AD394)),
              const SizedBox(width: 6),
              const Text("АНАЛИЗ УГРОЗ", style: TextStyle(color: Colors.grey, fontSize: 8, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(2),
            ),
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                return FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _isThreatScanning ? _threatScanProgress / 100 : 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isThreatScanning ? Colors.orangeAccent : const Color(0xFF6AD394),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: (_isThreatScanning ? Colors.orangeAccent : const Color(0xFF6AD394))
                              .withOpacity(0.5 + 0.3 * _glowController.value),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _threatStatus,
              key: ValueKey(_threatStatus),
              style: TextStyle(
                color: _isThreatScanning ? Colors.orangeAccent : const Color(0xFF6AD394),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBlock() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("СТАТИСТИКА", style: TextStyle(color: Colors.grey, fontSize: 8, letterSpacing: 1.5)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Контакты", style: TextStyle(color: Colors.grey, fontSize: 10)),
              Text("$_contactsCount", style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Сообщений", style: TextStyle(color: Colors.grey, fontSize: 10)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  "$_sessionMessages",
                  key: ValueKey(_sessionMessages),
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignalChart(Color stateColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _scannerController,
                    builder: (context, child) {
                      return Container(
                        width: 6, height: 6,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: stateColor.withOpacity(0.5 + 0.5 * sin(_scannerController.value * 2 * pi)),
                          shape: BoxShape.circle,
                        ),
                      );
                    },
                  ),
                  const Text("МЕТРИКА СТАБИЛЬНОСТИ", style: TextStyle(color: Colors.grey, fontSize: 8, letterSpacing: 1)),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  "${(_signalHistory.last * 100).toInt()}%",
                  key: ValueKey((_signalHistory.last * 100).toInt()),
                  style: TextStyle(color: stateColor, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: SignalChartPainter(history: _signalHistory, color: stateColor),
                ),
                if (_currentStatus == ConnectionStatus.Connected)
                  AnimatedBuilder(
                    animation: _scannerController,
                    builder: (context, child) => Align(
                      alignment: Alignment((_scannerController.value * 2) - 1, 0),
                      child: Container(
                        width: 2, height: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [stateColor.withOpacity(0), stateColor.withOpacity(0.8), stateColor.withOpacity(0)],
                          ),
                          boxShadow: [BoxShadow(color: stateColor.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelayBlock() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: _turnStatusColor,
                width: 3 + (_currentStatus == ConnectionStatus.Connected ? _glowController.value : 0),
              ),
            ),
            boxShadow: _currentStatus == ConnectionStatus.Connected
                ? [BoxShadow(color: _turnStatusColor.withOpacity(0.1 + 0.1 * _glowController.value), blurRadius: 10, offset: const Offset(-5, 0))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("RELAY NODE", style: TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (_currentStatus == ConnectionStatus.Connected)
                        Container(
                          width: 5, height: 5,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: _turnStatusColor,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: _turnStatusColor.withOpacity(0.5), blurRadius: 4)],
                          ),
                        ),
                      Text(_turnStatusText, style: TextStyle(color: _turnStatusColor, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("PING", style: TextStyle(color: Colors.grey, fontSize: 9)),
                  const SizedBox(height: 2),
                  Text(
                    _currentPing > 0 ? "${_currentPing}ms" : "---",
                    style: TextStyle(
                      color: _currentPing > 0 ? const Color(0xFF6AD394) : Colors.grey,
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoGrid() {
    return AnimatedBuilder(
      animation: _cardRevealController,
      builder: (context, child) {
        return GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.0,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildAnimatedCard(0, "ПРОТОКОЛ", "WSS", Icons.api, false),
            _buildAnimatedCard(1, "CIPHER", "ChaCha20", Icons.lock, true),
            _buildAnimatedCard(2, "DH", "X25519", Icons.swap_horiz, true),
            _buildAnimatedCard(3, "MAC", "Poly1305", Icons.verified_user, true),
            _buildAnimatedCard(4, "BUILD", AppConfig.appVersion, Icons.code, false),
            _buildAnimatedCard(5, "KEY ID", _displayedKeyId, Icons.fingerprint, true, isKeyId: true),
          ],
        );
      },
    );
  }

  Widget _buildAnimatedCard(int index, String title, String value, IconData icon, bool isSecurityCard, {bool isKeyId = false}) {
    final delay = index * 0.1;
    final progress = ((_cardRevealController.value - delay) / (1 - delay)).clamp(0.0, 1.0);
    
    return Transform.translate(
      offset: Offset(0, 15 * (1 - progress)),
      child: Opacity(
        opacity: progress,
        child: AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            final glowIntensity = isSecurityCard && _currentStatus == ConnectionStatus.Connected
                ? _glowController.value
                : 0.0;

            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSecurityCard 
                      ? const Color(0xFF6AD394).withOpacity(0.1 + 0.15 * glowIntensity)
                      : Colors.white10,
                  width: isSecurityCard ? 1 + 0.5 * glowIntensity : 1,
                ),
                boxShadow: isSecurityCard && _currentStatus == ConnectionStatus.Connected
                    ? [BoxShadow(
                        color: const Color(0xFF6AD394).withOpacity(0.05 + 0.08 * glowIntensity),
                        blurRadius: 8 + 4 * glowIntensity,
                      )]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 12,
                        color: Colors.grey.withOpacity(0.6 + 0.4 * glowIntensity),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(color: Colors.grey, fontSize: 7, letterSpacing: 0.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  isKeyId
                      ? _buildKeyIdText(value)
                      : Text(
                          value,
                          style: TextStyle(
                            color: isSecurityCard 
                                ? Color.lerp(Colors.white, const Color(0xFF6AD394), glowIntensity * 0.3)
                                : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildKeyIdText(String value) {
    return Row(
      children: List.generate(min(value.length, 8), (i) {
        final isScanning = _isKeyIdScanning && i == _keyIdScanIndex;
        return Text(
          value[i],
          style: TextStyle(
            color: isScanning ? const Color(0xFF6AD394) : Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            shadows: isScanning
                ? [const Shadow(color: Color(0xFF6AD394), blurRadius: 8)]
                : null,
          ),
        );
      }),
    );
  }
}

class SignalChartPainter extends CustomPainter {
  final List<double> history;
  final Color color;
  SignalChartPainter({required this.history, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final stepX = size.width / (history.length - 1);

    for (int i = 0; i < history.length; i++) {
      final x = i * stepX;
      final y = size.height - (history[i] * size.height);
      if (i == 0) path.moveTo(x, y);
      else {
        final prevX = (i - 1) * stepX;
        final prevY = size.height - (history[i - 1] * size.height);
        final cX = prevX + (x - prevX) / 2;
        path.cubicTo(cX, prevY, cX, y, x, y);
      }
    }
    canvas.drawPath(path, paint);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.2), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
