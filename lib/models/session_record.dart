// lib/models/session_record.dart
//
// Maps 1:1 to a row in the `sessions` table. Distinct from DrillSession
// (the in-memory live-drill accumulator in lib/models/drill_session.dart).

import 'package:flutter/foundation.dart';

@immutable
class SessionRecord {
  final String id;
  final String shooterId;
  final String? templateId;
  final String programType;       // 'A' | 'B'
  final String configJson;
  final String configHash;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool finishedNormally;
  final int iterationsCompleted;

  const SessionRecord({
    required this.id,
    required this.shooterId,
    required this.programType,
    required this.configJson,
    required this.configHash,
    required this.startedAt,
    required this.finishedNormally,
    required this.iterationsCompleted,
    this.templateId,
    this.endedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'shooter_id': shooterId,
        'template_id': templateId,
        'program_type': programType,
        'config_json': configJson,
        'config_hash': configHash,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'finished_normally': finishedNormally ? 1 : 0,
        'iterations_completed': iterationsCompleted,
      };

  factory SessionRecord.fromMap(Map<String, Object?> m) => SessionRecord(
        id: m['id'] as String,
        shooterId: m['shooter_id'] as String,
        templateId: m['template_id'] as String?,
        programType: m['program_type'] as String,
        configJson: m['config_json'] as String,
        configHash: m['config_hash'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        endedAt: m['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int),
        finishedNormally: (m['finished_normally'] as int) == 1,
        iterationsCompleted: m['iterations_completed'] as int,
      );

  SessionRecord copyWith({
    String? templateId,
    DateTime? endedAt,
    bool? finishedNormally,
    int? iterationsCompleted,
  }) =>
      SessionRecord(
        id: id,
        shooterId: shooterId,
        programType: programType,
        configJson: configJson,
        configHash: configHash,
        startedAt: startedAt,
        templateId: templateId ?? this.templateId,
        endedAt: endedAt ?? this.endedAt,
        finishedNormally: finishedNormally ?? this.finishedNormally,
        iterationsCompleted: iterationsCompleted ?? this.iterationsCompleted,
      );
}
