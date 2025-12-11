// lib/welcome_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:orpheus_project/main.dart';

class WelcomeScreen extends StatefulWidget {
  final VoidCallback onAuthComplete;
  const WelcomeScreen({super.key, required this.onAuthComplete});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  final _importController = TextEditingController();
  
  // Анимации
  late AnimationController _particlesController;
  late AnimationController _glowController;
  late AnimationController _revealController;
  late AnimationController _pulseController;
  late AnimationController _scanLineController;
  
  // Анимации появления элементов
  late Animation<double> _logoOpacity;
  late Animation<double> _logoScale;
  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleSlide;
  late Animation<double> _subtitleOpacity;
  late Animation<double> _buttonsOpacity;
  late Animation<Offset> _buttonsSlide;

  @override
  void initState() {
    super.initState();
    
    // Контроллер частиц
    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    
    // Контроллер glow эффекта
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    
    // Контроллер reveal анимации
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    
    // Пульсация кнопки
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    // Scanning line на логотипе
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    
    // Настройка staggered анимаций
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _revealController, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
    );
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _revealController, curve: const Interval(0.0, 0.4, curve: Curves.elasticOut)),
    );
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _revealController, curve: const Interval(0.25, 0.55, curve: Curves.easeOut)),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _revealController, curve: const Interval(0.25, 0.55, curve: Curves.easeOut)),
    );
    _subtitleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _revealController, curve: const Interval(0.4, 0.7, curve: Curves.easeOut)),
    );
    _buttonsOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _revealController, curve: const Interval(0.6, 1.0, curve: Curves.easeOut)),
    );
    _buttonsSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _revealController, curve: const Interval(0.6, 1.0, curve: Curves.easeOut)),
    );
    
    // Запуск reveal анимации
    Future.delayed(const Duration(milliseconds: 300), () {
      _revealController.forward();
    });
  }

  @override
  void dispose() {
    _particlesController.dispose();
    _glowController.dispose();
    _revealController.dispose();
    _pulseController.dispose();
    _scanLineController.dispose();
    super.dispose();
  }

  void _createNewAccount() async {
    await cryptoService.generateNewKeys();
    widget.onAuthComplete();
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ВОССТАНОВЛЕНИЕ"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Введите ваш Приватный ключ:", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            TextField(
              controller: _importController,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: "Вставьте ключ...",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ОТМЕНА")),
          ElevatedButton(
            onPressed: () async {
              final key = _importController.text.trim();
              if (key.isEmpty) return;
              try {
                await cryptoService.importPrivateKey(key);
                if (mounted) {
                  Navigator.pop(context);
                  widget.onAuthComplete();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Ошибка: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text("ИМПОРТ"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Градиентный фон
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0A0A0A), Color(0xFF000000)],
              ),
            ),
          ),
          
          // Частицы на фоне
          AnimatedBuilder(
            animation: _particlesController,
            builder: (context, child) => CustomPaint(
              size: Size.infinite,
              painter: _WelcomeParticlesPainter(_particlesController.value),
            ),
          ),
          
          // Основной контент
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Логотип с glow эффектом
                  AnimatedBuilder(
                    animation: Listenable.merge([_revealController, _glowController, _scanLineController]),
                    builder: (context, child) {
                      return Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Glow rings
                              ...List.generate(3, (i) {
                                final size = 180.0 + i * 30;
                                return Container(
                                  width: size,
                                  height: size,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFB0BEC5).withOpacity(
                                        (0.1 - i * 0.03) * (0.5 + 0.5 * _glowController.value)
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                );
                              }),
                              // Основной glow
                              Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFB0BEC5).withOpacity(0.15 + 0.1 * _glowController.value),
                                      blurRadius: 40 + 20 * _glowController.value,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                              ),
                              // Логотип
                              ClipRRect(
                                borderRadius: BorderRadius.circular(80),
                                child: Stack(
                                  children: [
                                    Image.asset(
                                      'assets/images/logo.png',
                                      height: 160,
                                      errorBuilder: (c, e, s) {
                                        return Container(
                                          width: 160,
                                          height: 160,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: RadialGradient(
                                              colors: [
                                                const Color(0xFFB0BEC5).withOpacity(0.3),
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                          child: const Icon(Icons.shield, size: 80, color: Color(0xFFB0BEC5)),
                                        );
                                      },
                                    ),
                                    // Scanning line
                                    Positioned(
                                      top: _scanLineController.value * 160,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        height: 2,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.transparent,
                                              const Color(0xFFB0BEC5).withOpacity(0.8),
                                              Colors.transparent,
                                            ],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFB0BEC5).withOpacity(0.5),
                                              blurRadius: 10,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 40),

                  // Название ORPHEUS
                  AnimatedBuilder(
                    animation: _revealController,
                    builder: (context, child) {
                      return SlideTransition(
                        position: _titleSlide,
                        child: Opacity(
                          opacity: _titleOpacity.value,
                          child: ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [
                                const Color(0xFFEEEEEE),
                                const Color(0xFFB0BEC5),
                                const Color(0xFFEEEEEE),
                              ],
                              stops: [
                                0.0,
                                0.5 + 0.5 * sin(_glowController.value * pi),
                                1.0,
                              ],
                            ).createShader(bounds),
                            child: const Text(
                              "ORPHEUS",
                              style: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 8.0,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Подзаголовок
                  AnimatedBuilder(
                    animation: _revealController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _subtitleOpacity.value,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildAnimatedDot(0),
                            const SizedBox(width: 8),
                            const Text(
                              "SECURE COMMUNICATION",
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 4.0,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildAnimatedDot(0.5),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 80),

                  // Кнопки
                  AnimatedBuilder(
                    animation: Listenable.merge([_revealController, _pulseController, _glowController]),
                    builder: (context, child) {
                      return SlideTransition(
                        position: _buttonsSlide,
                        child: Opacity(
                          opacity: _buttonsOpacity.value,
                          child: Column(
                            children: [
                              // Кнопка создания аккаунта с glow
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFB0BEC5).withOpacity(0.2 + 0.15 * _pulseController.value),
                                      blurRadius: 20 + 10 * _pulseController.value,
                                      spreadRadius: -2,
                                    ),
                                  ],
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 60,
                                  child: ElevatedButton(
                                    onPressed: _createNewAccount,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFCFD8DC),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_circle_outline,
                                          color: Colors.black.withOpacity(0.8),
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          "СОЗДАТЬ АККАУНТ",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            letterSpacing: 1.5,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Кнопка восстановления
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: OutlinedButton(
                                  onPressed: _showImportDialog,
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: Colors.grey.withOpacity(0.3 + 0.2 * _glowController.value),
                                      width: 1,
                                    ),
                                    foregroundColor: Colors.white70,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.key, size: 18, color: Colors.grey.shade500),
                                      const SizedBox(width: 10),
                                      const Text(
                                        "ВОССТАНОВИТЬ ИЗ КЛЮЧА",
                                        style: TextStyle(letterSpacing: 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Индикатор версии внизу
                  AnimatedBuilder(
                    animation: _revealController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _buttonsOpacity.value * 0.5,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6AD394).withOpacity(0.5 + 0.5 * _glowController.value),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "END-TO-END ENCRYPTED",
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 2,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAnimatedDot(double phaseOffset) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final phase = (_glowController.value + phaseOffset) % 1.0;
        return Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFB0BEC5).withOpacity(0.3 + 0.4 * phase),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB0BEC5).withOpacity(0.3 * phase),
                blurRadius: 4,
              ),
            ],
          ),
        );
      },
    );
  }
}

// Частицы на фоне приветственного экрана
class _WelcomeParticlesPainter extends CustomPainter {
  final double animationValue;
  _WelcomeParticlesPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final random = Random(42); // Фиксированный seed для стабильности
    
    for (int i = 0; i < 50; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.3 + random.nextDouble() * 0.7;
      final particleSize = 1.0 + random.nextDouble() * 2;
      
      // Движение вверх с wrap-around
      final y = (baseY - animationValue * size.height * speed) % size.height;
      
      // Легкое колебание по X
      final x = baseX + sin(animationValue * 2 * pi + i) * 20;
      
      // Пульсация прозрачности
      final opacity = 0.1 + 0.15 * sin(animationValue * 2 * pi + i * 0.5);
      
      canvas.drawCircle(
        Offset(x, y),
        particleSize,
        paint..color = const Color(0xFFB0BEC5).withOpacity(opacity.clamp(0.05, 0.3)),
      );
    }
    
    // Добавляем несколько более ярких частиц
    for (int i = 0; i < 8; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.2 + random.nextDouble() * 0.3;
      
      final y = (baseY - animationValue * size.height * speed) % size.height;
      final x = baseX + sin(animationValue * pi + i * 0.7) * 30;
      
      final opacity = 0.3 + 0.3 * sin(animationValue * 3 * pi + i);
      
      // Glow эффект
      canvas.drawCircle(
        Offset(x, y),
        6,
        paint..color = const Color(0xFFB0BEC5).withOpacity(opacity.clamp(0.0, 0.15)),
      );
      canvas.drawCircle(
        Offset(x, y),
        2,
        paint..color = const Color(0xFFB0BEC5).withOpacity(opacity.clamp(0.1, 0.5)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
