import 'dart:convert';

import '../services/config_hasher.dart';
import 'drill_config.dart';
import 'target_group.dart';

/// A saved drill configuration. Maps 1:1 to a row in the `drill_templates`
/// SQLite table. User-facing label is "preset"; the code-level name is
/// DrillTemplate to match the schema.
///
/// `shooterId == null` means an app-wide preset (gate-2's default). The
/// Instructor SKU can later introduce per-shooter presets without a schema
/// migration.
class DrillTemplate {
  final String id;
  final String? shooterId;
  final String name;
  final ProgramType programType;
  final DrillConfig config;
  final String configHash;
  final DateTime createdAt;

  const DrillTemplate({
    required this.id,
    required this.shooterId,
    required this.name,
    required this.programType,
    required this.config,
    required this.configHash,
    required this.createdAt,
  });

  String get programTypeCode => programType == ProgramType.programA ? 'A' : 'B';

  Map<String, Object?> toRow() => {
        'id': id,
        'shooter_id': shooterId,
        'name': name,
        'program_type': programTypeCode,
        'config_json': ConfigHasher.canonicalJson(config),
        'config_hash': configHash,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory DrillTemplate.fromRow(Map<String, Object?> row) {
    final configJson = row['config_json'] as String;
    final configMap = json.decode(configJson) as Map<String, Object?>;
    final program = (row['program_type'] as String) == 'A'
        ? ProgramType.programA
        : ProgramType.programB;
    return DrillTemplate(
      id: row['id'] as String,
      shooterId: row['shooter_id'] as String?,
      name: row['name'] as String,
      programType: program,
      config: _configFromCanonicalMap(configMap, program),
      configHash: row['config_hash'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  /// Rebuild a DrillConfig from the canonical-json map that [ConfigHasher]
  /// produces. Differs from `DrillConfig.fromJson` in two ways:
  /// 1. programType is stored as 'A'/'B' (not `.name`) in canonical form, and
  ///    typically also passed in from the row's program_type column.
  /// 2. Groups in canonical form omit `id`/`name`; we synthesize defaults
  ///    from positional order.
  static DrillConfig _configFromCanonicalMap(
    Map<String, Object?> m,
    ProgramType programType,
  ) {
    final rawGroups = m['groups'];
    final groups = <TargetGroup>[];
    if (rawGroups is List) {
      for (var i = 0; i < rawGroups.length; i++) {
        final g = rawGroups[i];
        if (g is Map) {
          final ids = (g['targetIds'] as List?)
                  ?.whereType<num>()
                  .map((n) => n.toInt())
                  .toList() ??
              <int>[];
          groups.add(TargetGroup(id: i + 1, targetIds: ids));
        }
      }
    }
    return DrillConfig(
      programType: programType,
      startMin: (m['startMin'] as num?)?.toDouble() ?? 1.0,
      startMax: (m['startMax'] as num?)?.toDouble() ?? 3.0,
      delayMin: (m['delayMin'] as num?)?.toDouble() ?? 0.5,
      delayMax: (m['delayMax'] as num?)?.toDouble() ?? 2.0,
      hitsMin: (m['hitsMin'] as num?)?.toInt() ?? 1,
      hitsMax: (m['hitsMax'] as num?)?.toInt() ?? 3,
      iterations: (m['iterations'] as num?)?.toInt() ?? 5,
      groups: groups,
      targetIds: (m['targetIds'] as List?)
              ?.whereType<num>()
              .map((n) => n.toInt())
              .toList() ??
          <int>[],
      noShootIds: (m['noShootIds'] as List?)
              ?.whereType<num>()
              .map((n) => n.toInt())
              .toList() ??
          <int>[],
    );
  }
}
