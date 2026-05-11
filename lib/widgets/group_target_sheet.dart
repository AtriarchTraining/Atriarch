import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../util/target_name_resolver.dart';
import 'tactical/tactical_section.dart';

/// Modal bottom-sheet content for managing a single group's target
/// assignments. Three sections (IN THIS GROUP / AVAILABLE / ASSIGNED
/// ELSEWHERE). Empty sections hide entirely. Maintains local mutable copies
/// of the three list/map props so the sheet rebuilds immediately on every
/// tap, while also notifying the parent via callbacks.
class GroupTargetSheet extends StatefulWidget {
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

  @override
  State<GroupTargetSheet> createState() => _GroupTargetSheetState();
}

class _GroupTargetSheetState extends State<GroupTargetSheet> {
  late List<int> _thisGroupIds;
  late List<int> _assignedElsewhereIds;
  late Map<int, int> _targetIdToGroupIndex;

  @override
  void initState() {
    super.initState();
    _thisGroupIds = List<int>.from(widget.thisGroupIds);
    _assignedElsewhereIds = List<int>.from(widget.assignedElsewhereIds);
    _targetIdToGroupIndex = Map<int, int>.from(widget.targetIdToGroupIndex);
  }

  String _groupLabel(int index) =>
      'GROUP ${(index + 1).toString().padLeft(2, '0')}';

  void _dispatchAdd(int id) {
    setState(() {
      _thisGroupIds.add(id);
      _assignedElsewhereIds.remove(id);
      _targetIdToGroupIndex.remove(id);
    });
    widget.onAdd(id);
  }

  void _dispatchRemove(int id) {
    setState(() {
      _thisGroupIds.remove(id);
    });
    widget.onRemove(id);
  }

  void _dispatchMove(int id, int fromGroupIndex) {
    setState(() {
      _assignedElsewhereIds.remove(id);
      _targetIdToGroupIndex.remove(id);
      _thisGroupIds.add(id);
    });
    widget.onMove(id, fromGroupIndex);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final state = context.watch<AppState>();
    final resolver = TargetNameResolver(state.targetNames);

    final availableIds = state.targets
        .where((t) =>
            t.isOnline &&
            !_thisGroupIds.contains(t.id) &&
            !_assignedElsewhereIds.contains(t.id))
        .map((t) => t.id)
        .toList();

    final sections = <Widget>[];

    if (_thisGroupIds.isNotEmpty) {
      sections.add(TacticalSection(
        code: 'IN THIS GROUP',
        trailing: _groupLabel(widget.groupIndex),
      ));
      for (final id in _thisGroupIds) {
        sections.add(_TargetRow(
          label: resolver.display(id),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: tokens.statusViolation,
            onPressed: () => _dispatchRemove(id),
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
          onTap: () => _dispatchAdd(id),
        ));
      }
      sections.add(const SizedBox(height: AtriarchSpacing.md));
    }

    if (_assignedElsewhereIds.isNotEmpty) {
      sections.add(const TacticalSection(code: 'ASSIGNED ELSEWHERE'));
      for (final id in _assignedElsewhereIds) {
        final from = _targetIdToGroupIndex[id];
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
          onTap: from == null
              ? null
              : () => _handleMoveTap(context, id, from, resolver),
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
          '${_groupLabel(widget.groupIndex)} — TARGETS',
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

  Future<void> _handleMoveTap(
    BuildContext context,
    int targetId,
    int fromGroupIndex,
    TargetNameResolver resolver,
  ) async {
    final state = context.read<AppState>();
    if (state.skipMoveConfirmation) {
      _dispatchMove(targetId, fromGroupIndex);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _MoveConfirmationDialog(
        targetLabel: resolver.display(targetId),
        fromLabel: _groupLabel(fromGroupIndex),
        toLabel: _groupLabel(widget.groupIndex),
      ),
    );
    if (!context.mounted) return;
    if (confirmed == true) {
      _dispatchMove(targetId, fromGroupIndex);
    }
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

class _MoveConfirmationDialog extends StatefulWidget {
  final String targetLabel;
  final String fromLabel;
  final String toLabel;
  const _MoveConfirmationDialog({
    required this.targetLabel,
    required this.fromLabel,
    required this.toLabel,
  });

  @override
  State<_MoveConfirmationDialog> createState() =>
      _MoveConfirmationDialogState();
}

class _MoveConfirmationDialogState extends State<_MoveConfirmationDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('MOVE TARGET'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Move ${widget.targetLabel} from ${widget.fromLabel} to '
            '${widget.toLabel}?',
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _dontShowAgain,
            onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
            title: const Text("Don't show this again"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () async {
            if (_dontShowAgain) {
              await context.read<AppState>().setSkipMoveConfirmation(true);
            }
            if (!context.mounted) return;
            Navigator.of(context).pop(true);
          },
          child: const Text('MOVE'),
        ),
      ],
    );
  }
}
