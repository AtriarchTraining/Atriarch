import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../util/target_name_resolver.dart';
import 'tactical/tactical_section.dart';

/// Modal bottom-sheet content for managing a single group's target
/// assignments. Three sections (IN THIS GROUP / AVAILABLE / ASSIGNED
/// ELSEWHERE). Empty sections hide entirely. State is owned by the parent;
/// this widget is pure presentation + tap dispatch.
class GroupTargetSheet extends StatelessWidget {
  final int groupIndex; // 0-based
  final List<int> thisGroupIds;
  final List<int> assignedElsewhereIds;
  final Map<int, int> targetIdToGroupIndex; // for ASSIGNED ELSEWHERE rows
  final ValueChanged<int> onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int targetId, int fromGroupIndex) onMove;

  const GroupTargetSheet({
    super.key,
    required this.groupIndex,
    required this.thisGroupIds,
    required this.assignedElsewhereIds,
    required this.targetIdToGroupIndex,
    required this.onAdd,
    required this.onRemove,
    required this.onMove,
  });

  String _groupLabel(int index) =>
      'GROUP ${(index + 1).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final state = context.watch<AppState>();
    final resolver = TargetNameResolver(state.targetNames);

    final availableIds = state.targets
        .where((t) =>
            t.isOnline &&
            !thisGroupIds.contains(t.id) &&
            !assignedElsewhereIds.contains(t.id))
        .map((t) => t.id)
        .toList();

    final sections = <Widget>[];

    if (thisGroupIds.isNotEmpty) {
      sections.add(TacticalSection(
        code: 'IN THIS GROUP',
        trailing: _groupLabel(groupIndex),
      ));
      for (final id in thisGroupIds) {
        sections.add(_TargetRow(
          label: resolver.display(id),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: tokens.statusViolation,
            onPressed: () => onRemove(id),
          ),
          onTap: null,
        ));
      }
      sections.add(const SizedBox(height: AtriarchSpacing.md));
    }

    if (availableIds.isNotEmpty) {
      sections.add(const TacticalSection(code: 'AVAILABLE'));
      for (final id in availableIds) {
        sections.add(_TargetRow(
          label: resolver.display(id),
          trailing: null,
          onTap: () => onAdd(id),
        ));
      }
      sections.add(const SizedBox(height: AtriarchSpacing.md));
    }

    if (assignedElsewhereIds.isNotEmpty) {
      sections.add(const TacticalSection(code: 'ASSIGNED ELSEWHERE'));
      for (final id in assignedElsewhereIds) {
        final from = targetIdToGroupIndex[id];
        sections.add(_TargetRow(
          label: resolver.display(id),
          trailing: from == null
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AtriarchSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: tokens.groupColor(from + 1)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    _groupLabel(from),
                    style: AtriarchText.labelTiny(
                      color: tokens.groupColor(from + 1),
                    ),
                  ),
                ),
          onTap: from == null ? null : () => onMove(id, from),
        ));
      }
      sections.add(const SizedBox(height: AtriarchSpacing.md));
    }

    final bodyChildren = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AtriarchSpacing.lg,
          AtriarchSpacing.md,
          AtriarchSpacing.lg,
          AtriarchSpacing.sm,
        ),
        child: Text(
          '${_groupLabel(groupIndex)} — TARGETS',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
        ),
      ),
    ];

    if (sections.isEmpty) {
      bodyChildren.add(Padding(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        child: Text(
          'NO ONLINE TARGETS',
          style: AtriarchText.labelTiny(color: tokens.textTertiary),
        ),
      ));
    } else {
      bodyChildren.addAll(sections);
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: bodyChildren,
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _TargetRow({required this.label, required this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AtriarchSpacing.lg,
          vertical: AtriarchSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                    ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
