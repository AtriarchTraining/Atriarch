import 'package:atriarch/services/audio_service.dart';

/// Alias + re-export for test consumers. The real `AudioService` ships a
/// [NoopAudioService] that already records every [playReady] volume without
/// touching a platform channel; use that directly in tests.
///
/// This file exists so widget-test imports have a single canonical location
/// (`test/test_helpers/fake_audio_service.dart`) that matches the
/// `fake_shooter_repo.dart` / `fake_preferences_repository.dart` pattern.
typedef FakeAudioService = NoopAudioService;
