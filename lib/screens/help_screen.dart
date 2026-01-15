import 'package:flutter/material.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_card.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      safeArea: false,
      appBar: AppBar(title: const Text('Как пользоваться')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _Section(
              title: 'Быстрый старт',
              bullets: [
                'Ваш ID — это публичный ключ. Им делятся, чтобы вас добавили.',
                'Контакт работает «в обе стороны»: вы добавляете человека по его ID/QR, и он добавляет вас по вашему ID/QR.',
                'Чат и звонки идут по защищённому каналу, сообщения шифруются.',
              ],
            ),
            SizedBox(height: 12),
            _Section(
              title: 'Экспорт аккаунта (важно)',
              bullets: [
                'Профиль → Экспорт аккаунта показывает приватный ключ.',
                'Приватный ключ — это полный доступ к аккаунту. Не показывайте его никому.',
                'Потеряли приватный ключ и удалили приложение — восстановление невозможно.',
              ],
            ),
            SizedBox(height: 12),
            _Section(
              title: 'PIN‑код',
              bullets: [
                'Профиль → Безопасность → PIN. Если PIN не задан — вход открыт.',
                'Если PIN включён — приложение блокируется при сворачивании и при запуске.',
              ],
            ),
            SizedBox(height: 12),
            _Section(
              title: 'Код принуждения (Duress)',
              bullets: [
                'Это второй PIN. При вводе показывается «пустой профиль» (0 контактов/сообщений).',
                'Реальные данные не удаляются — они скрыты, пока вы в duress‑режиме.',
              ],
            ),
            SizedBox(height: 12),
            _Section(
              title: 'Код удаления (Panic wipe)',
              bullets: [
                'Это отдельный код для полного удаления данных.',
                'После ввода кода появится подтверждение: удерживайте кнопку 2 секунды.',
                'Сделано так, чтобы нельзя было стереть всё случайно.',
              ],
            ),
            SizedBox(height: 12),
            _Section(
              title: 'Auto‑wipe',
              bullets: [
                'Опция: удалить данные после N неверных попыток введения PIN.',
                'Включайте только если понимаете риск необратимой потери данных.',
              ],
            ),
            SizedBox(height: 12),
            _Section(
              title: 'Жест panic wipe',
              bullets: [
                'Опция (по умолчанию выключена): 3 быстрых ухода приложения в фон → wipe.',
                'Жест основан на событиях ухода приложения в фон и может срабатывать менее предсказуемо, чем код удаления.',
              ],
            ),
            SizedBox(height: 12),
            _Section(
              title: 'Регионы и контроль трафика',
              bullets: [
                'Экран «Система» показывает режим: «Стандартный» или «Усиленная защита».',
                'Если обнаружен регион с контролем трафика, приложение включает «усиленный» режим в системном мониторе.',
                'Если есть проблемы со связью — откройте «Система» и проверьте статус сети/режима.',
              ],
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      radius: AppRadii.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...bullets.map((b) => _Bullet(text: b)),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 6, color: AppColors.textTertiary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: t.bodyMedium?.copyWith(height: 1.35)),
          ),
        ],
      ),
    );
  }
}
