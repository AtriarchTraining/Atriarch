import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/target_setup/group_chip_row.dart';
import '../widgets/target_setup/target_row.dart';

class TargetSetupScreen extends StatefulWidget {
  const TargetSetupScreen({super.key});

  @override
  State<TargetSetupScreen> createState() => _TargetSetupScreenState();
}

class _TargetSetupScreenState extends State<TargetSetupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ignore: discarded_futures
      _runDiscovery();
    });
  }

  Future<void> _runDiscovery() async {
    try {
      await context.read<AppState>().discoverTargets();
    } catch (_) {
      // Silent — online count staying at zero is the signal.
    }
  }

  Future<void> _onWalkTheRange() async {
    await context.read<AppState>().walkTheRange();
  }

  Future<void> _onFlash(BuildContext context, AppState state, int targetId) async {
    final name = state.targetNames[targetId] ?? 'Target $targetId';
    await state.identifyTarget(targetId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Flash sent to $name'),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  Future<void> _renameGroupDialog(BuildContext context, int groupNumber) async {
    final state = context.read<AppState>();
    final controller = TextEditingController(
      text: state.targetGroupLabels[groupNumber] ?? '',
    );
    final result = await showDialog<_GroupDialogResult>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Group $groupNumber'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Label (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
                ctx, const _GroupDialogResult.delete()),
            child: const Text('Delete group'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, _GroupDialogResult.save(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result.isDelete) {
      await state.deleteTargetGroup(groupNumber);
    } else {
      await state.renameTargetGroup(
        groupNumber,
        result.label!.isEmpty ? null : result.label,
      );
    }
  }

  Future<int> _createGroupAndRename(BuildContext context) async {
    final state = context.read<AppState>();
    final number = await state.createTargetGroup();
    if (mounted) {
      await _renameGroupDialog(context, number);
    }
    return number;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'TARGET SETUP',
      body: Padding(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        child: Consumer<AppState>(
          builder: (_, state, __) {
            final total = state.targets.length;
            final online = state.targets.where((t) => t.isOnline).length;
            final denominator = total == 0 ? '?' : total.toString();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(AtriarchSpacing.md),
                  decoration: BoxDecoration(
                    color: tokens.bgCard,
                    borderRadius: BorderRadius.circular(AtriarchRadius.md),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Row(
                    children: [
                      if (state.isScanning)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      else
                        Icon(
                          online > 0 ? Icons.check_circle : Icons.radar,
                          color: online > 0
                              ? tokens.statusLive
                              : tokens.textTertiary,
                        ),
                      const SizedBox(width: AtriarchSpacing.md),
                      Expanded(
                        child: Text(
                          '$online of $denominator targets online',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AtriarchSpacing.lg),
                Text('GROUPS',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: AtriarchSpacing.sm),
                GroupChipRow(
                  groupOrder: state.targetGroupOrder,
                  labels: state.targetGroupLabels,
                  onAddGroup: () => _createGroupAndRename(context),
                  onRenameGroup: (g) => _renameGroupDialog(context, g),
                  onDeleteGroup: (g) => state.deleteTargetGroup(g),
                ),
                const SizedBox(height: AtriarchSpacing.lg),
                Text('TARGETS',
                    style: Theme.of(context).textTheme.labelMedium),
                Expanded(
                  child: state.targets.isEmpty
                      ? Center(
                          child: Text(
                            'No targets discovered yet.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: tokens.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          itemCount: state.targets.length,
                          separatorBuilder: (_, __) => Divider(
                            color: tokens.border,
                            height: 1,
                          ),
                          itemBuilder: (_, i) {
                            final t = state.targets[i];
                            return TargetRow(
                              targetId: t.id,
                              displayName: state.targetNames[t.id],
                              isOnline: t.isOnline,
                              currentGroup:
                                  state.targetGroupAssignments[t.id],
                              groupOrder: state.targetGroupOrder,
                              labels: state.targetGroupLabels,
                              onSelectGroup: (g) =>
                                  state.setTargetGroup(t.id, g),
                              onCreateNewGroup: () =>
                                  _createGroupAndRename(context),
                              onFlash: () => _onFlash(context, state, t.id),
                            );
                          },
                        ),
                ),
                const SizedBox(height: AtriarchSpacing.md),
                TacticalPrimaryButton(
                  label: 'WALK_THE_RANGE',
                  icon: Icons.directions_walk,
                  onPressed: _onWalkTheRange,
                ),
                const SizedBox(height: AtriarchSpacing.sm),
                const TacticalPrimaryButton(
                  label: 'PHOTO_MAP',
                  icon: Icons.photo_camera_outlined,
                  variant: TacticalButtonVariant.disabled,
                ),
                const SizedBox(height: AtriarchSpacing.sm),
                TacticalPrimaryButton(
                  label: 'RESCAN',
                  onPressed: _runDiscovery,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GroupDialogResult {
  final bool isDelete;
  final String? label;
  const _GroupDialogResult.save(this.label) : isDelete = false;
  const _GroupDialogResult.delete()
      : isDelete = true,
        label = null;
}
