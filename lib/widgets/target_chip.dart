import 'package:flutter/material.dart';
import '../models/target_unit.dart';

class TargetChip extends StatelessWidget {
  final TargetUnit target;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TargetChip({
    super.key,
    required this.target,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Chip(
        label: Text('T${target.id}'),
        backgroundColor: _color(),
        side: selected ? const BorderSide(color: Colors.blue, width: 2) : null,
      ),
    );
  }

  Color _color() {
    if (!target.isOnline) return Colors.grey.shade300;
    if (target.isNoShoot) return Colors.red.shade100;
    if (target.groupId != null) return Colors.green.shade100;
    return Colors.white;
  }
}
