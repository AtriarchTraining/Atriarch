class TargetUnit {
  final int id;
  bool isOnline;
  bool isNoShoot;

  /// Optional user-assigned name (e.g. "Flipper").
  /// Null means fall back to `T{id}`. Gate 2 persists this via
  /// PreferencesRepository (addendum §4.B).
  String? displayName;

  /// True when ≥3 heartbeats have been missed (addendum §3, §7.6).
  /// Gate 2 wires this from the heartbeat tracker; default false for now.
  bool isUnreachable;

  TargetUnit({
    required this.id,
    this.isOnline = false,
    this.isNoShoot = false,
    this.displayName,
    this.isUnreachable = false,
  });

  /// Human-facing label: user-assigned name if set, else `T{id}`.
  String get label => displayName ?? 'T$id';
}
