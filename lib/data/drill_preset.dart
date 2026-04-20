import 'package:hive/hive.dart';
import '../models/drill_config.dart';

part 'drill_preset.g.dart';

/// A user-saved drill configuration (addendum §2 preset row).
///
/// Presets live in the `drill_presets` box keyed by [id]. The [version] field
/// supports future migrations via the [openTypedBox] migration table.
@HiveType(typeId: 10)
class DrillPreset extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  DateTime updatedAt;

  @HiveField(4)
  int version;

  @HiveField(5)
  DrillConfig config;

  DrillPreset({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.config,
    this.version = 1,
  });
}
