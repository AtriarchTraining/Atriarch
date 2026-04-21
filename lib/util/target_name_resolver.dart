/// Resolves a target id to its user-facing display name.
///
/// Stateless helper built from a snapshot of the saved names map
/// (see [PreferencesRepository.getTargetNames]). `AppState` exposes a live
/// resolver; consumers that render chips / tables / event logs should use
/// [display] instead of hard-coding `'T{id}'`.
///
/// Addendum §4.B (user-named targets).
class TargetNameResolver {
  final Map<int, String> names;

  const TargetNameResolver(this.names);

  /// Display name: the custom name when saved, else `T{id}` fallback.
  String display(int targetId) => names[targetId] ?? 'T$targetId';

  /// The stored custom name, or null when none is saved.
  String? customName(int targetId) => names[targetId];
}
