// lib/services/config_hasher.dart
//
// Canonical JSON serialization of DrillConfig → sha256 hex.
// "Canonical" = sorted keys at every level, deterministic list ordering,
// so two equivalent DrillConfigs always produce the same hash.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/drill_config.dart';
import '../models/target_group.dart';

class ConfigHasher {
  /// Returns the canonical JSON string for a DrillConfig.
  /// Public so callers can also persist the same json alongside the hash.
  static String canonicalJson(DrillConfig c) {
    final map = <String, Object?>{
      'programType': _programTypeString(c.programType),
      'startMin': c.startMin,
      'startMax': c.startMax,
      'delayMin': c.delayMin,
      'delayMax': c.delayMax,
      'hitsMin': c.hitsMin,
      'hitsMax': c.hitsMax,
      'groups': c.groups.map(_groupToJson).toList(),
      'targetIds': [...c.targetIds]..sort(),
      'noShootIds': [...c.noShootIds]..sort(),
      'iterations': c.iterations,
    };
    return _jsonEncodeSorted(map);
  }

  /// Returns sha256 of canonical JSON as a 64-char lowercase hex string.
  static String hash(DrillConfig c) {
    final bytes = utf8.encode(canonicalJson(c));
    return sha256.convert(bytes).toString();
  }

  static String _programTypeString(ProgramType t) =>
      t == ProgramType.programA ? 'A' : 'B';

  static Map<String, Object?> _groupToJson(TargetGroup g) => {
        'targetIds': [...g.targetIds]..sort(),
      };

  static String _jsonEncodeSorted(Object? value) {
    Object? norm(Object? v) {
      if (v is Map) {
        final sorted = <String, Object?>{};
        final keys = v.keys.cast<String>().toList()..sort();
        for (final k in keys) {
          sorted[k] = norm(v[k]);
        }
        return sorted;
      }
      if (v is List) return v.map(norm).toList();
      return v;
    }

    return jsonEncode(norm(value));
  }
}
