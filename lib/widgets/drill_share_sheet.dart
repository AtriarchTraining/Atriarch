import 'package:flutter/material.dart';

import '../theme/atriarch_theme.dart';

/// Bottom sheet launched from the Results AppBar (addendum §4.D+F).
///
/// Two rows:
///  - "Share result image"  → calls [onShareImage]
///  - "Export drill log (JSON)" → calls [onExportJson]
///
/// Both rows close the sheet before firing their callback so the caller
/// can push a share_plus intent without stacking modals.
class DrillShareSheet extends StatelessWidget {
  final VoidCallback onShareImage;
  final VoidCallback onExportJson;

  const DrillShareSheet({
    super.key,
    required this.onShareImage,
    required this.onExportJson,
  });

  /// Convenience wrapper that handles the modal plumbing — screens just
  /// pass the two callbacks and get a semantics-labelled sheet.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onShareImage,
    required VoidCallback onExportJson,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => DrillShareSheet(
        onShareImage: onShareImage,
        onExportJson: onExportJson,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AtriarchSpacing.md,
          AtriarchSpacing.sm,
          AtriarchSpacing.md,
          AtriarchSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AtriarchSpacing.sm,
                top: AtriarchSpacing.sm,
                bottom: AtriarchSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DRILL_SHARE',
                    style: AtriarchText.labelTiny(color: tokens.statusHit),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SHARE DRILL',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.4,
                        ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.ios_share, color: tokens.statusHit),
              title: const Text('Share result image'),
              subtitle: const Text('for student'),
              onTap: () {
                Navigator.of(context).pop();
                onShareImage();
              },
            ),
            ListTile(
              leading: Icon(Icons.article, color: tokens.textSecondary),
              title: const Text('Export drill log (JSON)'),
              subtitle: const Text('for Jeremy'),
              onTap: () {
                Navigator.of(context).pop();
                onExportJson();
              },
            ),
            const SizedBox(height: AtriarchSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
