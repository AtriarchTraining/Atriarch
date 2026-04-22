import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/drill_config.dart';
import '../theme/atriarch_theme.dart';
import '../theme/theme_controller.dart';
import '../util/preset_store.dart';
import '../widgets/inc_dec.dart';
import '../widgets/preset_row.dart';
import 'drill_running_screen.dart';

class ProgramBSetupScreen extends StatefulWidget {
  const ProgramBSetupScreen({super.key});

  @override
  State<ProgramBSetupScreen> createState() => _ProgramBSetupScreenState();
}

class _ProgramBSetupScreenState extends State<ProgramBSetupScreen> {
  final startMinCtrl = TextEditingController(text: '1.00');
  final startMaxCtrl = TextEditingController(text: '3.00');
  final delayMinCtrl = TextEditingController(text: '0.50');
  final delayMaxCtrl = TextEditingController(text: '2.00');
  final hitsMinCtrl = TextEditingController(text: '1.00');
  final hitsMaxCtrl = TextEditingController(text: '3.00');
  final iterCtrl = TextEditingController(text: '5.00');

  DrillConfig? _lastConfig;

  PresetStore? _presetStore;

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
      context.read<ThemeController>().setDrillContextActive(true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final prefs = context.read<AppState>().preferences;
      final store = PresetStore(
        repository: prefs,
        programType: ProgramType.programB,
      );
      await store.init();
      if (!mounted) {
        store.dispose();
        return;
      }
      setState(() => _presetStore = store);
      if (store.selectedPresetId != null) _onPresetLoaded();
      _pushLiveConfig();
    });

    for (final c in [
      startMinCtrl,
      startMaxCtrl,
      delayMinCtrl,
      delayMaxCtrl,
      hitsMinCtrl,
      hitsMaxCtrl,
      iterCtrl,
    ]) {
      c.addListener(_pushLiveConfig);
    }
  }

  @override
  void dispose() {
    try {
      context.read<AppState>().removeListener(_onPhaseChanged);
    } catch (_) {
      // Teardown — ignore.
    }
    try {
      context.read<ThemeController>().setDrillContextActive(false);
    } catch (_) {
      // Teardown — ignore.
    }
    for (final c in [
      startMinCtrl,
      startMaxCtrl,
      delayMinCtrl,
      delayMaxCtrl,
      hitsMinCtrl,
      hitsMaxCtrl,
      iterCtrl,
    ]) {
      c.removeListener(_pushLiveConfig);
    }
    _presetStore?.dispose();
    super.dispose();
  }

  /// Snapshot the current form state into the preset store so "— modified"
  /// and Save… enablement stay live.
  void _pushLiveConfig() {
    final store = _presetStore;
    if (store == null) return;
    store.setLiveConfig(_currentConfigForPresetTracking());
  }

  DrillConfig _currentConfigForPresetTracking() {
    return DrillConfig(
      programType: ProgramType.programB,
      startMin: double.tryParse(startMinCtrl.text) ?? 1.0,
      startMax: double.tryParse(startMaxCtrl.text) ?? 3.0,
      delayMin: double.tryParse(delayMinCtrl.text) ?? 0.5,
      delayMax: double.tryParse(delayMaxCtrl.text) ?? 2.0,
      hitsMin: (double.tryParse(hitsMinCtrl.text) ?? 1).toInt(),
      hitsMax: (double.tryParse(hitsMaxCtrl.text) ?? 3).toInt(),
      targetIds: const <int>[],
      noShootIds: const <int>[],
      iterations: (double.tryParse(iterCtrl.text) ?? 5).toInt(),
    );
  }

  /// Program B has no group state, so loading a preset just writes timing +
  /// iteration fields into the controllers. Target assignment is derived at
  /// drill-start from whichever targets are currently online.
  void _onPresetLoaded() {
    final store = _presetStore;
    if (store == null) return;
    final selId = store.selectedPresetId;
    if (selId == null) {
      _pushLiveConfig();
      return;
    }
    final preset = store.presets.firstWhere(
      (p) => p.id == selId,
      orElse: () => throw StateError('selected preset vanished'),
    );
    final cfg = preset.config;
    startMinCtrl.text = cfg.startMin.toStringAsFixed(2);
    startMaxCtrl.text = cfg.startMax.toStringAsFixed(2);
    delayMinCtrl.text = cfg.delayMin.toStringAsFixed(2);
    delayMaxCtrl.text = cfg.delayMax.toStringAsFixed(2);
    hitsMinCtrl.text = cfg.hitsMin.toStringAsFixed(2);
    hitsMaxCtrl.text = cfg.hitsMax.toStringAsFixed(2);
    iterCtrl.text = cfg.iterations.toStringAsFixed(2);
    _pushLiveConfig();
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
    final onlineTargets = state.targets.where((t) => t.isOnline).toList();

    if (onlineTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No targets online. Run Target Setup first.')),
      );
      return null;
    }

    return DrillConfig(
      programType: ProgramType.programB,
      startMin: double.tryParse(startMinCtrl.text) ?? 1.0,
      startMax: double.tryParse(startMaxCtrl.text) ?? 3.0,
      delayMin: double.tryParse(delayMinCtrl.text) ?? 0.5,
      delayMax: double.tryParse(delayMaxCtrl.text) ?? 2.0,
      hitsMin: (double.tryParse(hitsMinCtrl.text) ?? 1).toInt(),
      hitsMax: (double.tryParse(hitsMaxCtrl.text) ?? 3).toInt(),
      targetIds: onlineTargets.map((t) => t.id).toList(),
      noShootIds:
          onlineTargets.where((t) => t.isNoShoot).map((t) => t.id).toList(),
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Scaffold(
      appBar: AppBar(title: const Text('Program B - Individual Mode')),
      body: Column(
        children: [
          if (_presetStore != null)
            PresetRow(
              store: _presetStore!,
              onPresetLoaded: _onPresetLoaded,
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AtriarchSpacing.lg),
              child: Column(
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
            _sectionLabel('Iterations per Target'),
            Center(child: IncDec(iterCtrl, 'Count')),
            const SizedBox(height: AtriarchSpacing.lg),
            Consumer<AppState>(
              builder: (_, state, __) {
                final online =
                    state.targets.where((t) => t.isOnline).length;
                final noShoot = state.targets
                    .where((t) => t.isOnline && t.isNoShoot)
                    .length;
                return Text('$online target(s) online, $noShoot no-shoot',
                    style: TextStyle(color: tokens.textTertiary));
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
          ),
        ],
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
