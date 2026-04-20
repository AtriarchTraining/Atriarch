import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/widgets/tactical/tactical_app_bar.dart';

void main() {
  testWidgets('renders uppercase title and trailing slot', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: const TacticalAppBar(
            title: 'program_config',
            trailing: Text('TRAIL'),
          ),
          body: const SizedBox(),
        ),
      ),
    );
    expect(find.text('PROGRAM_CONFIG'), findsOneWidget);
    expect(find.text('TRAIL'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });
}
