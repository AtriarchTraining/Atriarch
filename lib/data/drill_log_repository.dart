import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

/// Per-drill versioned event logs (addendum §4.F).
///
/// Values are raw JSON strings so the schema can evolve freely without a
/// Hive-adapter migration — the JSON envelope carries its own `version`
/// field (Wave 2 / task #17 will populate and parse it).
class DrillLogRepository {
  static const String boxName = 'drill_logs';
  static const String exportSubdir = 'drill_logs';

  Box<String>? _box;

  /// Optional override for tests; when null we use
  /// [getApplicationDocumentsDirectory].
  final Future<Directory> Function()? _documentsDirProvider;

  DrillLogRepository({Future<Directory> Function()? documentsDirProvider})
      : _documentsDirProvider = documentsDirProvider;

  bool get isInitialized => _box != null;

  Future<void> init() async {
    _box ??= await Hive.openBox<String>(boxName);
  }

  Future<void> close() async {
    await _box?.close();
    _box = null;
  }

  Future<void> writeLog(String drillId, String jsonPayload) async {
    await _require().put(drillId, jsonPayload);
  }

  Future<String?> readLog(String drillId) async {
    return _require().get(drillId);
  }

  Future<List<String>> listDrillIds() async {
    return _require().keys.cast<String>().toList(growable: false);
  }

  Future<void> deleteLog(String drillId) async {
    await _require().delete(drillId);
  }

  /// Writes the log payload to a temp file for share_plus and returns the
  /// absolute path. File lives under
  /// `<app-documents>/drill_logs/{drillId}.json`.
  ///
  /// Throws [StateError] when no log exists for [drillId].
  Future<String> exportLogToFile(String drillId) async {
    final payload = await readLog(drillId);
    if (payload == null) {
      throw StateError('No drill log found for drillId "$drillId"');
    }
    final docs = await (_documentsDirProvider?.call() ??
        getApplicationDocumentsDirectory());
    final dir = Directory('${docs.path}/$exportSubdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$drillId.json');
    await file.writeAsString(payload, flush: true);
    return file.path;
  }

  Box<String> _require() {
    final box = _box;
    if (box == null) {
      throw StateError('DrillLogRepository.init() must be called first');
    }
    return box;
  }
}
