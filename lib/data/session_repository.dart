import 'dart:async';

import 'package:hive/hive.dart';

import 'hive_bootstrap.dart';
import 'session_summary.dart';

/// Current-session history for completed drills (addendum §4.E).
///
/// A "session" spans from the app being cold-started (or from the last
/// [clearSession]) until the app has been foregrounded again after >8h of
/// inactivity. This repository owns the 8h auto-clear policy via
/// [beginSessionIfNeeded] — callers invoke it on app start and resume.
///
/// Emits the full summary list on every mutation through [watch].
class SessionRepository {
  static const String historyBoxName = 'session_history';
  static const String settingsBoxName = 'app_settings';
  static const String _kSessionStart = 'session_start_iso';

  /// Max idle gap before the session auto-clears (addendum §4.E).
  static const Duration sessionIdleTimeout = Duration(hours: 8);

  Box<SessionSummary>? _history;
  Box<dynamic>? _settings;

  DateTime? _sessionStart;
  final List<SessionSummary> _cache = <SessionSummary>[];
  final StreamController<List<SessionSummary>> _controller =
      StreamController<List<SessionSummary>>.broadcast();

  /// Injectable clock, for testability.
  final DateTime Function() _clock;

  SessionRepository({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  bool get isInitialized => _history != null && _settings != null;

  DateTime? get sessionStart => _sessionStart;

  List<SessionSummary> get currentSessionDrills =>
      List<SessionSummary>.unmodifiable(_cache);

  Stream<List<SessionSummary>> watch() => _controller.stream;

  Future<void> init() async {
    _history ??= await openTypedBox<SessionSummary>(historyBoxName);
    _settings ??= await Hive.openBox<dynamic>(settingsBoxName);

    _cache
      ..clear()
      ..addAll(_history!.values);

    final iso = _settings!.get(_kSessionStart);
    if (iso is String) {
      _sessionStart = DateTime.tryParse(iso);
    }
  }

  Future<void> close() async {
    await _controller.close();
    await _history?.close();
    // Settings box is shared with PreferencesRepository; closing here would
    // break other holders. Callers that truly need to shut everything down
    // should call close on each repository — Hive refcounts box handles.
    _history = null;
    _settings = null;
  }

  /// If there is no active session, or the active session started more than
  /// [sessionIdleTimeout] ago, clear the history and stamp a fresh start.
  Future<void> beginSessionIfNeeded() async {
    final now = _clock();
    final start = _sessionStart;
    final stale =
        start == null || now.difference(start) >= sessionIdleTimeout;

    if (!stale) return;

    await _clearInternal(stampStart: now);
    _emit();
  }

  Future<void> appendDrill(SessionSummary summary) async {
    final box = _requireHistory();
    await box.add(summary);
    _cache.add(summary);
    _emit();
  }

  /// Explicitly wipe the current session. Does NOT restamp session-start —
  /// the next [beginSessionIfNeeded] call will.
  Future<void> clearSession() async {
    await _clearInternal(stampStart: null);
    _emit();
  }

  Future<void> _clearInternal({required DateTime? stampStart}) async {
    await _requireHistory().clear();
    _cache.clear();
    if (stampStart != null) {
      _sessionStart = stampStart;
      await _requireSettings().put(
        _kSessionStart,
        stampStart.toIso8601String(),
      );
    } else {
      _sessionStart = null;
      await _requireSettings().delete(_kSessionStart);
    }
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(List<SessionSummary>.unmodifiable(_cache));
  }

  Box<SessionSummary> _requireHistory() {
    final box = _history;
    if (box == null) {
      throw StateError('SessionRepository.init() must be called first');
    }
    return box;
  }

  Box<dynamic> _requireSettings() {
    final box = _settings;
    if (box == null) {
      throw StateError('SessionRepository.init() must be called first');
    }
    return box;
  }
}
