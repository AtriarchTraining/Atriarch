enum EventType {
  targetActivated,
  hitDetected,
  targetComplete,
  noShootViolation,
  lateHit,
  drillFinished,
  error,
}

class SessionEvent {
  final EventType type;
  final int? targetId;
  final int? hitNumber;
  final int? requiredHits;
  final int? totalTimeMs;
  final String? errorDetail;
  final DateTime timestamp;

  SessionEvent({
    required this.type,
    this.targetId,
    this.hitNumber,
    this.requiredHits,
    this.totalTimeMs,
    this.errorDetail,
  }) : timestamp = DateTime.now();
}
