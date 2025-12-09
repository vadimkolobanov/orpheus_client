import 'package:flutter/material.dart';
import 'package:orpheus_project/contacts_screen.dart';
import 'package:orpheus_project/screens/settings_screen.dart';
import 'package:orpheus_project/screens/status_screen.dart';
import 'package:orpheus_project/services/device_settings_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1; // По умолчанию открываем Контакты (индекс 1)
  
  @override
  void initState() {
    super.initState();
    // Проверяем настройки устройства при первом запуске
    _checkDeviceSettings();
  }
  
  /// Проверка настроек устройства и показ диалога при необходимости
  Future<void> _checkDeviceSettings() async {
    // Небольшая задержка, чтобы экран успел отрисоваться
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;
    
    // Проверяем, не скрыл ли пользователь этот диалог
    final isDismissed = await DeviceSettingsService.isSetupDialogDismissed();
    if (isDismissed) return;
    
    final needsSetup = await DeviceSettingsService.needsManualSetup();
    if (needsSetup && mounted) {
      DeviceSettingsService.showSetupDialog(context);
    }
  }

  // Список экранов для табов
  final List<Widget> _screens = [
    const StatusScreen(),
    const ContactsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Используем IndexedStack, чтобы сохранять состояние экранов при переключении
      // (например, чтобы список контактов не перезагружался каждый раз)
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: Colors.black,
          indicatorColor: const Color(0xFFB0BEC5), // Серебро
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.monitor_heart_outlined),
              selectedIcon: Icon(Icons.monitor_heart, color: Colors.black),
              label: 'Система',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble, color: Colors.black),
              label: 'Контакты',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings, color: Colors.black),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}