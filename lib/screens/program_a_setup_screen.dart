import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/drill_config.dart';
import '../models/drill_template.dart';
import '../models/target_group.dart';
import '../models/target_unit.dart';
import '../repositories/drill_template_repository.dart';
import '../services/config_hasher.dart';
import '../services/preferences_repository.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../util/target_name_resolver.dart';
import '../widgets/preset_chip_strip.dart';
import '../widgets/shooter_chip.dart';
import '../widgets/tactical/arming_failed_banner.dart';
import '../widgets/tactical/group_node_card.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_min_max_card.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import '../widgets/tactical/tactical_status_chip.dart';
import '../widgets/tactical/tactical_stepper.dart';
import '../widgets/tactical/target_node_chip.dart';
import '../widgets/group_target_sheet.dart';
import '../widgets/target_actions_sheet.dart';
import 'drill_running_screen.dart';
import 'shooter_picker_screen.dart';

class ProgramASetupScreen extends StatefulWidget {
  const ProgramASetupScreen({super.key});

  @override
  State<ProgramASetupScreen> createState() => _ProgramASetupScreenState();
}

class _ProgramASetupScreenState extends State<ProgramASetupScreen> {
  final startMinCtrl = TextEditingController(text: '1.00');
  final startMaxCtrl = TextEditingController(text: '3.00');
  final delayMinCtrl = TextEditingController(text: '0.50');
  final delayMaxCtrl = TextEditingController(text: '2.00');
  final hitsMinCtrl = TextEditingController(text: '1');
  final hitsMaxCtrl = TextEditingController(text: '3');
  final iterCtrl = TextEditingController(text: '5');

