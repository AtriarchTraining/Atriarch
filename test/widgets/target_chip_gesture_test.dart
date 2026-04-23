// Gate 2 #20 — TargetChip gesture model rewrite.
//
// Verifies:
//  - Press-and-hold fires onIdentifyHoldStart after 200ms; release fires
//    onIdentifyHoldEnd.
//  - Release before 200ms fires neither start nor end.
//  - Trailing ⋯ overflow button fires onOpenActions exactly once.
//  - Short tap on chip body fires onTap.
//  - identifyHoldEnabled=false disables the hold gesture.

import 'package:atriarch/models/target_unit.dart';
import 'package:atriarch/widgets/target_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Rec {
  int tapCount = 0;
  int holdStartCount = 0;
  int holdEndCount = 0;
  int openActionsCount = 0;
}

Future<void> _pumpChip(
  WidgetTester tester, {
  required _Rec rec,
  TargetUnit? target,
  bool identifyHoldEnabled = true,
}) async {
  target ??= TargetUnit(id: 3, isOnline: true);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: TargetChip(
            target: target,
            identifyHoldEnabled: identifyHoldEnabled,
            onTap: () => rec.tapCount++,
            onIdentifyHoldStart: () => rec.holdStartCount++,
            onIdentifyHoldEnd: () => rec.holdEndCount++,
            onOpenActions: () => rec.openActionsCount++,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('TargetChip gesture', () {
    testWidgets('press-and-hold >=200ms fires start + end', (tester) async {
      final rec = _Rec();
      await _pumpChip(tester, rec: rec);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(TargetChip)));
      // Before threshold: neither fires.
      await tester.pump(const Duration(milliseconds: 100));
      expect(rec.holdStartCount, 0);
      expect(rec.holdEndCount, 0);

      // Cross 200ms threshold.
      await tester.pump(const Duration(milliseconds: 150));
      expect(rec.holdStartCount, 1, reason: 'start fires on threshold');
      expect(rec.holdEndCount, 0);

      // Release.
      await gesture.up();
      await tester.pump();
      expect(rec.holdEndCount, 1);
      // Hold path does NOT invoke onTap.
      expect(rec.tapCount, 0);
    });

    testWidgets('release before 200ms does not fire start or end',
        (tester) async {
      final rec = _Rec();
      await _pumpChip(tester, rec: rec);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(TargetChip)));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.up();
      await tester.pump();

      expect(rec.holdStartCount, 0);
      expect(rec.holdEndCount, 0);
      // Short tap routes through onTap.
      expect(rec.tapCount, 1);
    });

    testWidgets('overflow ⋯ button fires onOpenActions exactly once',
        (tester) async {
      final rec = _Rec();
      await _pumpChip(tester, rec: rec);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      expect(rec.openActionsCount, 1);
      // Tapping the overflow does not leak into the body handlers.
      expect(rec.tapCount, 0);
      expect(rec.holdStartCount, 0);
    });

    testWidgets('identifyHoldEnabled=false disables hold gesture',
        (tester) async {
      final rec = _Rec();
      await _pumpChip(tester, rec: rec, identifyHoldEnabled: false);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(TargetChip)));
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pump();

      expect(rec.holdStartCount, 0,
          reason: 'hold disabled — start must not fire');
      expect(rec.holdEndCount, 0);
      // Overflow remains reachable even when holds are disabled.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      expect(rec.openActionsCount, 1);
    });

    testWidgets('short tap on body fires onTap', (tester) async {
      final rec = _Rec();
      await _pumpChip(tester, rec: rec);
      // Tap the chip body (not the overflow icon).
      await tester.tapAt(tester.getCenter(find.byType(TargetChip)) -
          const Offset(30, 0));
      await tester.pump();
      expect(rec.tapCount, 1);
    });
  });
}
