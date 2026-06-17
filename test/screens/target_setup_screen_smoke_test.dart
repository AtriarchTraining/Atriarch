import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atriarch/models/target_unit.dart';
import 'package:atriarch/screens/target_setup_screen.dart';
import 'package:atriarch/services/preferences_repository.dart';
import 'package:atriarch/state/app_state.dart';

import '../helpers/fake_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppState> _bootState() async {
    final prefs = PreferencesRepository(await SharedPreferences.getInstance());
    final s = AppState.forTesting(
      sessions: FakeSessionRepository(),
      shooterState: FakeShooterState(),
      preferences: prefs,
    );
    // Seed two targets initially (initState postFrameCallback will reset
    // isOnline flags via discoverTargets(); we re-apply them after the first
    // pump in each test).
    s.targets
      ..clear()
      ..addAll([
        TargetUnit(id: 1, isOnline: true),
        TargetUnit(id: 2, isOnline: false),
      ]);
    await s.hydratePreferences();
    return s;
  }

  /// Re-apply online flags after the postFrameCallback's discoverTargets()
  /// call resets them all to false.
  void _reseedOnlineFlags(AppState s) {
    s.targets[0].isOnline = true;
    s.targets[1].isOnline = false;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    s.notifyListeners();
  }

  testWidgets('renders target list with status + group picker + flash',
      (tester) async {
    final s = await _bootState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: s,
        child: const MaterialApp(home: TargetSetupScreen()),
      ),
    );
    // First pump: lets the postFrameCallback fire (discoverTargets resets
    // isOnline to false for all targets, BLE write silently fails).
    await tester.pump();
    // Re-apply online state and rebuild.
    _reseedOnlineFlags(s);
    await tester.pump();

    expect(find.text('Target 1'), findsOneWidget);
    expect(find.text('Target 2'), findsOneWidget);
    expect(find.text('online'), findsOneWidget);
    expect(find.text('offline'), findsOneWidget);
    // Each TargetRow has an IconButton with tooltip "Flash LED".
    final flashButtons = tester.widgetList<IconButton>(
      find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Flash LED',
      ),
    );
    expect(flashButtons, hasLength(2));
    expect(find.text('+ Add group'), findsOneWidget);
    // Drain the 8-second scan-timeout Timer created by discoverTargets() so no
    // pending timer remains when the widget tree is disposed.
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets('flash button disabled when target offline', (tester) async {
    final s = await _bootState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: s,
        child: const MaterialApp(home: TargetSetupScreen()),
      ),
    );
    await tester.pump();
    _reseedOnlineFlags(s);
    await tester.pump();

    final flashButtons = tester
        .widgetList<IconButton>(
          find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'Flash LED',
          ),
        )
        .toList();
    // Order matches target list order: Target 1 (online) enabled, Target 2 (offline) disabled.
    final enabledStates = flashButtons.map((b) => b.onPressed != null).toList();
    expect(enabledStates, [true, false]);
    // Drain the 8-second scan-timeout Timer created by discoverTargets().
    await tester.pump(const Duration(seconds: 9));
  });
}
