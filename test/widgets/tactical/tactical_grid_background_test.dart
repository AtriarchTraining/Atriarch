import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/widgets/tactical/tactical_grid_background.dart';

void main() {
  testWidgets('renders child over grid', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TacticalGridBackground(
          child: Text('OVERLAY_CONTENT'),
        ),
      ),
    );
    expect(find.text('OVERLAY_CONTENT'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
