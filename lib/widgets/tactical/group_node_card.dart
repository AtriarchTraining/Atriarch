import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';
import '../../util/target_name_resolver.dart';

class GroupNodeCard extends StatelessWidget {
  final int groupIndex; // 0-based
  final List<int> targetIds;
  final bool selected;
  final TargetNameResolver resolver;
  final VoidCallback onTap;
  final ValueChanged<int> onRemoveTarget;

  const GroupNodeCard({
    super.key,
    required this.groupIndex,
    required this.targetIds,
    required this.selected,
    required this.resolver,
    required this.onTap,
    required this.onRemoveTarget,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final assigned = targetIds.isNotEmpty;
    final groupColor = tokens.groupColor(groupIndex + 1);
    final nodeLabel =
        'NODE_${(groupIndex + 1).toString().padLeft(2, '0')}';
    final groupLabel = 'GROUP ${(groupIndex + 1).toString().padLeft(2, '0')}';

    final bg = assigned
        ? tokens.bgElevated
        : tokens.bgCard.withValues(alpha: 0.5);
    final border = selected
        ? Border.all(color: tokens.statusHit, width: 2)
        : Border(
            left: BorderSide(
              color: assigned
                  ? groupColor
                  : tokens.border.withValues(alpha: 0.2),
              width: 2,
            ),
          );

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: border),
          padding: const EdgeInsets.all(AtriarchSpacing.md),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nodeLabel,
                    style: AtriarchText.labelTiny(
                      color: assigned
                          ? groupColor
                          : tokens.textTertiary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    groupLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: assigned
                              ? tokens.textPrimary
                              : tokens.textTertiary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  if (targetIds.isNotEmpty)
                    _CollapsedLabels(
                      targetIds: targetIds,
                      resolver: resolver,
                      tokens: tokens,
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        assigned ? 'ASSIGNED' : 'STANDBY',
                        style: AtriarchText.labelTiny(
                          color: tokens.textTertiary,
                        ),
                      ),
                      Container(
                        width: 24,
                        height: 3,
                        color: assigned
                            ? groupColor
                            : tokens.border.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                ],
              ),
              if (assigned)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.check_circle,
                    size: 14,
                    color: groupColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsed unit-label row — single line, bounded by available width.
///
/// Strategy: render up to [_kMaxVisible] labels in a single [Row] of
/// [Flexible] items. If there are more targets than [_kMaxVisible], append a
/// `…` chip so the user knows there are hidden labels (visible on expand).
/// Each label is [Flexible] so long custom names truncate with ellipsis rather
/// than expanding the card. A single-line [Row] has a fixed line-height that
/// is always well within the grid cell's vertical budget, eliminating the
/// RenderFlex overflow errors that occurred with a multi-line [Wrap] under
/// narrow grid widths (≈160px cells on a 320px viewport).
class _CollapsedLabels extends StatelessWidget {
  /// Max labels shown before the `…` ellipsis chip. 3 keeps the row readable
  /// at the narrowest expected grid cell (~136px usable width).
  static const int _kMaxVisible = 3;

  final List<int> targetIds;
  final TargetNameResolver resolver;
  final AtriarchTokens tokens;

  const _CollapsedLabels({
    required this.targetIds,
    required this.resolver,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasOverflow = targetIds.length > _kMaxVisible;
    final visibleIds =
        hasOverflow ? targetIds.sublist(0, _kMaxVisible) : targetIds;

    final labelStyle = AtriarchText.labelTiny(color: tokens.textPrimary);

    // Build alternating label + separator children. Each label is Flexible so
    // the Row distributes remaining width rather than overflowing.
    final rowChildren = <Widget>[];
    for (int i = 0; i < visibleIds.length; i++) {
      if (i > 0) {
        rowChildren.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('·', style: labelStyle),
          ),
        );
      }
      rowChildren.add(
        Flexible(
          child: Text(
            resolver.display(visibleIds[i]),
            style: labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    if (hasOverflow) {
      rowChildren.add(
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text('…', style: labelStyle),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: rowChildren,
    );
  }
}
