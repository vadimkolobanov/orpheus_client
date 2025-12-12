// lib/screens/help_screen.dart
// Простая “инструкция пользователя” внутри приложения

import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('КАК ПОЛЬЗОВАТЬСЯ', style: TextStyle(letterSpacing: 1)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _SectionTitle('Быстрый старт'),
            _Bullet('Ваш ID — это ваш публичный ключ. Им делятся, чтобы вас добавили.'),
            _Bullet('Добавление контакта работает только в обе стороны: вы добавляете человека по его ID/QR, и он добавляет вас по вашему ID/QR. Пока это не сделано у обоих — связи может не быть.'),
            _Bullet('Чат и звонки работают по защищённому каналу, сообщения шифруются.'),
            SizedBox(height: 18),

            _SectionTitle('Экспорт аккаунта (важно)'),
            _Bullet('Профиль → Экспорт аккаунта показывает приватный ключ.'),
            _Bullet('Приватный ключ — это полный доступ к аккаунту. Не показывайте его никому.'),
            _Bullet('Потеряли приватный ключ и удалили приложение — восстановление невозможно.'),
            SizedBox(height: 18),

            _SectionTitle('PIN-код'),
            _Bullet('Профиль → Безопасность → PIN. Если PIN не задан — вход открыт.'),
            _Bullet('Если PIN включен — приложение блокируется при сворачивании и при запуске.'),
            SizedBox(height: 18),

            _SectionTitle('Код принуждения (Duress)'),
            _Bullet('Это второй PIN. При вводе показывается “пустой профиль” (0 контактов/сообщений).'),
            _Bullet('Реальные данные не удаляются — они скрыты, пока вы в duress режиме.'),
            SizedBox(height: 18),

            _SectionTitle('Код удаления (Panic wipe code)'),
            _Bullet('Это отдельный код для полного удаления данных.'),
            _Bullet('После ввода кода появится подтверждение: удерживайте кнопку 2 секунды.'),
            _Bullet('Сделано так, чтобы нельзя было стереть всё случайно.'),
            SizedBox(height: 18),

            _SectionTitle('Auto-wipe'),
            _Bullet('Опция: удалить данные после N неверных попыток PIN.'),
            _Bullet('Включайте только если понимаете риск необратимой потери данных.'),
            SizedBox(height: 18),

            _SectionTitle('Жест panic wipe'),
            _Bullet('Опция (по умолчанию выключена): 3 быстрых ухода приложения в фон → wipe.'),
            _Bullet('Важно: жест основан на событиях ухода приложения в фон и может срабатывать менее предсказуемо, чем код удаления.'),
            SizedBox(height: 18),

            _SectionTitle('Регионы и контроль трафика'),
            _Bullet('Экран “Система” показывает страну (определение по IP) и режим: “Стандартный” или “Усиленная защита”.'),
            _Bullet('Если обнаружен регион с контролем трафика, приложение показывает предупреждение и включает “усиленный” режим в системном мониторе.'),
            _Bullet('Если есть проблемы со связью — откройте “Система” и проверьте статус сети/режима.'),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: Color(0xFFB0BEC5)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey.shade300, height: 1.35, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}


