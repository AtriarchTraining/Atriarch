import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/services/event_batcher.dart';

void main() {
  group('EventBatcher', () {
    test('buffers events until flush interval elapses', () async {
      final flushed = <List<SessionEvent>>[];
      final batcher = EventBatcher(
        onFlush: (events) async => flushed.add(events),
        flushInterval: const Duration(milliseconds: 50),
      );

      batcher.start();
      batcher.add(SessionEvent(type: EventType.targetActivated, targetId: 1));
      batcher.add(SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1));

      expect(flushed, isEmpty);

      await Future.delayed(const Duration(milliseconds: 80));

      expect(flushed, hasLength(1));
      expect(flushed.first, hasLength(2));

      await batcher.stop();
    });

    test('stop() performs final flush of buffered events', () async {
      final flushed = <List<SessionEvent>>[];
      final batcher = EventBatcher(
        onFlush: (events) async => flushed.add(events),
        flushInterval: const Duration(seconds: 10),
      );
      batcher.start();
      batcher.add(SessionEvent(type: EventType.targetActivated, targetId: 1));
      await batcher.stop();
      expect(flushed, hasLength(1));
      expect(flushed.first, hasLength(1));
    });

    test('does not flush empty buffers', () async {
      final flushed = <List<SessionEvent>>[];
      final batcher = EventBatcher(
        onFlush: (events) async => flushed.add(events),
        flushInterval: const Duration(milliseconds: 30),
      );
      batcher.start();
      await Future.delayed(const Duration(milliseconds: 70));
      await batcher.stop();
      expect(flushed, isEmpty);
    });

    test('add() before start() is ignored (guard against leaks)', () async {
      final flushed = <List<SessionEvent>>[];
      final batcher = EventBatcher(
        onFlush: (events) async => flushed.add(events),
        flushInterval: const Duration(milliseconds: 10),
      );
      batcher.add(SessionEvent(type: EventType.targetActivated, targetId: 1));
      batcher.start();
      await Future.delayed(const Duration(milliseconds: 30));
      await batcher.stop();
      expect(flushed, isEmpty);
    });
  });
}
