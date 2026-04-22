import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/program_a_setup_screen.dart';
import 'package:atriarch/widgets/tactical/group_node_card.dart';
import 'package:atriarch/widgets/tactical/tactical_min_max_card.dart';

void main() {
  testWidgets('renders 5 GroupNodeCards and 3 MinMaxCards', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ProgramASetupScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GroupNodeCard), findsNWidgets(5));
    expect(find.byType(TacticalMinMaxCard), findsNWidgets(3));
  });
}
