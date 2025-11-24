// lib/welcome_screen.dart

import 'package:flutter/material.dart';
import 'package:orpheus_project/main.dart';

class WelcomeScreen extends StatefulWidget {
  final VoidCallback onAuthComplete;
  const WelcomeScreen({super.key, required this.onAuthComplete});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _importController = TextEditingController();

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
      body: Container(
        width: double.infinity, // Растягиваем на всю ширину
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF151515), Color(0xFF000000)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // ВЫРАВНИВАНИЕ ПО ЦЕНТРУ
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- БЛОК ЛОГОТИПА ---
              Image.asset(
                  'assets/images/logo.png',
                  height: 160, // Чуть уменьшил, чтобы было аккуратнее
                  errorBuilder: (c,e,s) {
                    return const Icon(Icons.shield, size: 120, color: Color(0xFFB0BEC5));
                  }
              ),

              const SizedBox(height: 32),

              const Text(
                "ORPHEUS",
                style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 5.0,
                    color: Color(0xFFEEEEEE)
                ),
              ),
              const Text(
                "SECURE COMMUNICATION",
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 3.0,
                    color: Colors.grey
                ),
              ),

              // --- ВМЕСТО Spacer() ФИКСИРОВАННЫЙ ОТСТУП ---
              const SizedBox(height: 80),

              // --- БЛОК КНОПОК ---
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _createNewAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCFD8DC),
                    elevation: 8,
                    shadowColor: Colors.white24,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                      "СОЗДАТЬ АККАУНТ",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: _showImportDialog,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.grey, width: 1),
                    foregroundColor: Colors.white70,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("ВОССТАНОВИТЬ ИЗ КЛЮЧА"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}