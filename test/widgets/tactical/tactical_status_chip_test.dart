import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/widgets/tactical/tactical_status_chip.dart';

void main() {
  testWidgets('renders label in uppercase with dot', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TacticalStatusChip(
            color: Colors.green,
            label: 'live',
          ),
        ),
      ),
    );
    expect(find.text('LIVE'), findsOneWidget);
  });
}
