// Gate 2 #20 — Walk-the-Range sequencing + cancel + phase gate.

import 'package:atriarch/models/target_unit.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('walkTheRange fires IDENT for each online target in ascending id order',
      () {
    fakeAsync((async) {
      final state = AppState.forTest();
      // Seed targets out of order — walk sorts ascending.
      state.targets
        ..add(TargetUnit(id: 3, isOnline: true))
        ..add(TargetUnit(id: 1, isOnline: true))
        ..add(TargetUnit(id: 2, isOnline: true));

      state.walkTheRange();
      async.flushMicrotasks();
      expect(state.walkTheRangeActive, isTrue);
      // First IDENT fires immediately.
      expect(state.debugSentIdentifyIds, equals([1]));

      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(state.debugSentIdentifyIds, equals([1, 2]));

      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(state.debugSentIdentifyIds, equals([1, 2, 3]));

      // After the final iteration the walk completes.
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(state.walkTheRangeActive, isFalse);
      state.dispose();
    });
  });

  test('cancelWalkTheRange stops at the next boundary', () {
    fakeAsync((async) {
      final state = AppState.forTest();
      state.targets
        ..add(TargetUnit(id: 1, isOnline: true))
        ..add(TargetUnit(id: 2, isOnline: true))
        ..add(TargetUnit(id: 3, isOnline: true));

      state.walkTheRange();
      async.flushMicrotasks();
      expect(state.debugSentIdentifyIds, equals([1]));

      // Cancel mid-first-wait.
      async.elapse(const Duration(milliseconds: 500));
      state.cancelWalkTheRange();

      // After the 3s wait boundary elapses, loop sees _walkActive=false and
      // breaks before firing T2.
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();

      expect(state.debugSentIdentifyIds, equals([1]),
          reason: 'cancel stops before the next fire');
      expect(state.walkTheRangeActive, isFalse);
      state.dispose();
    });
  });

  test('walkTheRange with zero online targets is a no-op', () {
    fakeAsync((async) {
      final state = AppState.forTest();
      // One target, offline.
      state.targets.add(TargetUnit(id: 1, isOnline: false));
      state.walkTheRange();
      async.flushMicrotasks();
      expect(state.walkTheRangeActive, isFalse);
      expect(state.debugSentIdentifyIds, isEmpty);
      state.dispose();
    });
  });

  test('walkTheRange during non-idle phase is a no-op', () {
    fakeAsync((async) {
      final state = AppState.forTest();
      state.targets.add(TargetUnit(id: 1, isOnline: true));
      state.debugSetPhase(DrillPhase.running);

      state.walkTheRange();
      async.flushMicrotasks();
      expect(state.walkTheRangeActive, isFalse);
      expect(state.debugSentIdentifyIds, isEmpty);
      state.dispose();
    });
  });

  test('walkTheRange skips removed targets', () {
    fakeAsync((async) {
      final state = AppState.forTest();
      state.targets
        ..add(TargetUnit(id: 1, isOnline: true))
        ..add(TargetUnit(id: 2, isOnline: true))
        ..add(TargetUnit(id: 3, isOnline: true));
      // Removed target — should NOT appear in the walk order.
      state.removeTarget(2);
      async.flushMicrotasks();

      state.walkTheRange();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      expect(state.debugSentIdentifyIds, equals([1, 3]));
      state.dispose();
    });
  });

  test('walkTheRange speaks each target name when ready-audio is enabled',
      () {
    fakeAsync((async) {
      final tts = RecordingTtsPort();
      final state = AppState.forTest(tts: tts);
      state.targets
        ..add(TargetUnit(id: 1, isOnline: true))
        ..add(TargetUnit(id: 2, isOnline: true));

      state.walkTheRange();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      expect(tts.spoken, equals(['T1', 'T2']));
      state.dispose();
    });
  });

  test('second walkTheRange while one is active is a no-op', () {
    fakeAsync((async) {
      final state = AppState.forTest();
      state.targets
        ..add(TargetUnit(id: 1, isOnline: true))
        ..add(TargetUnit(id: 2, isOnline: true));
      state.walkTheRange();
      async.flushMicrotasks();
      expect(state.debugSentIdentifyIds, equals([1]));
      expect(state.walkTheRangeActive, isTrue);

      // Attempt a second walk while still mid-walk.
      state.walkTheRange();
      async.flushMicrotasks();
      expect(state.debugSentIdentifyIds, equals([1]),
          reason: 'concurrent walk is blocked');

      // Let the active walk finish so fakeAsync drains cleanly.
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      state.dispose();
    });
  });
}
