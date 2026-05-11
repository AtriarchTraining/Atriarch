import 'package:flutter/material.dart';

import '../../theme/atriarch_theme.dart';

/// Horizontal scrollable chip list of persistent target groups, plus a
/// trailing `+ Add group` action chip.
///
/// Tap on a group chip fires [onRenameGroup]. The screen is responsible for
/// presenting a rename/delete dialog. [onDeleteGroup] is exposed for that
/// dialog's delete action.
class GroupChipRow extends StatelessWidget {
  final List<int> groupOrder;
  final Map<int, String> labels;
  final VoidCallback onAddGroup;
  final void Function(int groupNumber) onRenameGroup;
  final void Function(int groupNumber) onDeleteGroup;

  const GroupChipRow({
    super.key,
    required this.groupOrder,
    required this.labels,
    required this.onAddGroup,
    required this.onRenameGroup,
    required this.onDeleteGroup,
  });

  String _chipLabel(int groupNumber) {
    final label = labels[groupNumber];
    return (label == null || label.isEmpty)
        ? 'G$groupNumber'
        : 'G$groupNumber: $label';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groupOrder.length + 1,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AtriarchSpacing.sm),
        itemBuilder: (context, i) {
          if (i == groupOrder.length) {
            return ActionChip(
              label: const Text('+ Add group'),
              onPressed: onAddGroup,
            );
          }
          final g = groupOrder[i];
          return InputChip(
            label: Text(_chipLabel(g)),
            onPressed: () => onRenameGroup(g),
            backgroundColor: tokens.bgCard,
          );
        },
      ),
    );
  }
}
