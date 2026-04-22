import 'package:atriarch/models/target_unit.dart';
import 'package:atriarch/services/audio_service.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gate 2 #15 — ready-chime trigger rules (addendum §4.C).
///
/// Covers:
/// - DDONE with all targets online + setting enabled → chime fires.
/// - DDONE with an offline target → no chime.
/// - Two DDONEs in the same cycle → chime fires once.
/// - discoverTargets() between DDONEs → chime fires each cycle.
/// - Setting disabled → no chime.
/// - Late-arriving target completing the fleet post-DDONE → chime fires.
/// - Removed targets don't count toward the "all online" check.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NoopAudioService audio;
  late AppState state;

  setUp(() {
    audio = NoopAudioService();
    state = AppState.forTest(audio: audio);
  });

  tearDown(() {
    state.dispose();
  });

  test('DDONE with all non-removed targets online fires the chime once', () {
    state.debugInjectRawMessage('D/1/');
    state.debugInjectRawMessage('D/2/');
    state.debugInjectRawMessage('DDONE/');
    expect(audio.playCount, equals(1));
    // Volume defaults to 0.7 when the user hasn't changed it.
    expect(audio.playedVolumes.single, closeTo(0.7, 1e-9));
  });

  test('DDONE fires chime using the persisted volume', () async {
    await state.setReadyAudioVolume(0.25);
    state.debugInjectRawMessage('D/1/');
    state.debugInjectRawMessage('DDONE/');
    expect(audio.playedVolumes.single, closeTo(0.25, 1e-9));
  });

  test('DDONE with an offline target does NOT fire the chime', () {
    state.debugInjectRawMessage('D/1/');
    state.debugInjectRawMessage('D/2/');
    state.targets.firstWhere((t) => t.id == 2).isOnline = false;
    state.debugInjectRawMessage('DDONE/');
    expect(audio.playCount, equals(0));
  });

  test('two DDONEs in the same cycle fire the chime once only', () {
    state.debugInjectRawMessage('D/1/');
    state.debugInjectRawMessage('DDONE/');
    state.debugInjectRawMessage('DDONE/');
    expect(audio.playCount, equals(1));
  });

  test('discoverTargets() between DDONEs fires the chime each cycle',
      () async {
    state.debugInjectRawMessage('D/1/');
    state.debugInjectRawMessage('DDONE/');
    expect(audio.playCount, equals(1));

    // Begin a new cycle. discoverTargets() also tries a BLE write which
    // fails on the unconnected test service; that's irrelevant because
    // the cycle-reset logic runs before the write.
    try {
      await state.discoverTargets();
    } catch (_) {
      // Expected — no real BLE peripheral in unit tests.
    }

    state.debugInjectRawMessage('D/1/');
    state.debugInjectRawMessage('DDONE/');
    expect(audio.playCount, equals(2));
  });

  test('setting disabled → no chime even with all targets online',
      () async {
    await state.setReadyAudioEnabled(false);
    state.debugInjectRawMessage('D/1/');
    state.debugInjectRawMessage('DDONE/');
    expect(audio.playCount, equals(0));
  });

  test(
      'late-arriving target completing the fleet post-DDONE fires the chime '
      'exactly once', () {
    // T2 is already known (offline) from a prior cycle; T1 is discovered
    // this cycle and DDONE fires. The chime must NOT fire yet (T2 offline).
    state.targets.add(TargetUnit(id: 2, isOnline: false));
    state.debugInjectRawMessage('D/1/');
    state.debugInjectRawMessage('DDONE/');
    expect(audio.playCount, equals(0),
        reason: 'T2 offline at DDONE time → no chime yet');

    // T2 comes online late (straggler). That completes the fleet and fires
    // the chime.
    state.debugInjectRawMessage('D/2/');
    expect(audio.playCount, equals(1));

    // Another D/2/ in the same cycle must not re-fire.
    state.debugInjectRawMessage('D/2/');
    expect(audio.playCount, equals(1));
  });

  test(
      'late straggler BEFORE DDONE does not fire the chime until DDONE arrives',
      () {
    // Simulates a target discovery during the cycle; DDONE hasn't yet
    // happened, so even though the fleet is complete we wait for DDONE.
    state.targets.add(TargetUnit(id: 2, isOnline: false));
    state.debugInjectRawMessage('D/2/');
    state.debugInjectRawMessage('D/1/');
    expect(audio.playCount, equals(0),
        reason: 'No DDONE yet → mid-cycle completion must not chime');

    state.debugInjectRawMessage('DDONE/');
    expect(audio.playCount, equals(1));
  });

  test(
      'removed targets do not count toward "fleet all-online"; '
      'fleet of 1 removed + 1 online triggers the chime', () async {
    state.debugInjectRawMessage('D/1/');
    state.debugInjectRawMessage('D/2/');
    await state.removeTarget(1);
    state.targets.firstWhere((t) => t.id == 1).isOnline = false;

    state.debugInjectRawMessage('DDONE/');
    expect(audio.playCount, equals(1),
        reason: 'Only non-removed targets factor into readiness');
  });

  test('empty fleet (zero targets at DDONE) does not fire the chime', () {
    state.debugInjectRawMessage('DDONE/');
    expect(audio.playCount, equals(0));
  });

  test('setReadyAudioVolume clamps to [0.0, 1.0] and persists', () async {
    await state.setReadyAudioVolume(1.7);
    expect(state.readyAudioVolume, equals(1.0));
    await state.setReadyAudioVolume(-0.3);
    expect(state.readyAudioVolume, equals(0.0));
  });
}
