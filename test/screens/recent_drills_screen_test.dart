// test/screens/recent_drills_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/screens/recent_drills_screen.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';

void main() {
  testWidgets('shows empty state when no sessions repo', (tester) async {
    // AppState() with no sessions repo → _loadItems returns [] → empty state
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const RecentDrillsScreen(),
        ),
      ),
    );
    await tester.pump(); // let FutureBuilder complete
    expect(find.text('NO SESSIONS RECORDED YET.'), findsOneWidget);
  });
}
