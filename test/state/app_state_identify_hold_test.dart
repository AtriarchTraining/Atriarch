// Gate 2 #20 — press-and-hold IDENT/ cadence + safety gates.

import 'package:atriarch/state/app_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('identifyHoldStart fires immediate IDENT + periodic at 700ms', () {
    fakeAsync((async) {
      final state = AppState.forTest();
      state.identifyHoldStart(5);
      // Immediate fire.
      expect(state.debugSentIdentifyIds, equals([5]));

      // Advance 700ms -> one periodic tick.
      async.elapse(const Duration(milliseconds: 700));
      expect(state.debugSentIdentifyIds, equals([5, 5]));

      // Another 700ms -> another tick.
      async.elapse(const Duration(milliseconds: 700));
      expect(state.debugSentIdentifyIds, equals([5, 5, 5]));

      state.identifyHoldEnd(5);
      async.elapse(const Duration(seconds: 2));
      expect(state.debugSentIdentifyIds, equals([5, 5, 5]),
          reason: 'no more IDENT/ after release');
      state.dispose();
    });
  });

  test('identifyHoldEnd cancels the timer', () {
    fakeAsync((async) {
      final state = AppState.forTest();
      state.identifyHoldStart(7);
      async.elapse(const Duration(milliseconds: 350));
      state.identifyHoldEnd(7);
      async.elapse(const Duration(seconds: 5));
      // Exactly one fire — the immediate one. No periodic ticks because
      // the first tick would have been at 700ms and we stopped at 350ms.
      expect(state.debugSentIdentifyIds, equals([7]));
      state.dispose();
    });
  });

  test('two identifyHoldStart calls on same id coalesce (one timer)', () {
    fakeAsync((async) {
      final state = AppState.forTest();
      state.identifyHoldStart(3);
      state.identifyHoldStart(3);
      // Both calls produced an immediate fire; second call cancelled the
      // first timer and started a fresh one. So we have 2 immediate fires,
      // then periodic fires at 700ms from the second call.
      expect(state.debugSentIdentifyIds.length, 2);

      async.elapse(const Duration(milliseconds: 700));
      // One periodic tick (not two).
      expect(state.debugSentIdentifyIds.length, 3);

      async.elapse(const Duration(milliseconds: 700));
      expect(state.debugSentIdentifyIds.length, 4);

      state.identifyHoldEnd(3);
      state.dispose();
    });
  });

  test('identifyHoldStart during running phase is a no-op', () {
    fakeAsync((async) {
      final state = AppState.forTest();
      state.debugSetPhase(DrillPhase.running);
      state.identifyHoldStart(4);
      async.elapse(const Duration(seconds: 2));
      expect(state.debugSentIdentifyIds, isEmpty,
          reason: 'safety: no IDENT during drill');
      state.dispose();
    });
  });

  test('identifyHoldStart during arming/stopping is a no-op', () {
    fakeAsync((async) {
      final state = AppState.forTest();
      state.debugSetPhase(DrillPhase.arming);
      state.identifyHoldStart(1);
      state.debugSetPhase(DrillPhase.stopping);
      state.identifyHoldStart(2);
      async.elapse(const Duration(seconds: 2));
      expect(state.debugSentIdentifyIds, isEmpty);
      state.dispose();
    });
  });

  test('consumeIdentifyHoldTip returns true first, false thereafter',
      () async {
    final state = AppState.forTest();
    expect(await state.consumeIdentifyHoldTip(), isTrue);
    expect(await state.consumeIdentifyHoldTip(), isFalse);
    expect(await state.consumeIdentifyHoldTip(), isFalse);
    state.dispose();
  });
}
