import 'session_event.dart';
import 'drill_config.dart';

class DrillSession {
  final DrillConfig config;
  final List<SessionEvent> events;
  final DateTime startTime;
  DateTime? endTime;
  bool isRunning;

  DrillSession({
    required this.config,
  })  : events = [],
        startTime = DateTime.now(),
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
