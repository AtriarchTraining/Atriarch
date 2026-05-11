import 'package:flutter/material.dart';

/// Per-row group selection menu. Shows the current assignment as a chip
/// label; tapping opens a popup with `None`, every existing group, and
/// `+ New group…` at the bottom. Selecting "New group" awaits
/// [onCreateNew] for the newly minted group number and then calls
/// [onSelect] with it.
class GroupPicker extends StatelessWidget {
  final int? currentGroup;
  final List<int> groupOrder;
  final Map<int, String> labels;
  final void Function(int? groupNumber) onSelect;
  final Future<int> Function() onCreateNew;

  const GroupPicker({
    super.key,
    required this.currentGroup,
    required this.groupOrder,
    required this.labels,
    required this.onSelect,
    required this.onCreateNew,
  });

  static const _newGroupSentinel = -1;
  static const _noneSentinel = -2;

  String _chipLabel(int g) {
    final l = labels[g];
    return (l == null || l.isEmpty) ? 'G$g' : 'G$g: $l';
  }

  String get _currentLabel =>
      currentGroup == null ? 'None' : _chipLabel(currentGroup!);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Assign group',
      child: Chip(
        label: Text(_currentLabel),
        avatar: const Icon(Icons.expand_more, size: 18),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem<int>(
          value: _noneSentinel,
          child: Text('None'),
        ),
        for (final g in groupOrder)
          PopupMenuItem<int>(
            value: g,
            child: Text(_chipLabel(g)),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<int>(
          value: _newGroupSentinel,
          child: Text('+ New group…'),
        ),
      ],
      onSelected: (value) async {
        if (value == _noneSentinel) {
          onSelect(null);
        } else if (value == _newGroupSentinel) {
          final created = await onCreateNew();
          onSelect(created);
        } else {
          onSelect(value);
        }
      },
    );
  }
}
