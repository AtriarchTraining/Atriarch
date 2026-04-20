import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';
import 'tactical_card.dart';

class TacticalHudTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? accent;

  const TacticalHudTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      padding: const EdgeInsets.all(AtriarchSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AtriarchText.labelTiny(color: tokens.textTertiary),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: accent ?? tokens.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!.toUpperCase(),
                  style: AtriarchText.labelTiny(color: tokens.textTertiary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
