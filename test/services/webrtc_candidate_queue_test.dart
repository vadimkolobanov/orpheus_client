import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/webrtc_candidate_queue.dart';

void main() {
  group('WebRtcRemoteCandidateQueue (контракт очереди ICE до remote SDP)', () {
    test('по умолчанию remoteDescriptionSet=false и очередь пуста', () {
      final q = WebRtcRemoteCandidateQueue();
      expect(q.remoteDescriptionSet, isFalse);
      expect(q.queuedCount, equals(0));
    });

    test('до remote SDP: кандидаты копятся и не применяются', () async {
      final q = WebRtcRemoteCandidateQueue();
      final applied = <int>[];

      await q.addCandidate({'n': 1}, applyNow: (c) async => applied.add(c['n'] as int));
      await q.addCandidate({'n': 2}, applyNow: (c) async => applied.add(c['n'] as int));

      expect(q.remoteDescriptionSet, isFalse);
      expect(q.queuedCount, equals(2));
      expect(applied, isEmpty);
    });

    test('после remote SDP: очередь дренится FIFO и очищается', () async {
      final q = WebRtcRemoteCandidateQueue();
      final applied = <int>[];

      await q.addCandidate({'n': 1}, applyNow: (c) async => applied.add(c['n'] as int));
      await q.addCandidate({'n': 2}, applyNow: (c) async => applied.add(c['n'] as int));

      await q.onRemoteDescriptionSet(applyNow: (c) async => applied.add(c['n'] as int));

      expect(q.remoteDescriptionSet, isTrue);
      expect(q.queuedCount, equals(0));
      expect(applied, equals([1, 2]));
    });

    test('после remote SDP: новые кандидаты применяются сразу (без очереди)', () async {
      final q = WebRtcRemoteCandidateQueue();
      final applied = <int>[];

      await q.onRemoteDescriptionSet(applyNow: (_) async {});

      await q.addCandidate({'n': 3}, applyNow: (c) async => applied.add(c['n'] as int));
      expect(q.queuedCount, equals(0));
      expect(applied, equals([3]));
    });

    test('best-effort: ошибка применения одного кандидата не ломает дрен остальных', () async {
      final q = WebRtcRemoteCandidateQueue();
      final applied = <int>[];

      await q.addCandidate({'n': 1}, applyNow: (_) async {});
      await q.addCandidate({'n': 2}, applyNow: (_) async {});
      await q.addCandidate({'n': 3}, applyNow: (_) async {});

      await q.onRemoteDescriptionSet(applyNow: (c) async {
        final n = c['n'] as int;
        if (n == 2) throw StateError('boom');
        applied.add(n);
      });

      expect(applied, equals([1, 3]));
      expect(q.queuedCount, equals(0));
      expect(q.remoteDescriptionSet, isTrue);
    });

    test('reset очищает очередь и сбрасывает remoteDescriptionSet', () async {
      final q = WebRtcRemoteCandidateQueue();
      await q.addCandidate({'n': 1}, applyNow: (_) async {});
      await q.onRemoteDescriptionSet(applyNow: (_) async {});
      expect(q.remoteDescriptionSet, isTrue);

      q.reset();
      expect(q.remoteDescriptionSet, isFalse);
      expect(q.queuedCount, equals(0));
    });
  });
}




