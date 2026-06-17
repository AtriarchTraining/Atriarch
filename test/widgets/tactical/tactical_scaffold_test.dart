import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_scaffold.dart';
import 'package:atriarch/widgets/tactical/tactical_app_bar.dart';
import 'package:atriarch/widgets/tactical/tactical_grid_background.dart';

void main() {
  testWidgets('composes app bar + grid bg + child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: const TacticalScaffold(
          title: 'SYSTEM_CONFIG',
          body: Text('PAGE_BODY'),
        ),
      ),
    );
    expect(find.byType(TacticalAppBar), findsOneWidget);
    expect(find.byType(TacticalGridBackground), findsOneWidget);
    expect(find.text('PAGE_BODY'), findsOneWidget);
  });
}
