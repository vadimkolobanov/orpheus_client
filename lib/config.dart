// lib/config.dart

class AppConfig {
  static const String appVersion = "v1.0.0";
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