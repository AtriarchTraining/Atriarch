import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/device_discovery_screen.dart';
import 'package:atriarch/widgets/tactical/tactical_section.dart';

void main() {
  testWidgets('renders PARAM_01 scan section', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const DeviceDiscoveryScreen(),
        ),
      ),
    );
    // First frame only — avoid touching BLE streams.
    expect(find.byType(TacticalSection), findsWidgets);
    expect(find.text('PARAM_01'), findsOneWidget);
  });
}
