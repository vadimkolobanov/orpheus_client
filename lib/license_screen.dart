// lib/license_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/main.dart';

class LicenseScreen extends StatefulWidget {
  final VoidCallback onLicenseConfirmed;
  const LicenseScreen({
    super.key,
    required this.onLicenseConfirmed,
    Stream<String>? debugWsStreamOverride,
  }) : _debugWsStreamOverride = debugWsStreamOverride;

  final Stream<String>? _debugWsStreamOverride;

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> with TickerProviderStateMixin {
  // Состояние Promo
  final TextEditingController _promoController = TextEditingController();
  bool _isActivatingPromo = false;
  String? _promoError;
  bool _inputFocused = false;
  
  // Анимации
  late AnimationController _backgroundController;
  late AnimationController _pulseController;
  late AnimationController _glowController;
  late AnimationController _floatingController;

  StreamSubscription? _wsSubscription;

  @override
  void initState() {
    super.initState();
    
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _floatingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    final wsStream = widget._debugWsStreamOverride ?? websocketService.stream;
    _wsSubscription = wsStream.listen((message) {
      try {
        final data = json.decode(message);
        if (data['type'] == 'payment-confirmed' ||
            (data['type'] == 'license-status' && data['status'] == 'active')) {
          widget.onLicenseConfirmed();
        }
      } catch (_) {}
    });
  }

  Future<void> _activatePromo() async {
    final code = _promoController.text.trim();

    if (code.isEmpty) {
      setState(() => _promoError = "Введите код");
      return;
    }

    setState(() {
      _isActivatingPromo = true;
      _promoError = null;
    });

    try {
      final myPubkey = cryptoService.publicKeyBase64;
      if (myPubkey == null) throw Exception("Ключи не инициализированы");

      final url = Uri.parse(AppConfig.httpUrl('/api/activate-promo'));
      print("Sending promo request to $url with code: $code");

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "pubkey": myPubkey,
          "code": code
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['status'] == 'ok') {
        if (mounted) {
          _showSuccessDialog();
        }
      } else {
        setState(() {
          _promoError = data['message'] ?? "Неверный код";
        });
      }
    } catch (e) {
      setState(() {
        _promoError = "Ошибка соединения. Проверьте интернет.";
      });
      print("Promo error: $e");
    } finally {
      if (mounted) setState(() => _isActivatingPromo = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SuccessDialog(
        onConfirm: () {
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _promoController.dispose();
    _backgroundController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    _floatingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF050508),
        extendBodyBehindAppBar: true,
        appBar: _buildGlassAppBar(),
        body: Stack(
          children: [
            // Анимированный фон
            _buildAnimatedBackground(),
            
            // Плавающие иконки
            _buildFloatingIcons(),
            
            // Основной контент
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    
                    // Иконка с анимацией
                    _buildAnimatedIcon(),
                    
                    const SizedBox(height: 32),
                    
                    // Заголовок
                    _buildTitle(),
                    
                    const SizedBox(height: 12),
                    
                    // Описание
                    _buildDescription(),
                    
                    const SizedBox(height: 40),
                    
                    // Карточка ввода кода
                    _buildInputCard(),
                    
                    const SizedBox(height: 32),
                    
                    // Кнопка активации
                    _buildActivateButton(),
                    
                    const SizedBox(height: 40),
                    
                    // Информационный блок
                    _buildInfoSection(),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildGlassAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: ClipRRect(
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Кнопка назад
                    _buildGlassButton(
                      icon: Icons.arrow_back_ios_new,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 16),
                    
                    // Заголовок
                    const Text(
                      "АКТИВАЦИЯ",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
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
            color: Colors.white.withOpacity(0.8),
            size: 20,
          ),
        ),
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
            painter: _BackgroundPainter(_backgroundController.value),
          ),
        );
      },
    );
  }

  Widget _buildFloatingIcons() {
    return AnimatedBuilder(
      animation: _floatingController,
      builder: (context, child) {
        return Stack(
          children: List.generate(8, (index) {
            final baseX = (index * 0.12 + 0.08) * MediaQuery.of(context).size.width;
            final baseY = (index * 0.1 + 0.12) * MediaQuery.of(context).size.height;
            final offset = sin(_floatingController.value * 2 * pi + index) * 20;
            
            return Positioned(
              left: baseX + offset * 0.5,
              top: baseY + offset,
              child: Opacity(
                opacity: 0.03 + 0.02 * sin(_floatingController.value * 2 * pi + index),
                child: Icon(
                  index % 3 == 0 
                      ? Icons.key 
                      : index % 3 == 1 
                          ? Icons.vpn_key_outlined 
                          : Icons.lock_outline,
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

  Widget _buildAnimatedIcon() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _glowController]),
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFFB0BEC5).withOpacity(0.15 + 0.1 * _glowController.value),
                const Color(0xFFB0BEC5).withOpacity(0.05),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB0BEC5).withOpacity(0.15 + 0.1 * _glowController.value),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0A0A10),
              border: Border.all(
                color: const Color(0xFFB0BEC5).withOpacity(0.3 + 0.2 * _pulseController.value),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.vpn_key,
              size: 48,
              color: const Color(0xFFB0BEC5).withOpacity(0.8 + 0.2 * _pulseController.value),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitle() {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFFB0BEC5), Color(0xFFE0E8ED)],
      ).createShader(bounds),
      child: const Text(
        "ВВЕДИТЕ КОД",
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 3,
        ),
      ),
    );
  }

  Widget _buildDescription() {
    return Text(
      "Введите код активации, полученный\nпри покупке лицензии",
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.grey.shade500,
        fontSize: 14,
        height: 1.5,
      ),
    );
  }

