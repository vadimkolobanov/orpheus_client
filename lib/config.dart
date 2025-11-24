// lib/config.dart

class AppConfig {
  // Текущая отображаемая версия
  static const String appVersion = "v0.5-Alpha-Hotfix-2";

  // IP сервера (Для эмулятора: 10.0.2.2, Для реального устройства: твой локальный IP, например 192.168.1.X)
  static const String serverIp = 'vadimkolobanov-orpheus-d95e.twc1.net';
  //static const String serverIp = '10.0.2.2:8000';

  // --- Готовые URL ---
  static String webSocketUrl(String publicKey) {
    final encodedPublicKey = Uri.encodeComponent(publicKey);
    return 'wss://$serverIp/ws/$encodedPublicKey';
  }

  static String httpUrl(String path) {
    return 'https://$serverIp$path'; // Внимание: для локальных тестов http, для продакшена https
  }

  // --- Данные для Чейнджлога внутри приложения ---
  static const List<Map<String, dynamic>> changelogData = [
    {
      'version': '0.7-Alpha',
      'date': '21.11.2025',
      'changes': [
        'DESIGN: Новый стиль "Dark Premium" (Черный/Серебро).',
        'SECURITY: Запрет скриншотов и записи экрана.',
        'SECURITY: Биометрическая защита (палец/лицо) для экспорта ключей.',
        'NEW: Активация лицензии промокодом.',
        'UX: Удобная визитка с ID и кнопкой "Поделиться".',
      ]
    },
    {
      'version': '0.6-Alpha',
      'date': '19.11.2025',
      'changes': [
        'NEW: Push-уведомления! Теперь вы узнаете о сообщениях, даже если приложение закрыто.',
        'UI: Счетчики непрочитанных сообщений в списке контактов.',
        'UI: Галочки статуса доставки в чате.',
        'Fix: Улучшена стабильность соединения (авто-реконнект).',
      ]
    },
    {
      'version': '0.5-Alpha-Hotfix-2',
      'date': '19.11.2025',
      'changes': [
        'Server: Исправлена критическая ошибка пересылки сообщений (sender_pubkey).',
        'Client: Убран лишний визуальный шум из заголовка чата.',
        'Client: Добавлен экран просмотра истории обновлений.',
      ]
    },
    {
      'version': '0.5-Alpha-Hotfix-1',
      'date': '19.11.2025',
      'changes': [
        'Client: Исправлена обработка ошибок подключения.',
        'Client: Добавлено детальное логирование событий сети.',
      ]
    },
    {
      'version': '0.5-Alpha',
      'date': 'Initial Release',
      'changes': [
        'Релиз базовой версии.',
        'Анонимные звонки (WebRTC) и чаты.',
        'Шифрование X25519/ChaCha20.',
        'Оплата лицензии через TRON.',
      ]
    },
  ];
}