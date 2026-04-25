import 'package:flutter/material.dart';

import '../models/drill_config.dart';
import '../models/drill_template.dart';
import '../repositories/drill_template_repository.dart';
import '../services/preferences_repository.dart';
import '../theme/atriarch_theme.dart';
import 'tactical/tactical_card.dart';

class PresetChipStrip extends StatefulWidget {
  const PresetChipStrip({
    super.key,
    required this.drillTemplates,
    required this.currentConfig,
    required this.onLoad,
    required this.onSave,
    this.preferences,
    this.onSelectionChanged,
  });

  final DrillTemplateRepository drillTemplates;
  final DrillConfig Function() currentConfig;
  final void Function(DrillTemplate) onLoad;
  final VoidCallback onSave;
  final PreferencesRepository? preferences;
  final void Function(DrillTemplate?)? onSelectionChanged;

  @override
  State<PresetChipStrip> createState() => _PresetChipStripState();
}

class _PresetChipStripState extends State<PresetChipStrip> {
  List<DrillTemplate> _templates = const [];
  DrillTemplate? _selected;
  bool _loadedFromPrefs = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final templates = await widget.drillTemplates.listAll();
    String? lastId;
    if (widget.preferences != null) {
      lastId = await widget.preferences!.getDefaultPresetId();
    }
    if (!mounted) return;
    DrillTemplate? selected;
    bool fromPrefs = false;
    if (lastId != null) {
      try {
        selected = templates.firstWhere((t) => t.id == lastId);
        fromPrefs = true;
      } catch (_) {
        // lastId no longer exists — ignore
      }
    }
    setState(() {
      _templates = templates;
      _selected = selected;
      _loadedFromPrefs = fromPrefs;
      _loading = false;
    });
    if (selected != null) {
      widget.onLoad(selected);
      widget.onSelectionChanged?.call(selected);
    }
  }

  Future<void> _refresh() async {
    final templates = await widget.drillTemplates.listAll();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      if (_selected != null && !templates.any((t) => t.id == _selected!.id)) {
        _selected = null;
        _loadedFromPrefs = false;
        widget.onSelectionChanged?.call(null);
      }
    });
  }

  void _onSavePressed() {
    widget.onSave();
    Future<void>.delayed(const Duration(milliseconds: 80), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    if (_loading) {
      return TacticalCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AtriarchSpacing.md,
          vertical: AtriarchSpacing.sm,
        ),
        child: const SizedBox(
          height: 32,
          child: Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    return TacticalCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AtriarchSpacing.md,
        vertical: AtriarchSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loadedFromPrefs && _selected != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AtriarchSpacing.xs),
              child: Text(
                'LOADED: ${_selected!.name}',
                style: AtriarchText.labelTiny(color: tokens.textTertiary),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in _templates)
                  _Chip(
                    label: t.name,
                    selected: _selected?.id == t.id,
                    onTap: () {
                      setState(() {
                        _selected = t;
                        _loadedFromPrefs = false;
                      });
                      widget.onLoad(t);
                      widget.onSelectionChanged?.call(t);
                    },
                  ),
                _Chip(
                  label: '+ SAVE',
                  selected: false,
                  onTap: _onSavePressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: AtriarchSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AtriarchSpacing.sm,
          vertical: AtriarchSpacing.xs,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? tokens.statusHit : tokens.border,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          style: AtriarchText.labelTiny(
            color: selected ? tokens.statusHit : tokens.textTertiary,
          ),
        ),
      ),
    );
  }
}