  List<TargetGroup> groups = List.generate(5, (i) => TargetGroup(id: i + 1));
  int? selectedGroupIndex;
  DrillConfig? _lastConfig;
  AppState? _boundState;
  DrillTemplate? _selectedTemplate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().resetDrillPhase();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      _boundState = state;
      state.addListener(_onPhaseChanged);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      final seeded = state.buildSeededGroups();
      setState(() {
        groups = seeded.isNotEmpty
            ? seeded
            : List.generate(5, (i) => TargetGroup(id: i + 1));
      });
    });
  }

  @override
  void dispose() {
    _boundState?.removeListener(_onPhaseChanged);
    _boundState = null;
    super.dispose();
  }

  void _onPhaseChanged() {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.phase == DrillPhase.running) {
      // See ProgramBSetupScreen for why we detach before navigating: during
      // the ~300ms pushReplacement animation, Setup is still listening and
      // phase is still `running`, so every HIT/DONE notifyListeners would
      // re-fire this and stack duplicate Running screens.
      state.removeListener(_onPhaseChanged);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DrillRunningScreen()),
      );
    } else {
      setState(() {});
    }
  }

  DrillConfig? _buildConfig() {
    final state = context.read<AppState>();
    final activeGroups = groups.where((g) => g.targetIds.isNotEmpty).toList();
    if (activeGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assign at least one target to a group.'),
        ),
      );
      return null;
    }

    final noShootIds = state.targets
        .where((t) => t.isOnline && t.isNoShoot)
        .map((t) => t.id)
        .toList();

    return DrillConfig(
      programType: ProgramType.programA,
      startMin: double.tryParse(startMinCtrl.text) ?? 1.0,
      startMax: double.tryParse(startMaxCtrl.text) ?? 3.0,
      delayMin: double.tryParse(delayMinCtrl.text) ?? 0.5,
      delayMax: double.tryParse(delayMaxCtrl.text) ?? 2.0,
      hitsMin: int.tryParse(hitsMinCtrl.text) ?? 1,
      hitsMax: int.tryParse(hitsMaxCtrl.text) ?? 3,
      groups: groups,
      noShootIds: noShootIds,
      iterations: int.tryParse(iterCtrl.text) ?? 5,
    );
  }

  Future<void> _startDrill() async {
    final prefs = context.read<PreferencesRepository>();
    if (_selectedTemplate != null) {
      await prefs.setDefaultPresetId(_selectedTemplate!.id);
    }
    if (!mounted) return;
    final config = _buildConfig();
    if (config == null) return;
    _lastConfig = config;
    context.read<AppState>().startDrill(config);
  }

  void _retryDrill() {
    final state = context.read<AppState>();
    state.resetDrillPhase();
    final config = _lastConfig ?? _buildConfig();
    if (config == null) return;
    state.startDrill(config);
  }

  void _addToGroup(int targetId, int groupIndex) {
    final prevGroupIndex = groups.indexWhere(
      (g) => g.targetIds.contains(targetId),
    ); // -1 if unassigned
    setState(() {
      for (final g in groups) {
        g.targetIds.remove(targetId);
      }
      groups[groupIndex].targetIds.add(targetId);
    });
    _showUndoSnackBar(
      message: 'Target T/U_${targetId.toString().padLeft(2, '0')} added to '
          'GROUP ${(groupIndex + 1).toString().padLeft(2, '0')}',
      onUndo: () {
        setState(() {
          groups[groupIndex].targetIds.remove(targetId);
          if (prevGroupIndex != -1) {
            groups[prevGroupIndex].targetIds.remove(targetId); // idempotent
            groups[prevGroupIndex].targetIds.add(targetId);
          }
        });
      },
    );
  }

  void _removeFromGroup(int targetId, int groupIndex) {
    setState(() {
      groups[groupIndex].targetIds.remove(targetId);
    });
    _showUndoSnackBar(
      message: 'Target T/U_${targetId.toString().padLeft(2, '0')} removed '
          'from GROUP ${(groupIndex + 1).toString().padLeft(2, '0')}',
      onUndo: () {
        setState(() {
          groups[groupIndex].targetIds.remove(targetId); // idempotent
          groups[groupIndex].targetIds.add(targetId);
        });
      },
    );
  }

  void _moveBetweenGroups(
      int targetId, int fromGroupIndex, int toGroupIndex) {
    setState(() {
      groups[fromGroupIndex].targetIds.remove(targetId);
      groups[toGroupIndex].targetIds.add(targetId);
    });
    _showUndoSnackBar(
      message: 'Target T/U_${targetId.toString().padLeft(2, '0')} moved from '
          'GROUP ${(fromGroupIndex + 1).toString().padLeft(2, '0')} to '
          'GROUP ${(toGroupIndex + 1).toString().padLeft(2, '0')}',
      onUndo: () {
        setState(() {
          groups[toGroupIndex].targetIds.remove(targetId); // idempotent: ensure not present
          groups[fromGroupIndex].targetIds.remove(targetId); // idempotent
          groups[fromGroupIndex].targetIds.add(targetId);
        });
      },
    );
  }

  void _showUndoSnackBar({
    required String message,
    required VoidCallback onUndo,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: onUndo,
        ),
      ),
    );
  }

  Future<void> _openGroupSheet(int groupIndex) async {
    final thisGroupIds = List<int>.from(groups[groupIndex].targetIds);
    final assignedElsewhereIds = <int>[];
    final targetIdToGroupIndex = <int, int>{};
    for (var gi = 0; gi < groups.length; gi++) {
      if (gi == groupIndex) continue;
      for (final tid in groups[gi].targetIds) {
        assignedElsewhereIds.add(tid);
        targetIdToGroupIndex[tid] = gi;
      }
    }
    final state = context.read<AppState>();
    // Filter ASSIGNED ELSEWHERE to online targets only (mirrors AVAILABLE).
    final onlineIds = state.targets
        .where((t) => t.isOnline)
        .map((t) => t.id)
        .toSet();
    assignedElsewhereIds.removeWhere((id) => !onlineIds.contains(id));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: state,
        child: _PhaseAwareSheet(
          child: GroupTargetSheet(
            groupIndex: groupIndex,
            thisGroupIds: thisGroupIds,
            assignedElsewhereIds: assignedElsewhereIds,
            targetIdToGroupIndex: targetIdToGroupIndex,
            onAdd: (id) => _addToGroup(id, groupIndex),
            onRemove: (id) => _removeFromGroup(id, groupIndex),
            onMove: (id, from) => _moveBetweenGroups(id, from, groupIndex),
          ),
        ),
      ),
    );
  }

  void _assignTargetToGroup(int targetId) {
    if (selectedGroupIndex == null) return;
    _addToGroup(targetId, selectedGroupIndex!);
  }

  void _removeTargetFromGroup(int groupIndex, int targetId) {
    _removeFromGroup(targetId, groupIndex);
  }

  DrillConfig _currentConfigSnapshot() {
    final state = context.read<AppState>();
    final noShootIds = state.targets
        .where((t) => t.isOnline && t.isNoShoot)
        .map((t) => t.id)
        .toList();
    return DrillConfig(
      programType: ProgramType.programA,
      startMin: double.tryParse(startMinCtrl.text) ?? 1.0,
      startMax: double.tryParse(startMaxCtrl.text) ?? 3.0,
      delayMin: double.tryParse(delayMinCtrl.text) ?? 0.5,
      delayMax: double.tryParse(delayMaxCtrl.text) ?? 2.0,
      hitsMin: int.tryParse(hitsMinCtrl.text) ?? 1,
      hitsMax: int.tryParse(hitsMaxCtrl.text) ?? 3,
      groups: groups,
      noShootIds: noShootIds,
      iterations: int.tryParse(iterCtrl.text) ?? 5,
    );
  }

  void _applyPreset(DrillTemplate template) {
    final cfg = template.config;
    setState(() {
      startMinCtrl.text = cfg.startMin.toStringAsFixed(2);
      startMaxCtrl.text = cfg.startMax.toStringAsFixed(2);
      delayMinCtrl.text = cfg.delayMin.toStringAsFixed(2);
      delayMaxCtrl.text = cfg.delayMax.toStringAsFixed(2);
      hitsMinCtrl.text = cfg.hitsMin.toString();
      hitsMaxCtrl.text = cfg.hitsMax.toString();
      iterCtrl.text = cfg.iterations.toString();
      // Load group allocation if present.
      if (cfg.groups.isNotEmpty) {
        final loaded = <TargetGroup>[];
        for (var i = 0; i < 5; i++) {
          final src = i < cfg.groups.length ? cfg.groups[i] : null;
          loaded.add(
            TargetGroup(
              id: i + 1,
              targetIds: src != null ? List<int>.from(src.targetIds) : <int>[],
            ),
          );
        }
        groups = loaded;
      }
    });
  }

  Future<void> _promptSavePresetName() async {
    final state = context.read<AppState>();
    final repo = state.drillTemplates;
    if (repo == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Save preset'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Preset name',
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(
                controller.text.trim(),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    final config = _currentConfigSnapshot();
    final template = DrillTemplate(
      id: const Uuid().v4(),
      shooterId: null, // app-wide preset (gate-2 save flow)
      name: name,
      programType: ProgramType.programA,
      config: config,
      configHash: ConfigHasher.hash(config),
      createdAt: DateTime.now(),
    );
    await repo.insert(template);
    if (mounted) setState(() {});
  }

  void _openTargetActions(BuildContext context, int targetId) {
    final state = context.read<AppState>();
    final target = state.targets.firstWhere(
      (t) => t.id == targetId,
      orElse: () => TargetUnit(id: targetId, isOnline: false),
    );
    final resolver = TargetNameResolver(state.targetNames);
    final isRemoved = state.removedTargetIds.contains(targetId);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => TargetActionsSheet(
        target: target,
        resolver: resolver,
        isRemoved: isRemoved,
        onIdentify: () => state.identifyTarget(targetId),
        onRenameSaved: (name) => state.setTargetName(targetId, name),
        onToggleNoShoot: () => setState(() {
          target.isNoShoot = !target.isNoShoot;
        }),
        onRemoveConfirmed: () => state.markTargetRemoved(targetId),
        onRestoreConfirmed: () => state.unmarkTargetRemoved(targetId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'PROGRAM_CONFIG',
      trailing: Consumer<AppState>(
        builder: (_, state, __) {
          final online = state.targets.where((t) => t.isOnline).length;
          final drillLive = state.phase == DrillPhase.arming ||
              state.phase == DrillPhase.running ||
              state.phase == DrillPhase.stopping;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TacticalStatusChip(
                color: online > 0 ? tokens.statusLive : tokens.statusOffline,
                label: online > 0 ? 'live' : 'offline',
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: tokens.textSecondary),
                color: tokens.bgElevated,
                onSelected: (value) {
                  if (value == 'scan') {
                    state.resetDrillPhase();
                    state.discoverTargets();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'scan',
                    enabled: !drillLive,
                    child: Text(
                      'Scan for targets',
                      style: TextStyle(color: tokens.textPrimary),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      body: ListView(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: ShooterChip(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ShooterPickerScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          _header(context),
          const SizedBox(height: AtriarchSpacing.md),
          PresetChipStrip(
            drillTemplates: context.read<DrillTemplateRepository>(),
            preferences: context.read<PreferencesRepository>(),
            onLoad: (t) {
              _applyPreset(t);
              setState(() => _selectedTemplate = t);
            },
            onSave: _promptSavePresetName,
            onSelectionChanged: (t) => setState(() => _selectedTemplate = t),
          ),
          const SizedBox(height: AtriarchSpacing.lg),
          const TacticalSection(code: 'PARAM_01', trailing: 'TIMING'),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalMinMaxCard(
            title: 'START DELAY',
            rangeHint: '0.00 – 10.00 SEC',
            minController: startMinCtrl,
            maxController: startMaxCtrl,
            step: 0.25,
            unit: 'sec',
            min: 0,
            max: 10,
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalMinMaxCard(
            title: 'TIME BETWEEN ACTIVATIONS',
            rangeHint: '0.00 – 10.00 SEC',
            minController: delayMinCtrl,
            maxController: delayMaxCtrl,
            step: 0.25,
            unit: 'sec',
            min: 0,
            max: 10,
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalMinMaxCard(
            title: 'REQUIRED HITS',
            rangeHint: '1 – 20',
            minController: hitsMinCtrl,
            maxController: hitsMaxCtrl,
            step: 1,
            unit: 'hits',
            min: 1,
            max: 20,
            integer: true,
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(code: 'PARAM_02', trailing: 'ITERATIONS'),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalCard(
            accent: tokens.statusHit,
            child: TacticalStepper(
              controller: iterCtrl,
              label: 'iterations per group',
              unit: 'count',
              step: 1,
              min: 1,
              max: 50,
              integer: true,
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(
            code: 'PARAM_03',
            trailing: 'ALLOCATION_GRID',
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          Builder(
            builder: (context) {
              final resolver = TargetNameResolver(
                context.read<AppState>().targetNames,
              );
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AtriarchSpacing.sm,
                crossAxisSpacing: AtriarchSpacing.sm,
                childAspectRatio: 1.6,
                children: List.generate(
                  groups.length,
                  (i) => GestureDetector(
                    onLongPress: () {
                      if (groups[i].targetIds.isEmpty) return;
                      _openTargetActions(
                        context,
                        groups[i].targetIds.first,
                      );
                    },
                    child: GroupNodeCard(
                      groupIndex: i,
                      targetIds: groups[i].targetIds,
                      selected: selectedGroupIndex == i,
                      resolver: resolver,
                      onTap: () {
                        setState(() => selectedGroupIndex = i);
                        _openGroupSheet(i);
                      },
                      onRemoveTarget: (id) => _removeTargetFromGroup(i, id),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(
            code: 'PARAM_04',
            trailing: 'AVAILABLE_NODES',
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          Consumer<AppState>(
            builder: (_, state, __) {
              final assigned = groups.expand((g) => g.targetIds).toSet();
              final unassigned = state.targets
                  .where((t) => t.isOnline && !assigned.contains(t.id))
                  .toList();
              if (unassigned.isEmpty) {
                return Text(
                  'ALL NODES ASSIGNED',
                  style: AtriarchText.labelTiny(color: tokens.textTertiary),
                );
              }
              return Wrap(
                spacing: AtriarchSpacing.sm,
                runSpacing: AtriarchSpacing.sm,
                children: unassigned
                    .map(
                      (t) => GestureDetector(
                        onLongPress: () =>
                            _openTargetActions(context, t.id),
                        child: TargetNodeChip(
                          target: t,
                          onTap: () => _assignTargetToGroup(t.id),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          Consumer<AppState>(
            builder: (_, state, __) {
              if (state.phase == DrillPhase.armingFailed) {
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: AtriarchSpacing.md,
                  ),
                  child: TacticalArmingFailedBanner(onRetry: _retryDrill),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Consumer<AppState>(
            builder: (_, state, __) {
              final arming = state.phase == DrillPhase.arming;
              return TacticalPrimaryButton(
                label: arming ? 'arming' : 'commit // start drill',
                icon: arming ? null : Icons.bolt,
                variant: arming
                    ? TacticalButtonVariant.loading
                    : TacticalButtonVariant.primary,
                onPressed: _startDrill,
              );
            },
          ),
          const SizedBox(height: AtriarchSpacing.xxl),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final tokens = context.atriarch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PROTOCOL_STATUS',
          style: AtriarchText.labelTiny(color: tokens.textTertiary),
        ),
        const SizedBox(height: 4),
        Text(
          'PROGRAM A / GROUP MODE',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ],
    );
  }
}

class _PhaseAwareSheet extends StatefulWidget {
  final Widget child;
  const _PhaseAwareSheet({required this.child});

  @override
  State<_PhaseAwareSheet> createState() => _PhaseAwareSheetState();
}

class _PhaseAwareSheetState extends State<_PhaseAwareSheet> {
  late final VoidCallback _listener;
  late final AppState _state;
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _listener = () {
      if (_state.phase != DrillPhase.idle && mounted) {
        final route = _route;
        if (route != null && route.isActive) {
          Navigator.of(context).removeRoute(route);
        }
      }
    };
    _state.addListener(_listener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
  }

  @override
  void dispose() {
    _state.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

