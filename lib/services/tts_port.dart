import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Minimal TTS port so tests can drop in a recording fake without pulling
/// in the real `flutter_tts` plugin (which needs platform channels).
abstract class TtsPort {
  Future<void> speak(String text);
  Future<void> stop();
}

/// Production implementation using package:flutter_tts.
class FlutterTtsPort implements TtsPort {
  FlutterTtsPort._(this._tts);
  final FlutterTts _tts;

  static Future<FlutterTtsPort> create() async {
    return FlutterTtsPort._(FlutterTts());
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (e) {
      // Plugin failures are non-fatal — walk continues silently.
      debugPrint('TTS.speak failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // best-effort
    }
  }
}

/// Test fake: records every spoken string without touching the plugin.
class RecordingTtsPort implements TtsPort {
  final List<String> spoken = <String>[];

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}
}
