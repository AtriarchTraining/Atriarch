import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/drill_config.dart';
import '../models/target_group.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/inc_dec.dart';
import '../widgets/target_chip.dart';
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
  final hitsMinCtrl = TextEditingController(text: '1.00');
  final hitsMaxCtrl = TextEditingController(text: '3.00');
  final iterCtrl = TextEditingController(text: '5.00');

  List<TargetGroup> groups = List.generate(5, (i) => TargetGroup(id: i + 1));
  int? selectedGroupIndex;

  DrillConfig? _lastConfig;

  @override
  void initState() {
    super.initState();
    // Reset any residual phase (e.g. armingFailed from a prior attempt).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().resetDrillPhase();
    });
    // Listen for phase transitions so we navigate on arming -> running.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().addListener(_onPhaseChanged);
    });
  }

  @override
  void dispose() {
    // context.read in dispose is fine for listener removal.
    try {
      context.read<AppState>().removeListener(_onPhaseChanged);
    } catch (_) {
      // Widget tree teardown — ignore.
    }
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
      // Re-render START button (ARMING / armingFailed banner).
      setState(() {});
    }
  }

  DrillConfig? _buildConfig() {
    final state = context.read<AppState>();

    final activeGroups = groups.where((g) => g.targetIds.isNotEmpty).toList();
    if (activeGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assign at least one target to a group.')),
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
      hitsMin: (double.tryParse(hitsMinCtrl.text) ?? 1).toInt(),
      hitsMax: (double.tryParse(hitsMaxCtrl.text) ?? 3).toInt(),
      groups: groups,
      noShootIds: noShootIds,
      iterations: (double.tryParse(iterCtrl.text) ?? 5).toInt(),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Program A - Group Mode')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Start Delay (seconds)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(startMinCtrl, 'Min', 0.25),
                IncDec(startMaxCtrl, 'Max', 0.25),
              ],
            ),
            const SizedBox(height: AtriarchSpacing.xl),
            _sectionLabel('Time Between Activations (seconds)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(delayMinCtrl, 'Min', 0.25),
                IncDec(delayMaxCtrl, 'Max', 0.25),
              ],
            ),
            const SizedBox(height: AtriarchSpacing.xl),
            _sectionLabel('Required Hits'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(hitsMinCtrl, 'Min'),
                IncDec(hitsMaxCtrl, 'Max'),
              ],
            ),
            const SizedBox(height: AtriarchSpacing.xl),
            _sectionLabel('Iterations per Group'),
            Center(child: IncDec(iterCtrl, 'Count')),
            const SizedBox(height: AtriarchSpacing.xxl),
            _sectionLabel('Group Assignment'),
            Text(
              'Select a group, then tap online targets to assign them.',
              style: TextStyle(color: tokens.textTertiary),
            ),
            const SizedBox(height: AtriarchSpacing.md),
            ...List.generate(5, (i) => _buildGroupSection(i)),
            const SizedBox(height: AtriarchSpacing.lg),
            _sectionLabel('Available Targets'),
            Consumer<AppState>(
              builder: (_, state, __) {
                final assigned = groups.expand((g) => g.targetIds).toSet();
                final unassigned = state.targets
                    .where((t) => t.isOnline && !assigned.contains(t.id))
                    .toList();
                if (unassigned.isEmpty) {
                  return Text(
                    'All online targets assigned.',
                    style: TextStyle(color: tokens.textTertiary),
                  );
                }
                return Wrap(
                  spacing: AtriarchSpacing.sm,
                  runSpacing: AtriarchSpacing.sm,
                  children: unassigned
                      .map((t) => TargetChip(
                            target: t,
                            onTap: () => _assignTargetToGroup(t.id),
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: AtriarchSpacing.xxl),
            Consumer<AppState>(
              builder: (_, state, __) {
                if (state.phase == DrillPhase.armingFailed) {
                  return _ArmingFailedBanner(onRetry: _retryDrill);
                }
                return const SizedBox.shrink();
              },
            ),
            Consumer<AppState>(
              builder: (_, state, __) => _StartButton(
                phase: state.phase,
                onStart: _startDrill,
              ),
            ),
            const SizedBox(height: AtriarchSpacing.xxl),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSection(int index) {
    final tokens = context.atriarch;
    final group = groups[index];
    final isSelected = selectedGroupIndex == index;
    return Card(
      color: isSelected ? tokens.bgElevated : null,
      child: InkWell(
        onTap: () => setState(() => selectedGroupIndex = index),
        child: Padding(
          padding: const EdgeInsets.all(AtriarchSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Group ${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? tokens.groupColor(index + 1)
                      : tokens.textPrimary,
                ),
              ),
              const SizedBox(height: AtriarchSpacing.sm),
              group.targetIds.isEmpty
                  ? Text(
                      'No targets assigned',
                      style: TextStyle(color: tokens.textTertiary),
                    )
                  : Wrap(
                      spacing: AtriarchSpacing.xs,
                      children: group.targetIds
                          .map((id) => Chip(
                                label: Text('T$id'),
                                onDeleted: () =>
                                    _removeTargetFromGroup(index, id),
                                deleteIconColor: tokens.statusViolation,
                              ))
                          .toList(),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AtriarchSpacing.sm),
      child: Text(text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}

class _StartButton extends StatelessWidget {
  final DrillPhase phase;
  final VoidCallback onStart;

  const _StartButton({required this.phase, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final arming = phase == DrillPhase.arming;
    final disabled = arming;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Semantics(
        button: true,
        enabled: !disabled,
        label: arming
            ? 'Arming drill. Waiting for transmitter.'
            : 'Start drill',
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: arming ? tokens.statusOffline : tokens.statusLive,
            foregroundColor: tokens.bgBase,
            disabledBackgroundColor: tokens.statusOffline,
            disabledForegroundColor: tokens.bgBase,
          ),
          onPressed: disabled ? null : onStart,
          child: arming
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: tokens.bgBase,
                      ),
                    ),
                    const SizedBox(width: AtriarchSpacing.md),
                    Text(
                      'ARMING…',
                      style: TextStyle(
                          fontSize: 20, color: tokens.bgBase, letterSpacing: 2),
                    ),
                  ],
                )
              : Text(
                  'START DRILL',
                  style: TextStyle(fontSize: 20, color: tokens.bgBase),
                ),
        ),
      ),
    );
  }
}

class _ArmingFailedBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _ArmingFailedBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Container(
      margin: const EdgeInsets.only(bottom: AtriarchSpacing.md),
      padding: const EdgeInsets.all(AtriarchSpacing.md),
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        border: Border.all(color: tokens.statusViolation),
        borderRadius: BorderRadius.circular(AtriarchRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: tokens.statusViolation),
          const SizedBox(width: AtriarchSpacing.md),
          Expanded(
            child: Text(
              'No response from transmitter. Check connection.',
              style: TextStyle(color: tokens.textPrimary),
            ),
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          Semantics(
            button: true,
            label: 'Retry starting the drill',
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ),
        ],
      ),
    );
  }
}
