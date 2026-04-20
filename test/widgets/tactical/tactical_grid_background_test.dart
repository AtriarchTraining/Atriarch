import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_grid_background.dart';

void main() {
  testWidgets('renders child over grid', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: const TacticalGridBackground(
          child: Text('OVERLAY_CONTENT'),
        ),
      ),
    );
    expect(find.text('OVERLAY_CONTENT'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('asserts on cellSize <= 0', (tester) async {
    expect(
      () => TacticalGridBackground(cellSize: 0, child: const SizedBox()),
      throwsAssertionError,
    );
  });
}
