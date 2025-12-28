#!/usr/bin/env dart
// Утилита для красивого отчета по тестам
// Использование: dart tools/test_reporter.dart

import 'dart:io';
import 'dart:convert';
import 'dart:async';

void main(List<String> args) async {
  print('Запуск тестов Flutter...\n');
  
  // Запускаем тесты через shell
  final process = await Process.start(
    Platform.isWindows ? 'cmd' : 'sh',
    Platform.isWindows 
        ? ['/c', 'flutter', 'test', '--no-pub']
        : ['-c', 'flutter test --no-pub'],
    mode: ProcessStartMode.normal,
  );
  
  final output = StringBuffer();
  final errorOutput = StringBuffer();
  
  // Собираем вывод, но не показываем мусорные print'ы
  process.stdout.transform(utf8.decoder).listen((data) {
    // Не показываем прогресс тестов - только финальный отчет
    output.write(data);
  });
  
  process.stderr.transform(utf8.decoder).listen((data) {
    // Показываем только ошибки компиляции/запуска
    if (data.contains(RegExp(r'Error|Exception|Failed', caseSensitive: false))) {
      stderr.write(data);
    }
    errorOutput.write(data);
  });
  
  final exitCode = await process.exitCode;
  final fullOutput = output.toString() + errorOutput.toString();
  
  // Парсим результаты - ищем последнюю строку с "+N" (количество успешных тестов)
  int passed = 0;
  int failed = 0;
  
  // Ищем строку "All tests passed!" или последнюю строку с "+N"
  final allPassedMatch = RegExp(r'All tests passed!').firstMatch(fullOutput);
  if (allPassedMatch != null) {
    // Ищем последнюю строку с "+N" перед "All tests passed!"
    final lastTestMatch = RegExp(r'\+\d+').allMatches(fullOutput).lastOrNull;
    if (lastTestMatch != null) {
      passed = int.parse(lastTestMatch.group(0)!.substring(1));
    }
  } else {
    // Ищем строки с "+N -M" (успешные и проваленные)
    final summaryMatch = RegExp(r'\+(\d+)\s+-(\d+)').firstMatch(fullOutput);
    if (summaryMatch != null) {
      passed = int.parse(summaryMatch.group(1)!);
      failed = int.parse(summaryMatch.group(2)!);
    } else {
      // Пытаемся найти последнюю строку с "+N"
      final lastTestMatch = RegExp(r'\+\d+').allMatches(fullOutput).lastOrNull;
      if (lastTestMatch != null) {
        passed = int.parse(lastTestMatch.group(0)!.substring(1));
      }
    }
  }
  
  final total = passed + failed;
  
  // Парсим тесты по категориям
  final categories = <String, Category>{};
  final lines = fullOutput.split('\n');
  
  for (final line in lines) {
    // Ищем строки формата: "00:02 +49 -9: path: Group Name Test Name [E]"
    final testMatch = RegExp(r':\s*([^:]+?)\s*(\[E\])?$').firstMatch(line);
    if (testMatch != null) {
      final fullTest = testMatch.group(1)!.trim();
      final isFailed = testMatch.group(2) == '[E]';
      
      // Определяем категорию
      String category = 'ОБЩЕЕ';
      String testName = fullTest;
      
      // Пытаемся извлечь группу и название
      final groupMatch = RegExp(r'^(.+?):\s*(.+)$').firstMatch(fullTest);
      if (groupMatch != null) {
        final groupName = groupMatch.group(1)!.trim();
        testName = groupMatch.group(2)!.trim();
        
        // Определяем категорию по группе (приоритет - точные совпадения)
        if (groupName.contains('ЗВОНКИ') || groupName.contains('WebRTC') || 
            groupName.contains('webrtc') || groupName.contains('call') || 
            groupName.contains('Call') || groupName.contains('звонок')) {
          category = 'ЗВОНКИ';
        } else if (groupName.contains('ЧАТ') || groupName.contains('chat') || 
                   groupName.contains('Chat') || groupName.contains('message') || 
                   groupName.contains('Message') || groupName.contains('сообщени')) {
          category = 'ЧАТ';
        } else if (groupName.contains('СЕТЬ') || groupName.contains('websocket') || 
                   groupName.contains('WebSocket') || groupName.contains('сеть')) {
          category = 'СЕТЬ';
        } else if (groupName.contains('БЕЗОПАСНОСТЬ') || groupName.contains('auth') || 
                   groupName.contains('Auth') || groupName.contains('PIN') || 
                   groupName.contains('pin') || groupName.contains('security') || 
                   groupName.contains('Security') || groupName.contains('безопасн')) {
          category = 'БЕЗОПАСНОСТЬ';
        } else if (groupName.contains('notification') || groupName.contains('Notification') || 
                   groupName.contains('УВЕДОМЛЕНИЯ') || groupName.contains('уведомл')) {
          category = 'УВЕДОМЛЕНИЯ';
        } else if (groupName.contains('widget') || groupName.contains('screen') || 
                   groupName.contains('Screen') || groupName.contains('UI')) {
          category = 'UI';
        }
      } else {
        // Определяем по названию теста
        if (fullTest.contains('WebRTC') || fullTest.contains('webrtc') || 
            fullTest.contains('call') || fullTest.contains('Call') || 
            fullTest.contains('звонок')) {
          category = 'ЗВОНКИ';
        } else if (fullTest.contains('chat') || fullTest.contains('Chat') || 
                   fullTest.contains('message') || fullTest.contains('Message') || 
                   fullTest.contains('сообщени')) {
          category = 'ЧАТ';
        } else if (fullTest.contains('websocket') || fullTest.contains('WebSocket') || 
                   fullTest.contains('сеть')) {
          category = 'СЕТЬ';
        } else if (fullTest.contains('auth') || fullTest.contains('Auth') || 
                   fullTest.contains('PIN') || fullTest.contains('pin') || 
                   fullTest.contains('security') || fullTest.contains('Security') || 
                   fullTest.contains('безопасн')) {
          category = 'БЕЗОПАСНОСТЬ';
        } else if (fullTest.contains('notification') || fullTest.contains('уведомл')) {
          category = 'УВЕДОМЛЕНИЯ';
        }
      }
      
      categories.putIfAbsent(category, () => Category());
      if (isFailed) {
        categories[category]!.failed.add(testName);
      } else {
        categories[category]!.passed.add(testName);
      }
    }
  }
  
  // Выводим отчет
  print('\n');
  print('═══════════════════════════════════════════════════════════');
  print('                    ОТЧЕТ ПО ТЕСТАМ');
  print('═══════════════════════════════════════════════════════════');
  print('Дата: ${DateTime.now().toString().substring(0, 19)}');
  print('Всего: $total | Успешно: $passed | Провалено: $failed');
  print('');
  
  // Порядок категорий
  final categoryOrder = ['ЗВОНКИ', 'ЧАТ', 'СЕТЬ', 'БЕЗОПАСНОСТЬ', 'УВЕДОМЛЕНИЯ', 'UI', 'ОБЩЕЕ'];
  
  for (final catName in categoryOrder) {
    final cat = categories[catName];
    if (cat != null && (cat.passed.isNotEmpty || cat.failed.isNotEmpty)) {
      final totalInCat = cat.passed.length + cat.failed.length;
      final status = cat.failed.isEmpty ? 'OK' : 'FAIL';
      print('$catName: $status (${cat.passed.length}/$totalInCat)');
      
      // Показываем только ключевые тесты (первые 3 успешных, все проваленные)
      var shown = 0;
      for (final test in cat.passed) {
        if (shown < 3) {
          // Упрощаем название - убираем префиксы групп
          String shortName = test;
          if (shortName.contains(': ')) {
            final parts = shortName.split(': ');
            if (parts.length > 1) {
              shortName = parts.last;
            }
          }
          if (shortName.length > 60) {
            shortName = '${shortName.substring(0, 57)}...';
          }
          print('  [OK] $shortName');
          shown++;
        }
      }
      if (cat.passed.length > 3) {
        print('  ... и еще ${cat.passed.length - 3} успешных тестов');
      }
      
      // Показываем все проваленные
      for (final test in cat.failed) {
        String shortName = test;
        if (shortName.contains(': ')) {
          final parts = shortName.split(': ');
          if (parts.length > 1) {
            shortName = parts.last;
          }
        }
        if (shortName.length > 60) {
          shortName = '${shortName.substring(0, 57)}...';
        }
        print('  [FAIL] $shortName');
      }
      
      print('');
    }
  }
  
  // Остальные категории
  for (final entry in categories.entries) {
    if (!categoryOrder.contains(entry.key)) {
      final cat = entry.value;
      if (cat.passed.isNotEmpty || cat.failed.isNotEmpty) {
        final totalInCat = cat.passed.length + cat.failed.length;
        final status = cat.failed.isEmpty ? 'OK' : 'FAIL';
        print('${entry.key}: $status (${cat.passed.length}/$totalInCat)');
        
        var shown = 0;
        for (final test in cat.passed) {
          if (shown < 2) {
            String shortName = test;
            if (shortName.contains(': ')) {
              final parts = shortName.split(': ');
              if (parts.length > 1) {
                shortName = parts.last;
              }
            }
            if (shortName.length > 60) {
              shortName = '${shortName.substring(0, 57)}...';
            }
            print('  [OK] $shortName');
            shown++;
          }
        }
        if (cat.passed.length > 2) {
          print('  ... и еще ${cat.passed.length - 2} успешных тестов');
        }
        
        for (final test in cat.failed) {
          String shortName = test;
          if (shortName.contains(': ')) {
            final parts = shortName.split(': ');
            if (parts.length > 1) {
              shortName = parts.last;
            }
          }
          if (shortName.length > 60) {
            shortName = '${shortName.substring(0, 57)}...';
          }
          print('  [FAIL] $shortName');
        }
        
        print('');
      }
    }
  }
  
  print('═══════════════════════════════════════════════════════════');
  
  exit(exitCode);
}

class Category {
  final List<String> passed = [];
  final List<String> failed = [];
}

