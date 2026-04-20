import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class TacticalCard extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? background;

  const TacticalCard({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(AtriarchSpacing.md),
    this.onTap,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? tokens.bgCard,
        border: accent != null
            ? Border(left: BorderSide(color: accent!, width: 2))
            : null,
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: content,
      ),
    );
  }
}
