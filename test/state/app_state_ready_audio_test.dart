import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/services/audio_service.dart';
import 'package:atriarch/services/preferences_repository.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/state/shooter_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/fake_shooter_repo.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AppState ready-audio gating', () {
    Future<_Fixture> build({
      bool enabled = true,
      double volume = 1.0,
    }) async {
      final sp = await SharedPreferences.getInstance();
      final prefs = PreferencesRepository(sp);
      await prefs.setReadyAudioEnabled(enabled);
      await prefs.setReadyAudioVolume(volume);
      final audio = NoopAudioService();
      final ShooterRepository shooterRepo =
          FakeShooterRepo([makeUnassignedShooter()]);
      final state = AppState(
        shooterState: ShooterState(shooterRepo),
        preferences: prefs,
        audio: audio,
      );
      await state.hydratePreferences();
      return _Fixture(state: state, audio: audio);
    }

    test('plays chime when enabled and passes configured volume', () async {
      final f = await build(enabled: true, volume: 0.6);
      await f.state.playReadyChimeForTesting();
      expect(f.audio.playCount, 1);
      expect(f.audio.playedVolumes.single, closeTo(0.6, 1e-9));
    });

    test('does not play chime when disabled', () async {
      final f = await build(enabled: false);
      await f.state.playReadyChimeForTesting();
      expect(f.audio.playCount, 0);
    });

    test('setReadyAudioEnabled persists and mirrors state', () async {
      final f = await build(enabled: true);
      await f.state.setReadyAudioEnabled(false);
      expect(f.state.readyAudioEnabled, isFalse);
      final sp = await SharedPreferences.getInstance();
      expect(await PreferencesRepository(sp).isReadyAudioEnabled(), isFalse);
    });

    test('setReadyAudioVolume clamps and persists', () async {
      final f = await build(enabled: true, volume: 1.0);
      await f.state.setReadyAudioVolume(2.5);
      expect(f.state.readyAudioVolume, 1.0);
      await f.state.setReadyAudioVolume(-0.3);
      expect(f.state.readyAudioVolume, 0.0);
      await f.state.setReadyAudioVolume(0.4);
      expect(f.state.readyAudioVolume, 0.4);
      final sp = await SharedPreferences.getInstance();
      expect(await PreferencesRepository(sp).getReadyAudioVolume(), 0.4);
    });
  });
}

class _Fixture {
  _Fixture({required this.state, required this.audio});
  final AppState state;
  final NoopAudioService audio;
}
