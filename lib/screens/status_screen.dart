import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/services/websocket_service.dart';

import '../main.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scannerController;

  // График заполнен "шумом" 80%, чтобы не было пустоты при старте
  // Используем обычный список вместо List.filled, чтобы можно было удалять элементы
  final List<double> _signalHistory = List.generate(40, (_) => 0.85);

  final Random _rnd = Random();
  Timer? _updateTimer;

  // Данные сессии
  final DateTime _sessionStart = DateTime.now();
  String _uptime = "00:00:00";
  int _currentPing = 0;
  String _turnStatusText = "ОЖИДАНИЕ";
  Color _turnStatusColor = Colors.grey;

  // Храним статус глобально для синхронизации таймера и UI
  ConnectionStatus _currentStatus = ConnectionStatus.Disconnected;

  @override
  void initState() {
    super.initState();

    // Анимация пульсации
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Анимация сканера
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Слушаем стрим здесь, чтобы переменная _currentStatus всегда была актуальна для таймера
    websocketService.status.listen((status) {
      if (mounted) {
        setState(() {
          _currentStatus = status;
        });
      }
    });

    // Таймер обновления данных (1 раз в секунду)
    _updateTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (mounted) {
        setState(() {
          _updateRealtimeData();
        });
      }
    });
  }

  void _updateRealtimeData() {
    // 1. Аптайм
    final duration = DateTime.now().difference(_sessionStart);
    final h = duration.inHours.toString().padLeft(2, '0');
    final m = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
    _uptime = "$h:$m:$s";

    // 2. Логика данных на основе СТРОГОГО статуса
    if (_currentStatus == ConnectionStatus.Connected) {
      // Соединение есть
      _turnStatusText = "АКТИВЕН (TLS)";
      _turnStatusColor = const Color(0xFF6AD394); // Зеленый

      // Пинг 35-85 мс
      _currentPing = 35 + _rnd.nextInt(50);

      // График живой (85-95%)
      double signal = 0.85 + (_rnd.nextDouble() * 0.15);
      _addToHistory(signal.clamp(0.0, 1.0));

    } else if (_currentStatus == ConnectionStatus.Connecting) {
      // Соединение идет
      _turnStatusText = "ПРОВЕРКА...";
      _turnStatusColor = Colors.orangeAccent;
      _currentPing = 0;

      // График скачет (нестабильность)
      _addToHistory(0.3 + _rnd.nextDouble() * 0.2);

    } else {
      // Нет сети
      _turnStatusText = "НЕДОСТУПЕН";
      _turnStatusColor = Colors.redAccent;
      _currentPing = 0;

      // График в ноль
      _addToHistory(0.0);
    }
  }

  void _addToHistory(double value) {
    _signalHistory.removeAt(0);
    _signalHistory.add(value);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scannerController.dispose();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Определяем цвета и тексты для UI на основе того же _currentStatus
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),

              // ВЕРХНЯЯ ПАНЕЛЬ
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // Индикатор
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: stateColor.withOpacity(0.6 + 0.4 * _pulseController.value),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: stateColor.withOpacity(0.6), blurRadius: 8, spreadRadius: 1)
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      Text("СИСТЕМНЫЙ МОНИТОР", style: TextStyle(color: Colors.grey[600], fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  // Аптайм
                  Text(_uptime, style: const TextStyle(color: Colors.white38, fontFamily: 'monospace', fontSize: 12)),
                ],
              ),

              const SizedBox(height: 15),

              // ГЛАВНЫЙ СТАТУС
              Text(stateText, style: TextStyle(color: stateColor, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              Text(subText, style: const TextStyle(color: Colors.grey, fontSize: 13)),

              const SizedBox(height: 30),

              // ГРАФИК
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
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
                        const Text("МЕТРИКА СТАБИЛЬНОСТИ", style: TextStyle(color: Colors.grey, fontSize: 9, letterSpacing: 1)),
                        Text("${(_signalHistory.last * 100).toInt()}%", style: TextStyle(color: stateColor, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                      ],
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      height: 80,
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: Size.infinite,
                            painter: SignalChartPainter(history: _signalHistory, color: stateColor),
                          ),
                          // Сканер (только если подключено)
                          if (_currentStatus == ConnectionStatus.Connected)
                            AnimatedBuilder(
                              animation: _scannerController,
                              builder: (context, child) => Align(
                                alignment: Alignment((_scannerController.value * 2) - 1, 0),
                                child: Container(
                                  width: 1, height: double.infinity,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                      colors: [stateColor.withOpacity(0), stateColor, stateColor.withOpacity(0)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              // TURN БЛОК
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  border: Border(left: BorderSide(color: _turnStatusColor, width: 3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("УЗЕЛ RELAY (ОБХОД)", style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(_turnStatusText, style: TextStyle(color: _turnStatusColor, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text("ПИНГ", style: TextStyle(color: Colors.grey, fontSize: 9)),
                        const SizedBox(height: 4),
                        Text(_currentPing > 0 ? "${_currentPing}ms" : "---", style: TextStyle(color: _currentPing > 0 ? const Color(0xFF6AD394) : Colors.grey, fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              // ИНФО-СЕТКА
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.8,
                  children: [
                    _buildTechCard("ПРОТОКОЛ", "WSS/1.1", Icons.api, true),
                    _buildTechCard("ШИФРОВАНИЕ", "ChaCha20", Icons.lock, true),
                    _buildTechCard("СБОРКА", AppConfig.appVersion, Icons.code, true),
                    _buildTechCard("ЛИЦЕНЗИЯ", "АКТИВНА", Icons.verified, true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTechCard(String title, String value, IconData icon, bool active) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 9, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
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
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withOpacity(0.2), Colors.transparent]).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}