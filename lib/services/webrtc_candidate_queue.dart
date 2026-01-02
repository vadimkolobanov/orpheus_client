import 'dart:async';

/// Чистая (без плагинов) логика очереди remote ICE кандидатов.
///
/// Контракт:
/// - Пока remote SDP не установлен, кандидаты НЕ применяются, а копятся.
/// - После установки remote SDP очередь дренится FIFO, и все новые кандидаты применяются сразу.
/// - Ошибки применения отдельных кандидатов не должны ломать дрен (best-effort).
/// - `reset()` очищает очередь и возвращает в состояние "remote SDP не установлен".
class WebRtcRemoteCandidateQueue {
  final List<Map<String, dynamic>> _queued = <Map<String, dynamic>>[];
  bool _remoteDescriptionSet = false;

  bool get remoteDescriptionSet => _remoteDescriptionSet;
  int get queuedCount => _queued.length;

  void reset() {
    _remoteDescriptionSet = false;
    _queued.clear();
  }

  /// Добавить кандидата.
  ///
  /// - Если remote SDP уже установлен — вызывается `applyNow`.
  /// - Иначе кандидат добавляется в очередь.
  Future<void> addCandidate(
    Map<String, dynamic> candidateData, {
    required Future<void> Function(Map<String, dynamic> candidateData) applyNow,
  }) async {
    if (_remoteDescriptionSet) {
      await applyNow(candidateData);
      return;
    }
    _queued.add(candidateData);
  }

  /// Пометить remote SDP как установленный и применить всё накопленное FIFO.
  Future<void> onRemoteDescriptionSet({
    required Future<void> Function(Map<String, dynamic> candidateData) applyNow,
  }) async {
    _remoteDescriptionSet = true;

    // Дреним FIFO, но устойчиво к ошибкам отдельных кандидатов.
    final snapshot = List<Map<String, dynamic>>.from(_queued);
    _queued.clear();

    for (final c in snapshot) {
      try {
        await applyNow(c);
      } catch (_) {
        // best-effort: не прерываем дрен
      }
    }
  }
}






