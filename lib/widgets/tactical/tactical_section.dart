import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class TacticalSection extends StatelessWidget {
  final String code;
  final String? trailing;

  const TacticalSection({
    super.key,
    required this.code,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AtriarchSpacing.sm),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: tokens.bgCard,
              border: Border.all(
                color: tokens.textTertiary.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Text(
              code.toUpperCase(),
              style: AtriarchText.labelTiny(color: tokens.textTertiary),
            ),
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          Expanded(
            child: Container(
              height: 1,
              color: tokens.border.withValues(alpha: 0.3),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AtriarchSpacing.sm),
            Text(
              trailing!.toUpperCase(),
              style: AtriarchText.labelTiny(color: tokens.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
