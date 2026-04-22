import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';
import 'tactical_card.dart';

/// Banner shown when the transmitter does not respond during drill arming.
/// Used by Program A and Program B setup screens.
class TacticalArmingFailedBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const TacticalArmingFailedBanner({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      accent: tokens.statusViolation,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: tokens.statusViolation),
          const SizedBox(width: AtriarchSpacing.md),
          Expanded(
            child: Text(
              'NO RESPONSE FROM TRANSMITTER // CHECK CONNECTION',
              style: AtriarchText.labelTiny(color: tokens.textPrimary),
            ),
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          Semantics(
            button: true,
            label: 'Retry starting the drill',
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('RETRY'),
            ),
          ),
        ],
      ),
    );
  }
}
