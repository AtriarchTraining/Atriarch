import '../models/drill_session.dart';
import '../models/session_event.dart';
import 'drill_log_codec.dart';
import 'target_name_resolver.dart';

/// Thin view model that [ResultsScreen] consumes for BOTH live sessions and
/// historical sessions hydrated from a drill-log JSON blob (#16).
///
/// A live session passes through everything from [DrillSession]; a
/// historical session rebuilds from a [DecodedDrillLog] and embeds the
/// logged target-name snapshot so renames after the fact don't rewrite
/// history.
class ResultsViewModel {
  /// Stable id of the drill this view represents.
  final String drillId;

  /// Preset name at drill start (or "Custom").
  final String presetName;

  /// When the drill started.
  final DateTime startedAt;

  /// Total drill duration. For live sessions this is [DrillSession.elapsed];
  /// for historical sessions we derive it from the first/last event
  /// timestamps.
  final Duration duration;

  /// Ordered event list for the breakdown table + log.
  final List<SessionEvent> events;

  /// Resolver used by the per-target table. Live view defers to the global
  /// resolver (so in-flight renames take effect); historical view uses the
  /// snapshot stored on the log so rows keep the names they had.
  final TargetNameResolver nameResolver;

  const ResultsViewModel({
    required this.drillId,
    required this.presetName,
    required this.startedAt,
    required this.duration,
    required this.events,
    required this.nameResolver,
  });

  /// Build from the in-memory [DrillSession] that [AppState] owns during a
  /// live drill. [resolver] is taken from [AppState.targetNameResolver] so
  /// the screen reflects the latest rename state.
  factory ResultsViewModel.fromLiveSession(
    DrillSession session, {
    required String presetName,
    required TargetNameResolver resolver,
  }) {
    return ResultsViewModel(
      drillId: session.drillId,
      presetName: presetName,
      startedAt: session.startTime,
      duration: session.elapsed,
      events: List<SessionEvent>.unmodifiable(session.events),
      nameResolver: resolver,
    );
  }

  /// Build from a serialized drill log. Duration is recomputed from the
  /// event timestamps so a historical view stays stable even if the device
  /// clock has drifted since.
  factory ResultsViewModel.fromDecodedLog(DecodedDrillLog log) {
    final duration = _deriveDuration(log.startedAt, log.events);
    return ResultsViewModel(
      drillId: log.drillId,
      presetName: log.presetName,
      startedAt: log.startedAt,
      duration: duration,
      events: List<SessionEvent>.unmodifiable(log.events),
      nameResolver: TargetNameResolver(
        Map<int, String>.unmodifiable(log.targetNames),
      ),
    );
  }

  static Duration _deriveDuration(
    DateTime startedAt,
    List<SessionEvent> events,
  ) {
    if (events.isEmpty) return Duration.zero;
    final last = events.last.timestamp;
    final diff = last.difference(startedAt);
    return diff.isNegative ? Duration.zero : diff;
  }
}