  Widget _buildInputCard() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A10).withOpacity(0.8),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _inputFocused
                  ? const Color(0xFFB0BEC5).withOpacity(0.3)
                  : Colors.white.withOpacity(0.06),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB0BEC5).withOpacity(0.05 + 0.03 * _glowController.value),
                blurRadius: 30,
                spreadRadius: -5,
              ),
            ],
          ),
          child: Column(
            children: [
              // Метка поля
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB0BEC5).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.key,
                      size: 16,
                      color: const Color(0xFFB0BEC5).withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "КОД АКТИВАЦИИ",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // Поле ввода
              Focus(
                onFocusChange: (focused) => setState(() => _inputFocused = focused),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12121A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _promoError != null
                          ? Colors.red.withOpacity(0.5)
                          : _inputFocused
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
                  child: TextField(
                    controller: _promoController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontFamily: 'monospace',
                      letterSpacing: 3,
                    ),
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.visiblePassword,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'XXXX-XXXX-XXXX',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 20,
                        letterSpacing: 3,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                    ),
                  ),
                ),
              ),
              
              // Сообщение об ошибке
              if (_promoError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: Colors.red.shade300,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _promoError!,
                          style: TextStyle(
                            color: Colors.red.shade300,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivateButton() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
                color: const Color(0xFFB0BEC5).withOpacity(0.2 + 0.1 * _pulseController.value),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isActivatingPromo ? null : _activatePromo,
              borderRadius: BorderRadius.circular(16),
              child: Center(
                child: _isActivatingPromo
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.black87,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.black87,
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Text(
                            "АКТИВИРОВАТЬ",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF6AD394).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6AD394).withOpacity(0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF6AD394).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.info_outline,
              color: Color(0xFF6AD394),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Поддерживаемые форматы",
                  style: TextStyle(
                    color: Color(0xFF6AD394),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Буквы, цифры, а также символы _ и -",
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Фоновый painter
class _BackgroundPainter extends CustomPainter {
  final double animationValue;
  _BackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final random = Random(42);
    
    // Тонкие линии сетки
    final linePaint = Paint()
      ..color = const Color(0xFFB0BEC5).withOpacity(0.015)
      ..strokeWidth = 0.5;
    
    for (int i = 0; i < 15; i++) {
      final y = (i * size.height / 15);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        linePaint,
      );
    }
    
    // Частицы
    for (int i = 0; i < 25; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.1 + random.nextDouble() * 0.2;
      final particleSize = 1.0 + random.nextDouble() * 2;
      
      final y = (baseY + animationValue * size.height * speed) % size.height;
      final x = baseX + sin(animationValue * 2 * pi + i * 0.5) * 12;
      
      final opacity = 0.02 + 0.03 * sin(animationValue * 2 * pi + i * 0.3);
      
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

// Диалог успешной активации
class _SuccessDialog extends StatefulWidget {
  final VoidCallback onConfirm;
  const _SuccessDialog({required this.onConfirm});

  @override
  State<_SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends State<_SuccessDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
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
          backgroundColor: const Color(0xFF0A120A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: const Color(0xFF6AD394).withOpacity(0.3)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6AD394).withOpacity(0.15),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Color(0xFF6AD394),
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Код принят!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Лицензия успешно активирована',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6AD394),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: widget.onConfirm,
                  child: const Text(
                    'ОТЛИЧНО',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
