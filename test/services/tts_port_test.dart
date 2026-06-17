import 'package:atriarch/services/tts_port.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingTts implements TtsPort {
  final List<String> spoken = [];
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

void main() {
  test('a TtsPort substitute records spoken text', () async {
    final tts = _RecordingTts();
    await tts.speak('target one');
    expect(tts.spoken, ['target one']);
  });

  test('RecordingTtsPort from lib/services records spoken text', () async {
    final tts = RecordingTtsPort();
    await tts.speak('alpha');
    await tts.speak('bravo');
    expect(tts.spoken, ['alpha', 'bravo']);
  });
}
