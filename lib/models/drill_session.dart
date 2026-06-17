import 'package:uuid/uuid.dart';

import 'session_event.dart';
import 'drill_config.dart';

class DrillSession {
  /// Stable UUID assigned at drill-start time. Round-trips through drill
  /// log JSON and SessionSummary so historical views can re-open the
  /// serialized event log for this drill.
  final String drillId;

  /// Name of the preset loaded at start, or null when the user ran with
  /// an unsaved / modified config. [AppState._onDrillFinished] substitutes
  /// the JSON-visible value "Custom" on null.
  final String? presetName;

  final DrillConfig config;
  final List<SessionEvent> events;
  final DateTime startTime;
  DateTime? endTime;
  bool isRunning;

  DrillSession({
    required this.config,
    String? drillId,
    this.presetName,
    DateTime? startTime,
  })  : drillId = drillId ?? const Uuid().v4(),
        events = [],
        startTime = startTime ?? DateTime.now(),
        isRunning = true;

  void addEvent(SessionEvent event) {
    events.add(event);
    if (event.type == EventType.drillFinished) {
      isRunning = false;
      endTime = DateTime.now();
    }
  }

  Duration get elapsed => (endTime ?? DateTime.now()).difference(startTime);
}
