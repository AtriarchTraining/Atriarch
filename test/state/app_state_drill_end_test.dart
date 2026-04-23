import 'dart:convert';

import 'package:atriarch/data/in_memory_repositories.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gate 2 #16+#17 — drill-end persistence pipeline.
///
/// Covers:
///  - FIN/ persists one summary + one log.
///  - STOP_ACK/ persists the same way.
///  - SNAP_REPLY !running persists the same way.
///  - Zero-activation drill (never armed) persists NOTHING.
///  - FIN after STOP_ACK does NOT double-persist (single drill, single write).
///  - Preset name defaults to "Custom"; honors the startDrill override.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;
  late InMemorySessionRepository sessions;
  late InMemoryDrillLogRepository logs;

  setUp(() {
    sessions = InMemorySessionRepository();
    logs = InMemoryDrillLogRepository();
    state = AppState.forTest(sessions: sessions, drillLogs: logs);
  });

  tearDown(() {
    state.dispose();
  });

  /// Drive a minimal drill: startDrill → ACT → then whatever termination the
  /// test wants to inject. Returns after the ACT so the caller can choose
  /// how to end.
  Future<void> _startAndActivate({String? presetName}) async {
    final cfg = DrillConfig(
      programType: ProgramType.programB,
      targetIds: [1],
    );
    try {
      await state.startDrill(cfg, presetName: presetName);
    } catch (_) {
      // BLE write fails under test — startDrill still sets phase + session.
    }
    state.debugInjectRawMessage('ACT/1/');
  }

  test('FIN/ persists one summary + one log JSON', () async {
    await _startAndActivate();
    state.debugInjectRawMessage('HIT/1/1/1/');
    state.debugInjectRawMessage('DONE/1/812/');
    state.debugInjectRawMessage('FIN/');
    // Let the queued persistence microtasks land.
    await Future<void>.delayed(Duration.zero);

    expect(sessions.currentSessionDrills, hasLength(1));
    final summary = sessions.currentSessionDrills.single;
    expect(summary.drillId, equals(state.currentSession!.drillId));
    expect(summary.completions, equals(1));
    expect(summary.violations, equals(0));
    expect(summary.lateHits, equals(0));
    expect(summary.incomplete, isFalse);

    final stored = await logs.readLog(summary.drillId);
    expect(stored, isNotNull);
    final decoded = jsonDecode(stored!) as Map<String, dynamic>;
    expect(decoded['version'], equals(1));
    expect(decoded['drillId'], equals(summary.drillId));
    expect((decoded['events'] as List), isNotEmpty);
  });

  test('STOP_ACK/ path persists like FIN/', () async {
    await _startAndActivate();
    state.debugInjectRawMessage('STOP_ACK/');
    await Future<void>.delayed(Duration.zero);
    expect(sessions.currentSessionDrills, hasLength(1));
    final stored =
        await logs.readLog(state.currentSession!.drillId);
    expect(stored, isNotNull);
  });

  test('SNAP_REPLY/0 path persists like FIN/', () async {
    await _startAndActivate();
    state.debugInjectRawMessage('SNAP_REPLY/0/0/');
    await Future<void>.delayed(Duration.zero);
    expect(sessions.currentSessionDrills, hasLength(1));
    final summary = sessions.currentSessionDrills.single;
    // Transmitter drop during running is treated as incomplete per spec.
    expect(summary.incomplete, isTrue);
  });

  test('zero-activation drill skips persistence entirely', () async {
    final cfg = DrillConfig(
      programType: ProgramType.programB,
      targetIds: [1],
    );
    try {
      await state.startDrill(cfg);
    } catch (_) {}
    // NO activation — just inject FIN/ (simulates fast STOP after ARMING).
    state.debugInjectRawMessage('FIN/');
    await Future<void>.delayed(Duration.zero);
    expect(sessions.currentSessionDrills, isEmpty);
    expect(await logs.listDrillIds(), isEmpty);
  });

  test('FIN after STOP_ACK does not double-persist', () async {
    await _startAndActivate();
    state.debugInjectRawMessage('STOP_ACK/');
    state.debugInjectRawMessage('FIN/');
    await Future<void>.delayed(Duration.zero);
    expect(sessions.currentSessionDrills, hasLength(1));
    final ids = await logs.listDrillIds();
    expect(ids, hasLength(1));
  });

  test('preset name defaults to "Custom" when null', () async {
    await _startAndActivate();
    state.debugInjectRawMessage('FIN/');
    await Future<void>.delayed(Duration.zero);
    expect(sessions.currentSessionDrills.single.presetName, equals('Custom'));
    final stored =
        await logs.readLog(sessions.currentSessionDrills.single.drillId);
    final decoded = jsonDecode(stored!) as Map<String, dynamic>;
    expect((decoded['preset'] as Map)['name'], equals('Custom'));
  });

  test('preset name honored when passed to startDrill', () async {
    await _startAndActivate(presetName: 'Bill Drill');
    state.debugInjectRawMessage('FIN/');
    await Future<void>.delayed(Duration.zero);
    final summary = sessions.currentSessionDrills.single;
    expect(summary.presetName, equals('Bill Drill'));
    final stored = await logs.readLog(summary.drillId);
    final decoded = jsonDecode(stored!) as Map<String, dynamic>;
    expect((decoded['preset'] as Map)['name'], equals('Bill Drill'));
  });
}
