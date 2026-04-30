import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Minimal playback interface used by [AudioService]. Lets tests inject a
/// recording fake without constructing a real [AudioPlayer] (which spins
/// up a platform channel).
abstract class AudioPlayerPort {
  Future<void> setAsset(String assetPath);
  Future<void> setVolume(double volume);
  Future<void> seek(Duration position);
  Future<void> play();
  Future<void> dispose();
}

class _JustAudioPlayerPort implements AudioPlayerPort {
  _JustAudioPlayerPort(this._player);

  final AudioPlayer _player;

  @override
  Future<void> setAsset(String assetPath) async {
    await _player.setAsset(assetPath);
  }

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Plays the ready-chime audio cue when the fleet comes fully online after
/// a discovery cycle (addendum §4.C).
///
/// Design notes:
/// - Uses the `ambient` audio-session category on iOS/macOS so playback
///   respects the physical silent switch. The chime is a non-alerting UI
///   cue; it must not override the user's "do not disturb this room" intent.
/// - Asset is `assets/sounds/ready.mp3`. During dev the file is a 0-byte
///   placeholder — `setAsset` will fail on first play, and the try/catch
///   swallows the error so the UI path stays crash-free. Drop the real MP3
///   in to enable sound.
/// - Playback is fire-and-forget from [AppState] on `DiscoveryDone`; failures
///   are logged via [debugPrint] but never thrown.
///
/// TODO(jeremy): replace `assets/sounds/ready.mp3` with the real 2-note
/// ascending bell (~500ms) before field test.
///
/// Callers should:
///   1. Construct in `main.dart`.
///   2. `await service.init()` before passing to [AppState].
///   3. Call [playReady] on the ready event.
///   4. Call [dispose] at process teardown (Flutter handles on exit; explicit
///      disposal is only necessary in tests).
///
/// Tests that don't need real playback should use [NoopAudioService], which
/// extends this class and overrides the three public entry points with
/// record-only stubs.
class AudioService {
  AudioService({AudioPlayerPort? player})
      : _player = player ?? _JustAudioPlayerPort(AudioPlayer());

  /// Test-only variant that skips creating any real player.
  AudioService._noop() : _player = null;

  /// Bundled asset path for the ready chime. Declared in
  /// `pubspec.yaml` under `flutter: assets: - assets/sounds/`.
  static const String readyAssetPath = 'assets/sounds/ready.mp3';

  final AudioPlayerPort? _player;
  bool _assetLoaded = false;
  bool _sessionConfigured = false;
  // Set true when setAsset fails so we skip playback and don't touch the
  // disposed native player (prevents stale AVFoundation callbacks crashing
  // on just_audio 0.9.x / iOS 26).
  bool _playerDisposed = false;

  /// Configure the iOS/macOS audio session category to `ambient` (respects
  /// the silent switch) and preload the ready asset. Best-effort: never
  /// throws.
  Future<void> init() async {
    await _configureSession();
    await _preloadAsset();
  }

  Future<void> _configureSession() async {
    if (_sessionConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          // Ambient = respects silent switch, mixes with other audio.
          // This is explicitly what §4.C calls for — non-alerting UI cue.
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions:
              AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.sonification,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.notificationEvent,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
          androidWillPauseWhenDucked: false,
        ),
      );
      _sessionConfigured = true;
    } catch (e) {
      debugPrint('AudioService: session configure failed: $e');
    }
  }

  Future<void> _preloadAsset() async {
    if (_assetLoaded || _playerDisposed) return;
    final player = _player;
    if (player == null) return;
    try {
      await player.setAsset(readyAssetPath);
      _assetLoaded = true;
    } catch (e) {
      debugPrint('AudioService: preload failed ($readyAssetPath): $e');
      // Dispose the native player immediately so no stale AVFoundation
      // callbacks fire after the failure (causes EXC_BAD_ACCESS on iOS 26
      // with just_audio 0.9.x). Mark disposed so playReady is a no-op.
      _playerDisposed = true;
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  /// Play the ready chime at [volume] (0.0–1.0). Best-effort; wraps all
  /// failure modes (asset missing, session unavailable, player disposed)
  /// in try/catch and logs instead of throwing.
  Future<void> playReady({required double volume}) async {
    final player = _player;
    if (player == null || _playerDisposed) return;
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    try {
      if (!_assetLoaded) {
        // Re-try preload on demand; useful when init() ran before the asset
        // bundle was ready (rare — but also simplifies the recovery path
        // if the real MP3 drops in mid-session via hot reload).
        await _preloadAsset();
      }
      await player.setVolume(clamped);
      await player.seek(Duration.zero);
      await player.play();
    } catch (e) {
      debugPrint('AudioService.playReady failed: $e');
    }
  }

  Future<void> dispose() async {
    final player = _player;
    if (player == null || _playerDisposed) return;
    _playerDisposed = true;
    try {
      await player.dispose();
    } catch (_) {
      // Best-effort.
    }
  }
}

/// Test/fake variant of [AudioService] that records every [playReady] call
/// without touching the real [AudioPlayer] or [AudioSession]. Used by
/// [AppState.forTest] and unit tests that want to verify the chime trigger
/// rules without playing actual audio during the test run.
class NoopAudioService extends AudioService {
  NoopAudioService() : super._noop();

  final List<double> playedVolumes = <double>[];

  int get playCount => playedVolumes.length;

  @override
  Future<void> init() async {}

  @override
  Future<void> playReady({required double volume}) async {
    playedVolumes.add(volume);
  }

  @override
  Future<void> dispose() async {}
}
