import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/target_unit.dart';
import '../theme/atriarch_theme.dart';
import '../util/target_name_resolver.dart';

/// Long-press action sheet for a [TargetChip] (addendum §4.B).
///
/// Four rows:
///   - Identify (flash LED)
///   - Rename (opens a dialog)
///   - Toggle No-Shoot (shows current state)
///   - Remove from fleet (or Restore to fleet when the target is soft-deleted)
///
/// The sheet is intentionally dumb — it receives the [target], a
/// [resolver] for the current display name, an [isRemoved] flag, and
/// callbacks. The caller wires those callbacks to `AppState`. This keeps
/// the widget testable without provider.
class TargetActionsSheet extends StatelessWidget {
  final TargetUnit target;
  final TargetNameResolver resolver;
  final bool isRemoved;
  final VoidCallback onIdentify;
  final ValueChanged<String?> onRenameSaved;
  final VoidCallback onToggleNoShoot;
  final VoidCallback onRemoveConfirmed;
  final VoidCallback onRestoreConfirmed;

  const TargetActionsSheet({
    super.key,
    required this.target,
    required this.resolver,
    required this.onIdentify,
    required this.onRenameSaved,
    required this.onToggleNoShoot,
    required this.onRemoveConfirmed,
    required this.onRestoreConfirmed,
    this.isRemoved = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final displayName = resolver.display(target.id);
    final noShootLabel =
        target.isNoShoot ? 'currently ON' : 'currently OFF';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AtriarchSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AtriarchSpacing.lg,
                AtriarchSpacing.md,
                AtriarchSpacing.lg,
                AtriarchSpacing.sm,
              ),
              child: Text(
                displayName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            _ActionRow(
              icon: Icons.lightbulb_outline,
              label: 'Identify (flash LED)',
              onTap: () {
                HapticFeedback.selectionClick();
                onIdentify();
                Navigator.of(context).pop();
              },
            ),
            _ActionRow(
              icon: Icons.edit,
              label: 'Rename',
              onTap: () async {
                final result = await _showRenameDialog(context, displayName);
                if (!context.mounted) return;
                if (result != null) {
                  // result.value: trimmed string or null-sentinel for revert.
                  onRenameSaved(result.value);
                  Navigator.of(context).pop();
                }
              },
            ),
            _ActionRow(
              icon: Icons.block,
              label: 'Toggle No-Shoot ($noShootLabel)',
              onTap: () {
                HapticFeedback.selectionClick();
                onToggleNoShoot();
                Navigator.of(context).pop();
              },
            ),
            if (isRemoved)
              _ActionRow(
                icon: Icons.restore_from_trash,
                label: 'Restore to fleet',
                onTap: () async {
                  final confirmed = await _confirmRestore(context, displayName);
                  if (!context.mounted) return;
                  if (confirmed == true) {
                    onRestoreConfirmed();
                    Navigator.of(context).pop();
                  }
                },
              )
            else
              _ActionRow(
                icon: Icons.delete_outline,
                label: 'Remove from fleet',
                destructive: true,
                onTap: () async {
                  final confirmed = await _confirmRemove(context, displayName);
                  if (!context.mounted) return;
                  if (confirmed == true) {
                    onRemoveConfirmed();
                    Navigator.of(context).pop();
                  }
                },
              ),
            const SizedBox(height: AtriarchSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<_RenameResult?> _showRenameDialog(
    BuildContext context,
    String currentDisplayName,
  ) {
    // Pre-fill with the custom name if one is saved; leave blank when the
    // user is running on the `T{id}` fallback so they're editing their name,
    // not the placeholder.
    final initial = resolver.customName(target.id) ?? '';
    final controller = TextEditingController(text: initial);
    return showDialog<_RenameResult>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Rename $currentDisplayName'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'Leave blank to reset',
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                Navigator.of(dialogContext).pop(
                  _RenameResult(trimmed.isEmpty ? null : trimmed),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmRemove(BuildContext context, String displayName) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove target?'),
          content: Text(
            'Remove $displayName from the fleet? Hidden from UI until you '
            'tap Show Removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmRestore(BuildContext context, String displayName) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Restore target?'),
          content: Text('Restore $displayName to the fleet?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );
  }
}

/// Wraps the optional rename result so the caller can distinguish between
/// "user cancelled" (null outer) and "user confirmed with empty field" (non-null
/// outer, null inner value → revert to `T{id}`).
class _RenameResult {
  final String? value;
  const _RenameResult(this.value);
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final color = destructive ? tokens.statusViolation : tokens.textPrimary;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AtriarchSpacing.lg,
            vertical: AtriarchSpacing.md,
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: AtriarchSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
