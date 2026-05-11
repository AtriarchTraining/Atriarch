import 'package:flutter/material.dart';

import '../../theme/atriarch_theme.dart';
import 'group_picker.dart';

class TargetRow extends StatelessWidget {
  final int targetId;
  final String? displayName;
  final bool isOnline;
  final int? currentGroup;
  final List<int> groupOrder;
  final Map<int, String> labels;
  final void Function(int? groupNumber) onSelectGroup;
  final Future<int> Function() onCreateNewGroup;
  final VoidCallback onFlash;

  const TargetRow({
    super.key,
    required this.targetId,
    required this.displayName,
    required this.isOnline,
    required this.currentGroup,
    required this.groupOrder,
    required this.labels,
    required this.onSelectGroup,
    required this.onCreateNewGroup,
    required this.onFlash,
  });

  Widget _subtitle(BuildContext context) {
    final tokens = context.atriarch;
    if (displayName != null && displayName!.isNotEmpty) {
      return Text(
        displayName!,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
      );
    }
    return Text(
      isOnline ? 'online' : 'offline',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isOnline ? tokens.textSecondary : tokens.textTertiary,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AtriarchSpacing.sm),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: isOnline ? tokens.statusLive : tokens.textTertiary,
          ),
          const SizedBox(width: AtriarchSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Target $targetId',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _subtitle(context),
              ],
            ),
          ),
          GroupPicker(
            currentGroup: currentGroup,
            groupOrder: groupOrder,
            labels: labels,
            onSelect: onSelectGroup,
            onCreateNew: onCreateNewGroup,
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          IconButton(
            tooltip: 'Flash LED',
            icon: const Icon(Icons.flash_on),
            onPressed: isOnline ? onFlash : null,
          ),
        ],
      ),
    );
  }
}
