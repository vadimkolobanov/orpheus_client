// Кастомный репортер для структурированного отчета по тестам
// Использование: flutter test --reporter json | dart test_reporter.dart

import 'dart:convert';
import 'dart:io';

void main() async {
  final input = await stdin.transform(utf8.decoder).join();
  
  // Маппинг тестов к функциональным областям
  final categoryMap = {
    'ЗВОНКИ': [
      'webrtc', 'call', 'CallScreen', 'CallSession', 'BackgroundCall',
      'IncomingCall', 'WebRTC', 'ICE', 'TURN', 'signaling'
    ],
    'ЧАТ': [
      'chat', 'ChatScreen', 'ChatSession', 'message', 'Message',
      'chat_time', 'day-separator'
    ],
    'БЕЗОПАСНОСТЬ': [
      'auth', 'AuthService', 'PIN', 'duress', 'wipe', 'lockout',
      'SecurityConfig', 'PanicWipe', 'LockScreen'
    ],
    'УВЕДОМЛЕНИЯ': [
      'notification', 'NotificationService', 'FCM', 'push'
    ],
    'КОНТАКТЫ': [
      'contact', 'Contact', 'ContactsScreen', 'QR', 'qr_scan'
    ],
    'БАЗА ДАННЫХ': [
      'database', 'DatabaseService', 'Database', 'CRUD'
    ],
    'КРИПТОГРАФИЯ': [
      'crypto', 'CryptoService', 'encrypt', 'decrypt'
    ],
    'СЕТЬ': [
      'websocket', 'WebSocket', 'presence', 'connection'
    ],
  };

  // Парсим JSON вывод flutter test
  try {
    final json = jsonDecode(input) as Map<String, dynamic>;
    final tests = json['tests'] as List<dynamic>? ?? [];
    
    final categories = <String, List<Map<String, dynamic>>>{};
    
    for (final test in tests) {
      final testMap = test as Map<String, dynamic>;
      final name = testMap['name'] as String? ?? '';
      final result = testMap['result'] as String? ?? 'success';
      
      // Определяем категорию
      String category = 'ДРУГОЕ';
      for (final entry in categoryMap.entries) {
        if (entry.value.any((keyword) => name.toLowerCase().contains(keyword.toLowerCase()))) {
          category = entry.key;
          break;
        }
      }
      
      categories.putIfAbsent(category, () => []).add({
        'name': _cleanTestName(name),
        'result': result,
      });
    }
    
    // Выводим структурированный отчет
    print('\n╔═══════════════════════════════════════════════════════════════╗');
    print('║           ОТЧЕТ ПО ТЕСТАМ ORPHEUS CLIENT                     ║');
    print('╚═══════════════════════════════════════════════════════════════╝\n');
    
    for (final entry in categories.entries) {
      final category = entry.key;
      final tests = entry.value;
      final passed = tests.where((t) => t['result'] == 'success').length;
      final failed = tests.length - passed;
      
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📦 $category (${tests.length} тестов, ✅ $passed, ❌ $failed)');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      for (final test in tests) {
        final icon = test['result'] == 'success' ? '✅' : '❌';
        print('  $icon ${test['name']}');
      }
      print('');
    }
  } catch (e) {
    // Если не JSON, выводим как есть
    print(input);
  }
}

String _cleanTestName(String name) {
  // Убираем технические детали, оставляем суть
  var clean = name;
  
  // Убираем путь к файлу
  if (clean.contains(':')) {
    clean = clean.split(':').last.trim();
  }
  
  // Убираем скобки с параметрами
  clean = clean.replaceAll(RegExp(r'\([^)]*\)'), '');
  
  // Убираем "test", "Test", "TEST"
  clean = clean.replaceAll(RegExp(r'\btest\b', caseSensitive: false), '');
  
  return clean.trim();
}

