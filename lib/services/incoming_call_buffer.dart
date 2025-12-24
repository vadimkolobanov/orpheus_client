import 'package:flutter/foundation.dart';

/// Буфер входящих сигналов звонка (в первую очередь ICE candidates),
/// чтобы закрыть race condition между приходом кандидатов и готовностью `CallScreen`.
///
/// Важно: буфер живёт в памяти. При завершении звонка/отмене — очищайте по ключу отправителя.
class IncomingCallBuffer {
  IncomingCallBuffer._();

  static final IncomingCallBuffer instance = IncomingCallBuffer._();

  final Map<String, List<Map<String, dynamic>>> _bySender = {};

  /// Гарантирует, что для отправителя есть список.
  /// Не очищает существующие данные (кандидаты, пришедшие до offer, сохраняются).
  void ensure(String senderPublicKey) {
    _bySender.putIfAbsent(senderPublicKey, () => <Map<String, dynamic>>[]);
  }

  /// Добавить входящий сигнал в буфер.
  void add(String senderPublicKey, Map<String, dynamic> messageData) {
    ensure(senderPublicKey);
    _bySender[senderPublicKey]!.add(messageData);
  }

  /// Забрать и очистить все буферизованные сигналы для отправителя.
  List<Map<String, dynamic>> takeAll(String senderPublicKey) {
    final buffer = _bySender.remove(senderPublicKey);
    return buffer ?? <Map<String, dynamic>>[];
  }

  /// Полностью очистить буфер для отправителя (без возврата данных).
  void clear(String senderPublicKey) {
    _bySender.remove(senderPublicKey);
  }

  @visibleForTesting
  void clearAll() {
    _bySender.clear();
  }

  @visibleForTesting
  int sizeFor(String senderPublicKey) => _bySender[senderPublicKey]?.length ?? 0;
}


