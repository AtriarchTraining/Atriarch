import 'dart:convert';

import '../models/drill_config.dart';
import '../models/drill_session.dart';
import '../models/session_event.dart';

/// Drill log JSON envelope codec (addendum §4.F, #17).
///
/// Encodes a [DrillSession] into the v1 log payload and decodes the same
/// payload back into a [DecodedDrillLog] for historical-view rendering.
///
/// Schema:
/// ```json
/// {
///   "version": 1,
///   "drillId": "...",
///   "startedAt": "2026-04-20T14:05:00Z",
///   "preset": { "name": "...", "config": { ... } },
///   "targetNames": { "1": "Flipper", ... },
///   "events": [ { "t": "...", "type": "ACT", "targetId": 1 }, ... ]
/// }
/// ```
class DrillLogCodec {
  static const int version = 1;

  /// Build the JSON envelope for [session]. [presetName] defaults to
  /// "Custom" when null (matches [SessionSummary.presetName] convention).
  static Map<String, dynamic> encodeToMap(
    DrillSession session, {
    String? presetName,
    Map<int, String> targetNames = const <int, String>{},
  }) {
    return <String, dynamic>{
      'version': version,
      'drillId': session.drillId,
      'startedAt': session.startTime.toUtc().toIso8601String(),
      'preset': <String, dynamic>{
        'name': presetName ?? 'Custom',
        'config': session.config.toJson(),
      },
      'targetNames': <String, String>{
        for (final entry in targetNames.entries)
          entry.key.toString(): entry.value,
      },
      'events': session.events
          .map((e) => e.toJson())
          .toList(growable: false),
    };
  }

  /// Convenience wrapper that emits a JSON string suitable for
  /// [DrillLogRepository.writeLog].
  static String encode(
    DrillSession session, {
    String? presetName,
    Map<int, String> targetNames = const <int, String>{},
  }) {
    return jsonEncode(
      encodeToMap(
        session,
        presetName: presetName,
        targetNames: targetNames,
      ),
    );
  }

  /// Parse a JSON log string back into its typed representation.
  /// Throws [FormatException] when the payload is malformed.
  static DecodedDrillLog decode(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map) {
      throw const FormatException('Drill log payload is not a JSON object');
    }
    final map = Map<String, dynamic>.from(decoded);
    return decodeMap(map);
  }

  static DecodedDrillLog decodeMap(Map<String, dynamic> map) {
    final version = (map['version'] as num?)?.toInt() ?? 1;
    final drillId = map['drillId'] as String? ?? '';
    final rawStarted = map['startedAt'];
    final startedAt = rawStarted is String
        ? (DateTime.tryParse(rawStarted) ?? DateTime.fromMillisecondsSinceEpoch(0))
        : DateTime.fromMillisecondsSinceEpoch(0);

    final rawPreset = map['preset'];
    final String presetName;
    final DrillConfig config;
    if (rawPreset is Map) {
      final presetMap = Map<String, dynamic>.from(rawPreset);
      presetName = presetMap['name'] as String? ?? 'Custom';
      final rawConfig = presetMap['config'];
      if (rawConfig is Map) {
        config = DrillConfig.fromJson(Map<String, dynamic>.from(rawConfig));
      } else {
        config = DrillConfig(programType: ProgramType.programA);
      }
    } else {
      presetName = 'Custom';
      config = DrillConfig(programType: ProgramType.programA);
    }

    final rawTargetNames = map['targetNames'];
    final targetNames = <int, String>{};
    if (rawTargetNames is Map) {
      rawTargetNames.forEach((key, value) {
        if (value is! String) return;
        final id = int.tryParse(key.toString());
        if (id == null) return;
        targetNames[id] = value;
      });
    }

    final rawEvents = map['events'];
    final events = rawEvents is List
        ? rawEvents
            .whereType<Map>()
            .map((m) => SessionEvent.fromJson(Map<String, dynamic>.from(m)))
            .toList(growable: false)
        : const <SessionEvent>[];

    return DecodedDrillLog(
      version: version,
      drillId: drillId,
      startedAt: startedAt,
      presetName: presetName,
      config: config,
      targetNames: targetNames,
      events: events,
    );
  }
}

/// Typed view of a decoded drill log payload. Used by historical Results
/// to render the same screen as a live session.
class DecodedDrillLog {
  final int version;
  final String drillId;
  final DateTime startedAt;
  final String presetName;
  final DrillConfig config;
  final Map<int, String> targetNames;
  final List<SessionEvent> events;

  const DecodedDrillLog({
    required this.version,
    required this.drillId,
    required this.startedAt,
    required this.presetName,
    required this.config,
    required this.targetNames,
    required this.events,
  });
}
