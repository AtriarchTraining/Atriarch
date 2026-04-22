// Colorblind-safe target chip (addendum §3, §6.1, §5.A).
// Every state is double-encoded: tint + icon + text suffix. Group membership
// is surfaced via a trailing pill with the group number. Never rely on
// color alone — ~8% of male trainers are red-green colorblind, and misreading
// a no-shoot target on a live range is a safety issue.
//
// Gate 2 #20 gesture model (Jeremy 2026-04-21):
//   - Short tap on body   -> [onTap]      (e.g. assign to group)
//   - Press-and-hold ≥200ms on body -> [onIdentifyHoldStart] on threshold,
//                                       [onIdentifyHoldEnd] on release.
//   - Trailing ⋯ IconButton -> [onOpenActions].
// This supersedes the Wave 2a #13 `onLongPress` trigger for the actions sheet.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Press-and-hold threshold before [TargetChip.onIdentifyHoldStart] fires
/// (addendum §5.A). Exposed for widget tests.
const Duration kTargetChipIdentifyHoldThreshold = Duration(milliseconds: 200);

class TargetChip extends StatefulWidget {
  final TargetUnit target;
  final bool selected;

  /// Short-tap (<200ms) callback. Existing "select / assign to group"
  /// behavior preserved from Wave 2a.
  final VoidCallback? onTap;

  /// Fires once when press-and-hold on the chip body crosses the 200ms
  /// threshold (addendum §5.A). Caller should begin repeated IDENT/.
  final VoidCallback? onIdentifyHoldStart;

  /// Fires on release after [onIdentifyHoldStart] has already fired. Any
  /// release path (pointer up, cancel, drag-off) drives this. Caller should
  /// stop the repeating IDENT/ timer.
  final VoidCallback? onIdentifyHoldEnd;

  /// Fires when the trailing ⋯ overflow button is tapped. Replaces the old
  /// long-press trigger for the actions sheet (#13).
  final VoidCallback? onOpenActions;

  /// When true, the press-and-hold gesture is swallowed (drill phase !=
  /// idle — don't flash target LEDs during live fire). The ⋯ overflow
  /// remains reachable since its actions are safe during a drill.
  final bool identifyHoldEnabled;

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
    this.onIdentifyHoldStart,
    this.onIdentifyHoldEnd,
    this.onOpenActions,
    this.identifyHoldEnabled = true,
    this.displayName,
    this.isRemoved = false,
  });

  @override
  State<TargetChip> createState() => _TargetChipState2();
}

class _TargetChipState2 extends State<TargetChip> {
  Timer? _holdTimer;
  bool _holdFired = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (!widget.identifyHoldEnabled) return;
    _holdTimer?.cancel();
    _holdFired = false;
    _holdTimer = Timer(kTargetChipIdentifyHoldThreshold, () {
      _holdFired = true;
      // Light haptic on threshold so the user knows the "flash" started.
      HapticFeedback.selectionClick();
      widget.onIdentifyHoldStart?.call();
    });
  }

  void _onTapUp(TapUpDetails _) {
    _endHold(invokeTap: true);
  }

  void _onTapCancel() {
    _endHold(invokeTap: false);
  }

  void _endHold({required bool invokeTap}) {
    final timer = _holdTimer;
    _holdTimer = null;
    final fired = _holdFired;
    _holdFired = false;
    timer?.cancel();

    if (fired) {
      HapticFeedback.selectionClick();
      widget.onIdentifyHoldEnd?.call();
      // Hold fired -> this was a hold gesture, not a tap. Don't call onTap.
      return;
    }

    // Not a hold — short tap path. Only fire onTap on a real release
    // (cancel means pointer drifted off; treat as no-op, matching InkWell).
    if (invokeTap) widget.onTap?.call();
  }

  _TargetChipState _state() {
    if (widget.isRemoved) return _TargetChipState.removed;
    if (!widget.target.isOnline) return _TargetChipState.offline;
    if (widget.target.isUnreachable) return _TargetChipState.unreachable;
    if (widget.target.isNoShoot && widget.target.groupId != null) {
      return _TargetChipState.noShootInGroup;
    }
    if (widget.target.isNoShoot) return _TargetChipState.noShoot;
    if (widget.target.groupId != null) return _TargetChipState.grouped;
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
          tokens.groupColor(widget.target.groupId!).withValues(alpha: 0.20),
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

    final border = widget.selected
        ? Border.all(color: tokens.textPrimary, width: 2)
        : (outline ?? Border.all(color: tokens.border, width: 1));

    final resolvedName = widget.displayName ?? widget.target.label;
    final labelText = '$resolvedName$suffix';
    // Hide the group badge on removed chips — they're out of the fleet.
    final showGroupBadge = widget.target.groupId != null && !widget.isRemoved;

    final bodyChildren = <Widget>[];
    if (leadingIcon != null) {
      bodyChildren.add(Icon(leadingIcon, size: 14, color: leadingIconColor));
      bodyChildren.add(const SizedBox(width: AtriarchSpacing.xs));
    }
    bodyChildren.add(
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
      bodyChildren.add(const SizedBox(width: AtriarchSpacing.xs));
      bodyChildren.add(
        _GroupBadge(groupId: widget.target.groupId!, tokens: tokens),
      );
    }

    // Chip body (press target for tap / hold-to-identify). Wrapped in
    // Semantics so assistive tech gets the state label and the hint about
    // hold-to-flash.
    final body = Semantics(
      label: _semanticsLabel(state),
      hint: 'Press and hold to identify, tap more for actions.',
      button: true,
      selected: widget.selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AtriarchSpacing.md,
              vertical: AtriarchSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: bodyChildren,
            ),
          ),
        ),
      ),
    );

    // Trailing ⋯ overflow button. 44pt min touch target so it's reachable
    // with a gloved thumb. Always tappable even when the hold gesture is
    // disabled (#20: overflow stays reachable during a drill).
    final overflow = Semantics(
      label: 'Target actions for $resolvedName',
      button: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 20,
          icon: const Icon(Icons.more_vert),
          tooltip: 'Target actions',
          onPressed: widget.onOpenActions,
        ),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.circular(AtriarchRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [body, overflow],
        ),
      ),
    );
  }

  String _semanticsLabel(_TargetChipState state) {
    final resolvedName = widget.displayName ?? widget.target.label;
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
        parts.add('in group ${widget.target.groupId}');
        break;
      case _TargetChipState.noShoot:
        parts.add('no-shoot');
        break;
      case _TargetChipState.grouped:
        parts.add('in group ${widget.target.groupId}');
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
