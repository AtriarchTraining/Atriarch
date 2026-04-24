import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class TacticalAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? onMenuTap;
  final bool showBack;

  const TacticalAppBar({
    super.key,
    required this.title,
    this.trailing,
    this.onMenuTap,
    this.showBack = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final canPop = Navigator.of(context).canPop();
    final showBackEffective = showBack || canPop;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        border: Border(
          bottom: BorderSide(
            color: tokens.border.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AtriarchSpacing.lg),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              showBackEffective ? Icons.arrow_back : Icons.menu,
              color: tokens.statusHit,
            ),
            onPressed: onMenuTap ??
                (showBackEffective
                    ? () => Navigator.of(context).maybePop()
                    : null),
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(
                    color: tokens.statusHit,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3.2,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
