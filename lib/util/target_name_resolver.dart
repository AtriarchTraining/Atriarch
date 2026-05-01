/// Resolves a target id to its user-facing display name.
///
/// Stateless helper built from a snapshot of the saved names map
/// (see [PreferencesRepository.getTargetNames]). `AppState` exposes a live
/// resolver; consumers that render chips / tables / event logs should use
/// [display] instead of hard-coding `'T{id}'` or `'NODE_T{id}'`.
class TargetNameResolver {
  final Map<int, String> names;

  const TargetNameResolver(this.names);

  /// Display name: the custom name when saved, else `T/U_##` fallback
  /// (zero-padded two-digit unit number).
  String display(int targetId) =>
      names[targetId] ?? 'T/U_${targetId.toString().padLeft(2, '0')}';

  /// The stored custom name, or null when none is saved.
  String? customName(int targetId) => names[targetId];
}
