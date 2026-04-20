import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/models/target_unit.dart';
import 'package:atriarch/widgets/tactical/target_node_chip.dart';

void main() {
  Widget _wrap(Widget child) => MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(body: child),
      );

  Color _dotColor(WidgetTester tester) {
    final dotContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(TargetNodeChip),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      ),
    );
    return (dotContainer.decoration as BoxDecoration).color!;
  }

  testWidgets('renders label and fires onTap', (tester) async {
    var tapped = false;
    final target = TargetUnit(id: 3, isOnline: true);
    await tester.pumpWidget(
      _wrap(
        TargetNodeChip(target: target, onTap: () => tapped = true),
      ),
    );
    expect(find.text('T3'), findsOneWidget);
    await tester.tap(find.byType(TargetNodeChip));
    expect(tapped, isTrue);
  });

  testWidgets('uses displayName when provided', (tester) async {
    final target = TargetUnit(id: 7, displayName: 'ALPHA', isOnline: true);
    await tester.pumpWidget(
      _wrap(TargetNodeChip(target: target, onTap: () {})),
    );
    expect(find.text('ALPHA'), findsOneWidget);
  });

  testWidgets('online target shows statusLive dot', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TargetNodeChip(
          target: TargetUnit(id: 1, isOnline: true),
          onTap: () {},
        ),
      ),
    );
    final tokens = AtriarchTokens.dark;
    expect(_dotColor(tester), tokens.statusLive);
  });

  testWidgets('offline target shows statusOffline dot', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TargetNodeChip(
          target: TargetUnit(id: 1, isOnline: false),
          onTap: () {},
        ),
      ),
    );
    expect(_dotColor(tester), AtriarchTokens.dark.statusOffline);
  });

  testWidgets('no-shoot target shows statusViolation dot', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TargetNodeChip(
          target: TargetUnit(id: 1, isOnline: true, isNoShoot: true),
          onTap: () {},
        ),
      ),
    );
    expect(_dotColor(tester), AtriarchTokens.dark.statusViolation);
  });

  testWidgets('unreachable online target shows statusArmed dot',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        TargetNodeChip(
          target: TargetUnit(id: 1, isOnline: true, isUnreachable: true),
          onTap: () {},
        ),
      ),
    );
    expect(_dotColor(tester), AtriarchTokens.dark.statusArmed);
  });
}
