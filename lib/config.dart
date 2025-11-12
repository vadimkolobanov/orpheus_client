// lib/config.dart

class AppConfig {
  // --- ГЛАВНАЯ НАСТРОЙКА ---
  // Меняйте этот адрес, когда перенесете сервер на хостинг.
  // Для Android-эмулятора: '10.0.2.2'
  // Для iOS-симулятора: 'localhost'
  // Для реального устройства в той же Wi-Fi сети: IP-адрес вашего компьютера (например, '192.168.1.5')
  static const String serverIp = 'vadimkolobanov-orpheus-d95e.twc1.net';


  // --- Готовые URL, которые будут использоваться в приложении ---

  // URL для WebSocket соединений
  static String webSocketUrl(String publicKey) {
    final encodedPublicKey = Uri.encodeComponent(publicKey);
    return 'ws://$serverIp/ws/$encodedPublicKey';
  }

  // URL для HTTP запросов (например, для будущего получения контактов)
  static String httpUrl(String path) {
    return 'https://$serverIp$path';
  }
}