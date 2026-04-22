enum EventType {
  targetActivated,
  hitDetected,
  targetComplete,
  noShootViolation,
  lateHit,
  drillFinished,
  error,
}

/// Short protocol-facing codes for each [EventType]. Used by the drill log
/// JSON envelope (#17) so stored logs stay readable outside the app.
///
/// `ACT` / `HIT` / `DONE` / `NS` / `LATE` / `FIN` mirror the transmitter
/// protocol; `ERR` mirrors the generic error path.
const Map<EventType, String> kEventTypeCodes = <EventType, String>{
  EventType.targetActivated: 'ACT',
  EventType.hitDetected: 'HIT',
  EventType.targetComplete: 'DONE',
  EventType.noShootViolation: 'NS',
  EventType.lateHit: 'LATE',
  EventType.drillFinished: 'FIN',
  EventType.error: 'ERR',
};

EventType? eventTypeFromCode(String code) {
  for (final entry in kEventTypeCodes.entries) {
    if (entry.value == code) return entry.key;
  }
  return null;
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
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// JSON view for drill log export. Field ordering is deterministic so
  /// round-trip tests can string-compare without sort keys.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      't': timestamp.toUtc().toIso8601String(),
      'type': kEventTypeCodes[type]!,
    };
    if (targetId != null) map['targetId'] = targetId;
    if (hitNumber != null) map['hitNumber'] = hitNumber;
    if (requiredHits != null) map['requiredHits'] = requiredHits;
    if (totalTimeMs != null) map['totalTimeMs'] = totalTimeMs;
    if (errorDetail != null) map['errorDetail'] = errorDetail;
    return map;
  }

  /// Rebuild a [SessionEvent] from its JSON representation. Unknown event
  /// type codes map to [EventType.error] so future additions don't crash
  /// historical-view reconstruction.
  factory SessionEvent.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'];
    final type = rawType is String
        ? (eventTypeFromCode(rawType) ?? EventType.error)
        : EventType.error;
    final rawTimestamp = json['t'];
    DateTime ts;
    if (rawTimestamp is String) {
      ts = DateTime.tryParse(rawTimestamp) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }
    return SessionEvent(
      type: type,
      targetId: json['targetId'] as int?,
      hitNumber: json['hitNumber'] as int?,
      requiredHits: json['requiredHits'] as int?,
      totalTimeMs: json['totalTimeMs'] as int?,
      errorDetail: json['errorDetail'] as String?,
      timestamp: ts,
    );
  }
}
