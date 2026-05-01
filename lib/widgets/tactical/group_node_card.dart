import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';
import '../../util/target_name_resolver.dart';

class GroupNodeCard extends StatelessWidget {
  final int groupIndex; // 0-based
  final List<int> targetIds;
  final bool selected;
  final bool expanded;
  final TargetNameResolver resolver;
  final VoidCallback onTap;
  final ValueChanged<int> onRemoveTarget;

  const GroupNodeCard({
    super.key,
    required this.groupIndex,
    required this.targetIds,
    required this.selected,
    required this.expanded,
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
                  const SizedBox(height: AtriarchSpacing.md),
                  if (targetIds.isNotEmpty)
                    expanded
                        ? Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: targetIds
                                .map(
                                  (id) => InputChip(
                                    label: Text(resolver.display(id)),
                                    onDeleted: () => onRemoveTarget(id),
                                    deleteIcon: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: tokens.statusViolation,
                                    ),
                                  ),
                                )
                                .toList(),
                          )
                        : Wrap(
                            spacing: AtriarchSpacing.sm,
                            runSpacing: 4,
                            children: targetIds
                                .map(
                                  (id) => Text(
                                    resolver.display(id),
                                    style: AtriarchText.labelTiny(
                                      color: tokens.textPrimary,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  const SizedBox(height: AtriarchSpacing.sm),
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
