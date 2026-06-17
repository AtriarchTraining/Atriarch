import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/shooter_state.dart';

class ShooterChip extends StatelessWidget {
  final VoidCallback onTap;
  const ShooterChip({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = context.select<ShooterState, String>(
      (s) => s.current?.displayName ?? 'Unassigned',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ActionChip(
        avatar: const Icon(Icons.person_outline, size: 18),
        label: Text('Firing as: $name'),
        onPressed: onTap,
      ),
    );
  }
}
