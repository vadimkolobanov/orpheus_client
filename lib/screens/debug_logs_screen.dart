// lib/screens/debug_logs_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:share_plus/share_plus.dart';

class DebugLogsScreen extends StatefulWidget {
  const DebugLogsScreen({super.key});

  @override
  State<DebugLogsScreen> createState() => _DebugLogsScreenState();
}

class _DebugLogsScreenState extends State<DebugLogsScreen> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _subscription;
  
  // Фильтр по тегам
  String? _selectedTag;
  bool _autoScroll = true;
  
  // Доступные теги
  final Set<String> _availableTags = {};

  @override
  void initState() {
    super.initState();
    _updateTags();
    
    // Подписка на обновления логов
    _subscription = DebugLogger.onUpdate.listen((_) {
      if (mounted) {
        setState(() {
          _updateTags();
        });
        
        if (_autoScroll && _scrollController.hasClients) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      }
    });
  }

  void _updateTags() {
    _availableTags.clear();
    for (final log in DebugLogger.logs) {
      _availableTags.add(log.tag);
    }
  }

  List<LogEntry> get _filteredLogs {
    if (_selectedTag == null) {
      return DebugLogger.logs;
    }
    return DebugLogger.logs.where((e) => e.tag == _selectedTag).toList();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.success:
        return Colors.green;
    }
  }

  Color _getTagColor(String tag) {
    final hash = tag.hashCode;
    final colors = [
      Colors.purple,
      Colors.teal,
      Colors.amber,
      Colors.cyan,
      Colors.pink,
      Colors.lime,
      Colors.indigo,
      Colors.deepOrange,
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filteredLogs;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text(
          'DEBUG LOGS',
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        backgroundColor: const Color(0xFF1A0000),
        foregroundColor: Colors.red,
        actions: [
          // Кнопка автоскролла
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
              color: _autoScroll ? Colors.green : Colors.grey,
            ),
            tooltip: 'Автопрокрутка',
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
            },
          ),
          // Копировать логи
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Копировать',
            onPressed: () {
              final text = DebugLogger.exportToText();
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Логи скопированы'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
          // Поделиться логами
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Поделиться',
            onPressed: () {
              final text = DebugLogger.exportToText();
              Share.share(text, subject: 'Orpheus Debug Logs');
            },
          ),
          // Очистить логи
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Очистить',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E1E),
                  title: const Text('Очистить логи?', style: TextStyle(color: Colors.white)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена'),
                    ),
                    TextButton(
                      onPressed: () {
                        DebugLogger.clear();
                        Navigator.pop(context);
                      },
                      child: const Text('Очистить', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Панель фильтров
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: const Color(0xFF1A1A1A),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Кнопка "Все"
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FilterChip(
                      label: Text('ВСЕ (${DebugLogger.logs.length})'),
                      selected: _selectedTag == null,
                      selectedColor: Colors.white24,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color: _selectedTag == null ? Colors.white : Colors.grey,
                        fontSize: 11,
                      ),
                      onSelected: (_) {
                        setState(() => _selectedTag = null);
                      },
                    ),
                  ),
                  // Теги
                  ..._availableTags.map((tag) {
                    final count = DebugLogger.logs.where((e) => e.tag == tag).length;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FilterChip(
                        label: Text('$tag ($count)'),
                        selected: _selectedTag == tag,
                        selectedColor: _getTagColor(tag).withOpacity(0.3),
                        checkmarkColor: _getTagColor(tag),
                        labelStyle: TextStyle(
                          color: _selectedTag == tag ? _getTagColor(tag) : Colors.grey,
                          fontSize: 11,
                        ),
                        onSelected: (_) {
                          setState(() => _selectedTag = _selectedTag == tag ? null : tag);
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          
          // Статус-бар
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF0A0A0A),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 8, color: Colors.green),
                const SizedBox(width: 6),
                Text(
                  'Записей: ${logs.length}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Text(
                  'Real-time logging',
                  style: TextStyle(
                    color: Colors.green.withOpacity(0.7),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          
          // Список логов
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      'Нет логов',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final entry = logs[index];
                      return _buildLogEntry(entry, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(LogEntry entry, int index) {
    final levelColor = _getLevelColor(entry.level);
    final tagColor = _getTagColor(entry.tag);
    
    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: entry.toFormattedString()));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Запись скопирована'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: index % 2 == 0 ? Colors.transparent : const Color(0xFF0A0A0A),
          border: Border(
            left: BorderSide(
              color: levelColor.withOpacity(0.5),
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Время
            SizedBox(
              width: 85,
              child: Text(
                entry.timeString,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // Тег
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: tagColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.tag,
                style: TextStyle(
                  color: tagColor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Сообщение
            Expanded(
              child: Text(
                entry.message,
                style: TextStyle(
                  color: levelColor == Colors.red ? Colors.red : Colors.white,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

