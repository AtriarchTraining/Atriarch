import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drill_config.dart';
import '../models/target_group.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/group_node_card.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_min_max_card.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import '../widgets/tactical/tactical_status_chip.dart';
import '../widgets/tactical/tactical_stepper.dart';
import '../widgets/tactical/target_node_chip.dart';
import 'drill_running_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().resetDrillPhase();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().addListener(_onPhaseChanged);
    });
  }

  @override
  void dispose() {
    try {
      context.read<AppState>().removeListener(_onPhaseChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onPhaseChanged() {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.phase == DrillPhase.running) {
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

  void _startDrill() {
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

  void _assignTargetToGroup(int targetId) {
    if (selectedGroupIndex == null) return;
    setState(() {
      for (final g in groups) {
        g.targetIds.remove(targetId);
      }
      groups[selectedGroupIndex!].targetIds.add(targetId);
    });
  }

  void _removeTargetFromGroup(int groupIndex, int targetId) {
    setState(() {
      groups[groupIndex].targetIds.remove(targetId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'PROGRAM_CONFIG',
      trailing: Consumer<AppState>(
        builder: (_, state, __) {
          final online = state.targets.where((t) => t.isOnline).length;
          return TacticalStatusChip(
            color:
                online > 0 ? tokens.statusLive : tokens.statusOffline,
            label: online > 0 ? 'live' : 'offline',
          );
        },
      ),
      body: ListView(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        children: [
          _header(context),
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
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AtriarchSpacing.sm,
            crossAxisSpacing: AtriarchSpacing.sm,
            childAspectRatio: 1.6,
            children: List.generate(
              5,
              (i) => GroupNodeCard(
                groupIndex: i,
                targetIds: groups[i].targetIds,
                selected: selectedGroupIndex == i,
                onTap: () => setState(() => selectedGroupIndex = i),
                onRemoveTarget: (id) => _removeTargetFromGroup(i, id),
              ),
            ),
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
                      (t) => TargetNodeChip(
                        target: t,
                        onTap: () => _assignTargetToGroup(t.id),
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
                  child: _ArmingFailedBanner(onRetry: _retryDrill),
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

class _ArmingFailedBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _ArmingFailedBanner({required this.onRetry});

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
