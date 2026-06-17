import 'package:atriarch/services/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every call to the player surface so tests can assert ordering
/// and argument values.
class _RecordingPlayerPort implements AudioPlayerPort {
  final List<String> calls = <String>[];
  double? lastVolume;
  Duration? lastSeek;
  bool disposed = false;
  bool failSetAsset = false;
  bool failPlay = false;

  @override
  Future<void> setAsset(String assetPath) async {
    calls.add('setAsset:$assetPath');
    if (failSetAsset) {
      throw StateError('setAsset failure (simulated)');
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('setVolume:$volume');
    lastVolume = volume;
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
    lastSeek = position;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    if (failPlay) {
      throw StateError('play failure (simulated)');
    }
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    disposed = true;
  }
}

void main() {
  group('AudioService', () {
    test('playReady calls setVolume, seek(0), play in order', () async {
      final port = _RecordingPlayerPort();
      final service = AudioService(player: port);
      // init() will attempt setAsset (may "succeed" silently in the fake).
      await service.init();

      await service.playReady(volume: 0.7);

      // Asset load happens once during init().
      expect(port.calls.first, equals('setAsset:${AudioService.readyAssetPath}'));
      // After preload, the play sequence is setVolume → seek(0) → play.
      final playTrace = port.calls.sublist(port.calls.indexOf('setVolume:0.7'));
      expect(playTrace, equals(['setVolume:0.7', 'seek:0', 'play']));
      expect(port.lastVolume, closeTo(0.7, 1e-9));
      expect(port.lastSeek, equals(Duration.zero));
    });

    test('playReady clamps volume to [0.0, 1.0]', () async {
      final port = _RecordingPlayerPort();
      final service = AudioService(player: port);
      await service.init();

      await service.playReady(volume: 1.5);
      expect(port.lastVolume, equals(1.0));

      await service.playReady(volume: -0.3);
      expect(port.lastVolume, equals(0.0));
    });

    test(
        'playReady swallows player errors and does not rethrow',
        () async {
      final port = _RecordingPlayerPort()..failPlay = true;
      final service = AudioService(player: port);
      await service.init();

      // Must not throw.
      await service.playReady(volume: 0.5);

      // play() was attempted (recorded before the throw fires).
      expect(port.calls, contains('play'));
    });

    test('playReady retries asset preload when init() preload failed',
        () async {
      final port = _RecordingPlayerPort()..failSetAsset = true;
      final service = AudioService(player: port);
      await service.init(); // setAsset throws → _assetLoaded stays false.

      port.failSetAsset = false; // simulate asset becoming available.
      await service.playReady(volume: 0.4);

      // Two setAsset attempts: init() + recovery in playReady.
      final setAssetCalls =
          port.calls.where((c) => c.startsWith('setAsset:')).toList();
      expect(setAssetCalls, hasLength(2));
      // Volume and play eventually succeed.
      expect(port.calls, containsAllInOrder(['setVolume:0.4', 'seek:0', 'play']));
    });

    test('dispose forwards to the underlying port', () async {
      final port = _RecordingPlayerPort();
      final service = AudioService(player: port);
      await service.init();

      await service.dispose();
      expect(port.disposed, isTrue);
      expect(port.calls.last, equals('dispose'));
    });
  });

  group('NoopAudioService', () {
    test('records every playReady call, does not throw', () async {
      final noop = NoopAudioService();
      await noop.init();
      await noop.playReady(volume: 0.7);
      await noop.playReady(volume: 0.3);
      expect(noop.playCount, equals(2));
      expect(noop.playedVolumes, equals([0.7, 0.3]));
      await noop.dispose();
    });
  });
}
