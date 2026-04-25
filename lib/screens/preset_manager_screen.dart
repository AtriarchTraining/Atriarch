import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/drill_config.dart';
import '../models/drill_template.dart';
import '../repositories/drill_template_repository.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import 'program_a_setup_screen.dart';
import 'program_b_setup_screen.dart';

class PresetManagerScreen extends StatefulWidget {
  const PresetManagerScreen({super.key});

  @override
  State<PresetManagerScreen> createState() => _PresetManagerScreenState();
}

class _PresetManagerScreenState extends State<PresetManagerScreen> {
  DrillTemplateRepository? _repo;
  Future<List<DrillTemplate>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo ??= context.read<DrillTemplateRepository>();
    _future ??= _repo!.listAll();
  }

  void _refresh() {
    setState(() {
      _future = _repo!.listAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return TacticalScaffold(
      title: 'PRESETS',
      body: FutureBuilder<List<DrillTemplate>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final templates = snap.data ?? const [];
          if (templates.isEmpty) {
            return _EmptyState();
          }
          return ListView.builder(
            itemCount: templates.length,
            itemBuilder: (ctx, i) {
              final t = templates[i];
              return _SwipeablePresetRow(
                key: ValueKey(t.id),
                template: t,
                repo: _repo!,
                onRefresh: _refresh,
                onTap: () async {
                  if (t.programType == ProgramType.programA) {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProgramASetupScreen(),
                      ),
                    );
                  } else {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProgramBSetupScreen(),
                      ),
                    );
                  }
                  if (mounted) _refresh();
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Center(
      child: Text(
        'NO PRESETS SAVED.',
        style: AtriarchText.labelTiny(color: tokens.textTertiary),
      ),
    );
  }
}

String _configSummary(DrillTemplate t) {
  final c = t.config;
  return '${c.iterations} ITER · ${c.startMin}–${c.startMax}s';
}

class _SwipeablePresetRow extends StatefulWidget {
  final DrillTemplate template;
  final DrillTemplateRepository repo;
  final VoidCallback onRefresh;
  final VoidCallback onTap;

  const _SwipeablePresetRow({
    super.key,
    required this.template,
    required this.repo,
    required this.onRefresh,
    required this.onTap,
  });

  @override
  State<_SwipeablePresetRow> createState() => _SwipeablePresetRowState();
}

class _SwipeablePresetRowState extends State<_SwipeablePresetRow>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offsetAnim;

  static const double _actionWidth = 140.0; // total reveal width (2 × 70)
  static const double _swipeThreshold = 60.0;

  double _dragOffset = 0;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _offsetAnim = Tween<double>(begin: 0, end: -_actionWidth)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snapOpen() {
    _open = true;
    _controller.forward();
  }

  void _snapClose() {
    _open = false;
    _controller.reverse();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dx.abs() < details.delta.dy.abs()) return;
    final delta = details.primaryDelta ?? 0;
    final currentOffset = _open ? -_actionWidth : 0.0;
    final newOffset = (currentOffset + delta).clamp(-_actionWidth, 0.0);
    _controller.value = (-newOffset) / _actionWidth;
    _dragOffset = newOffset;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_dragOffset < -_swipeThreshold) {
      _snapOpen();
    } else {
      _snapClose();
    }
    _dragOffset = 0;
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    _snapClose();
    final controller = TextEditingController(text: widget.template.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Rename preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Name',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(controller.text.trim()),
            child: const Text('RENAME'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    await widget.repo.rename(widget.template.id, newName);
    if (mounted) widget.onRefresh();
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    _snapClose();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete ${widget.template.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repo.delete(widget.template.id);
    if (mounted) widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final pgmBadge =
        widget.template.programType == ProgramType.programA ? 'PGM-A' : 'PGM-B';
    final summary = _configSummary(widget.template);

    return SizedBox(
      height: 72,
      child: Stack(
        children: [
          // --- Action tiles (revealed on swipe) ---
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // REN tile
                GestureDetector(
                  onTap: () => _showRenameDialog(context),
                  child: Container(
                    width: 70,
                    color: const Color(0xFF1a1a2a),
                    alignment: Alignment.center,
                    child: Text(
                      'REN',
                      style: AtriarchText.labelTiny(color: tokens.textPrimary),
                    ),
                  ),
                ),
                // DEL tile
                GestureDetector(
                  onTap: () => _showDeleteDialog(context),
                  child: Container(
                    width: 70,
                    color: const Color(0xFF2a1010),
                    alignment: Alignment.center,
                    child: Text(
                      'DEL',
                      style: AtriarchText.labelTiny(
                          color: tokens.statusViolation),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // --- Swipeable front row ---
          AnimatedBuilder(
            animation: _offsetAnim,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(_offsetAnim.value, 0),
                child: child,
              );
            },
            child: GestureDetector(
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onTap: () {
                if (_open) {
                  _snapClose();
                } else {
                  widget.onTap();
                }
              },
              child: Container(
                height: 72,
                color: tokens.bgCard,
                padding: const EdgeInsets.symmetric(
                  horizontal: AtriarchSpacing.lg,
                  vertical: AtriarchSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.template.name,
                            style: AtriarchText.labelTiny(
                                color: tokens.statusHit),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            summary,
                            style: AtriarchText.labelTiny(
                                color: tokens.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      pgmBadge,
                      style:
                          AtriarchText.labelTiny(color: tokens.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom divider
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Divider(
              height: 1,
              thickness: 1,
              color: tokens.border,
            ),
          ),
        ],
      ),
    );
  }
}
