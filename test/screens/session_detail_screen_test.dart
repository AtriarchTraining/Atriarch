// test/screens/session_detail_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/screens/session_detail_screen.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';

void main() {
  // AppState() with no repos → both loaders return null → shows "SESSION NOT FOUND"
  testWidgets('shows not-found when repos are null', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const SessionDetailScreen(sessionId: 'fake-id'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('SESSION NOT FOUND.'), findsOneWidget);
  });
}
