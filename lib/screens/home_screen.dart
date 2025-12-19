import 'package:flutter/material.dart';
import 'package:orpheus_project/contacts_screen.dart';
import 'package:orpheus_project/screens/settings_screen.dart';
import 'package:orpheus_project/screens/status_screen.dart';
import 'package:orpheus_project/services/device_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static const String _betaDisclaimerDismissedKey = 'beta_disclaimer_dismissed_v1';

  int _currentIndex = 1; // По умолчанию открываем Контакты
  
  late AnimationController _glowController;
  late AnimationController _pulseController;
  late AnimationController _transitionController;
  
  // Для анимации смены экрана
  int _previousIndex = 1;
  
  @override
  void initState() {
    super.initState();
    
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeShowBetaDisclaimer();
      if (!mounted) return;
      await _checkDeviceSettings();
    });
  }
  
  @override
  void dispose() {
    _glowController.dispose();
    _pulseController.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  Future<bool> _isBetaDisclaimerDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_betaDisclaimerDismissedKey) ?? false;
  }

  Future<void> _setBetaDisclaimerDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_betaDisclaimerDismissedKey, true);
  }

  Future<void> _maybeShowBetaDisclaimer() async {
    // Небольшая пауза, чтобы не "рвать" первый кадр.
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    final dismissed = await _isBetaDisclaimerDismissed();
    if (dismissed || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Важно',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Вы используете версию приложения, проходящую тестирование.\n\n'
            'Возможны нестабильности и неоднозначное поведение в отдельных сценариях. '
            'Мы постепенно выявляем такие случаи и оперативно исправляем.\n\n'
            'Пожалуйста, не воспринимайте это как “идеальный” релиз.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.35),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6AD394),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              await _setBetaDisclaimerDismissed();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Я понял(а) и больше не показывать'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkDeviceSettings() async {
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;
    
    final isDismissed = await DeviceSettingsService.isSetupDialogDismissed();
    if (isDismissed) return;
    
    final needsSetup = await DeviceSettingsService.needsManualSetup();
    if (needsSetup && mounted) {
      DeviceSettingsService.showSetupDialog(context);
    }
  }

  final List<Widget> _screens = [
    const StatusScreen(),
    const ContactsScreen(),
    const SettingsScreen(),
  ];

  void _onTabSelected(int index) {
    if (index == _currentIndex) return;
    
    setState(() {
      _previousIndex = _currentIndex;
      _currentIndex = index;
    });
    
    _transitionController.reset();
    _transitionController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          // Определяем направление анимации
          final slideDirection = _currentIndex > _previousIndex ? 1.0 : -1.0;
          
          return SlideTransition(
            position: Tween<Offset>(
              begin: Offset(slideDirection * 0.1, 0),
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
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: _screens[_currentIndex],
        ),
      ),
      bottomNavigationBar: _buildAnimatedNavigationBar(),
    );
  }

  Widget _buildAnimatedNavigationBar() {
    return AnimatedBuilder(
      animation: Listenable.merge([_glowController, _pulseController]),
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF050505),
            border: Border(
              top: BorderSide(
                color: const Color(0xFFB0BEC5).withOpacity(0.1 + 0.05 * _glowController.value),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB0BEC5).withOpacity(0.05 * _glowController.value),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(
                    index: 0,
                    icon: Icons.monitor_heart_outlined,
                    activeIcon: Icons.monitor_heart,
                    label: 'Система',
                    accentColor: const Color(0xFF6AD394),
                  ),
                  _buildNavItem(
                    index: 1,
                    icon: Icons.chat_bubble_outline,
                    activeIcon: Icons.chat_bubble,
                    label: 'Контакты',
                    accentColor: const Color(0xFFB0BEC5),
                  ),
                  _buildNavItem(
                    index: 2,
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    label: 'Профиль',
                    accentColor: const Color(0xFFB0BEC5),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required Color accentColor,
  }) {
    final isSelected = _currentIndex == index;
    
    return GestureDetector(
      onTap: () => _onTabSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor.withOpacity(0.1 + 0.05 * _glowController.value)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: isSelected
                  ? Border.all(
                      color: accentColor.withOpacity(0.2 + 0.1 * _glowController.value),
                      width: 1,
                    )
                  : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accentColor.withOpacity(0.15 * _glowController.value),
                        blurRadius: 15,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Иконка с анимацией
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accentColor.withOpacity(0.2)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: accentColor.withOpacity(0.3 + 0.2 * _pulseController.value),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(
                        scale: animation,
                        child: child,
                      );
                    },
                    child: Icon(
                      isSelected ? activeIcon : icon,
                      key: ValueKey(isSelected),
                      color: isSelected
                          ? accentColor
                          : Colors.grey.shade600,
                      size: isSelected ? 24 : 22,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Лейбл
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    color: isSelected ? accentColor : Colors.grey.shade600,
                    fontSize: isSelected ? 11 : 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    letterSpacing: isSelected ? 0.5 : 0,
                  ),
                  child: Text(label),
                ),
                // Индикатор под активным табом
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: isSelected ? 20 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accentColor.withOpacity(0.8 + 0.2 * _pulseController.value)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: accentColor.withOpacity(0.5),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
