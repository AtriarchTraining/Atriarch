// Colorblind-safe target chip (addendum §3, §6.1).
// Every state is double-encoded: tint + icon + text suffix. Group membership
// is surfaced via a trailing pill with the group number. Never rely on
// color alone — ~8% of male trainers are red-green colorblind, and misreading
// a no-shoot target on a live range is a safety issue.

import 'package:flutter/material.dart';
import '../models/target_unit.dart';
import '../theme/atriarch_theme.dart';

enum _TargetChipState {
  offline,
  unreachable,
  noShootInGroup,
  noShoot,
  grouped,
  unassignedOnline,
  removed,
}

class TargetChip extends StatelessWidget {
  final TargetUnit target;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// User-facing name for this target (e.g. "Flipper" or `T3`). Supplied by
  /// the caller so `TargetChip` stays independent of `AppState` / provider.
  /// When null, falls back to `target.label` (which is `T{id}` sans custom
  /// name).
  final String? displayName;

  /// When true, render the soft-deleted variant: neutral tint + delete icon
  /// + `· REMOVED` suffix. Takes precedence over every other state so the
  /// chip always reads the same regardless of online/group state.
  final bool isRemoved;

  const TargetChip({
    super.key,
    required this.target,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.displayName,
    this.isRemoved = false,
  });

  _TargetChipState _state() {
    if (isRemoved) return _TargetChipState.removed;
    if (!target.isOnline) return _TargetChipState.offline;
    if (target.isUnreachable) return _TargetChipState.unreachable;
    if (target.isNoShoot && target.groupId != null) {
      return _TargetChipState.noShootInGroup;
    }
    if (target.isNoShoot) return _TargetChipState.noShoot;
    if (target.groupId != null) return _TargetChipState.grouped;
    return _TargetChipState.unassignedOnline;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final state = _state();

    // Background tint: alpha-blend status color over bgCard for a subtle wash.
    Color bg = tokens.bgCard;
    IconData? leadingIcon;
    Color leadingIconColor = tokens.textPrimary;
    String suffix = '';
    Border? outline;

    switch (state) {
      case _TargetChipState.offline:
        bg = tokens.bgCard;
        leadingIcon = Icons.bluetooth_disabled;
        leadingIconColor = tokens.statusOffline;
        suffix = ' · OFFLINE';
        outline = Border.all(color: tokens.border);
        break;
      case _TargetChipState.unreachable:
        bg = Color.alphaBlend(
          tokens.statusArmed.withValues(alpha: 0.18),
          tokens.bgCard,
        );
        leadingIcon = Icons.warning;
        leadingIconColor = tokens.statusArmed;
        suffix = ' · UNREACHABLE';
        break;
      case _TargetChipState.noShootInGroup:
      case _TargetChipState.noShoot:
        bg = Color.alphaBlend(
          tokens.statusViolation.withValues(alpha: 0.18),
          tokens.bgCard,
        );
        leadingIcon = Icons.block;
        leadingIconColor = tokens.statusViolation;
        suffix = ' · NO-SHOOT';
        break;
      case _TargetChipState.grouped:
        bg = Color.alphaBlend(
          tokens.groupColor(target.groupId!).withValues(alpha: 0.20),
          tokens.bgCard,
        );
        break;
      case _TargetChipState.unassignedOnline:
        bg = tokens.bgCard;
        break;
      case _TargetChipState.removed:
        bg = tokens.bgCard;
        leadingIcon = Icons.delete;
        leadingIconColor = tokens.textTertiary;
        suffix = ' · REMOVED';
        outline = Border.all(color: tokens.border);
        break;
    }

    final border = selected
        ? Border.all(color: tokens.textPrimary, width: 2)
        : (outline ?? Border.all(color: tokens.border, width: 1));

    final resolvedName = displayName ?? target.label;
    final labelText = '$resolvedName$suffix';
    // Hide the group badge on removed chips — they're out of the fleet.
    final showGroupBadge = target.groupId != null && !isRemoved;

    final children = <Widget>[];
    if (leadingIcon != null) {
      children.add(Icon(leadingIcon, size: 14, color: leadingIconColor));
      children.add(const SizedBox(width: AtriarchSpacing.xs));
    }
    children.add(
      Flexible(
        child: Text(
          labelText,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: tokens.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    if (showGroupBadge) {
      children.add(const SizedBox(width: AtriarchSpacing.xs));
      children.add(_GroupBadge(groupId: target.groupId!, tokens: tokens));
    }

    return Semantics(
      label: _semanticsLabel(state),
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(AtriarchRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AtriarchSpacing.md,
                vertical: AtriarchSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: bg,
                border: border,
                borderRadius: BorderRadius.circular(AtriarchRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _semanticsLabel(_TargetChipState state) {
    final resolvedName = displayName ?? target.label;
    final parts = <String>['Target $resolvedName'];
    switch (state) {
      case _TargetChipState.offline:
        parts.add('offline');
        break;
      case _TargetChipState.unreachable:
        parts.add('unreachable');
        break;
      case _TargetChipState.noShootInGroup:
        parts.add('no-shoot');
        parts.add('in group ${target.groupId}');
        break;
      case _TargetChipState.noShoot:
        parts.add('no-shoot');
        break;
      case _TargetChipState.grouped:
        parts.add('in group ${target.groupId}');
        break;
      case _TargetChipState.unassignedOnline:
        parts.add('online, unassigned');
        break;
      case _TargetChipState.removed:
        parts.add('removed from fleet');
        break;
    }
    return parts.join(', ');
  }
}

class _GroupBadge extends StatelessWidget {
  final int groupId;
  final AtriarchTokens tokens;

  const _GroupBadge({required this.groupId, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.groupColor(groupId),
        borderRadius: BorderRadius.circular(AtriarchRadius.sm),
      ),
      child: Text(
        'G$groupId',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }
}
