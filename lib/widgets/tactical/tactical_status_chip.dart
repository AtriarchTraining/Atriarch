import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class TacticalStatusChip extends StatelessWidget {
  final Color color;
  final String label;
  final bool glow;

  const TacticalStatusChip({
    super.key,
    required this.color,
    required this.label,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            boxShadow: glow
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: AtriarchText.labelTiny(color: color),
        ),
      ],
    );
  }
}
