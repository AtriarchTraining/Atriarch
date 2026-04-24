import 'package:flutter/material.dart';

import '../models/drill_config.dart';
import '../models/drill_template.dart';
import '../repositories/drill_template_repository.dart';
import '../theme/atriarch_theme.dart';
import 'tactical/tactical_card.dart';
import 'tactical/tactical_primary_button.dart';

/// PresetRow — tactical header row for the Program Setup screens.
///
/// Gate-2 shipped a dropdown + Save/Overflow row pinned above the form. This
/// Stage-3 rebuild talks directly to [DrillTemplateRepository] (SQLite,
/// `drill_templates` table) and uses tactical styling. The `preset_store.dart`
/// ChangeNotifier is no longer needed.
///
/// Callers pass [currentConfig] (a builder that snapshots the live
/// controllers), [onLoad] (which pushes a selected template's config into
/// the screen's controllers), and [onSave] (which opens a "name this preset"
/// dialog and then inserts through [drillTemplates]).
class PresetRow extends StatefulWidget {
  const PresetRow({
    super.key,
    required this.drillTemplates,
    required this.currentConfig,
    required this.onLoad,
    required this.onSave,
  });

  final DrillTemplateRepository drillTemplates;
  final DrillConfig Function() currentConfig;
  final void Function(DrillTemplate) onLoad;
  final VoidCallback onSave;

  @override
  State<PresetRow> createState() => _PresetRowState();
}

class _PresetRowState extends State<PresetRow> {
  List<DrillTemplate> _templates = const [];
  DrillTemplate? _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final list = await widget.drillTemplates.listAll();
    if (!mounted) return;
    setState(() {
      _templates = list;
      // Keep selection if still present.
      if (_selected != null &&
          !list.any((t) => t.id == _selected!.id)) {
        _selected = null;
      }
      _loading = false;
    });
  }

  void _onSavePressed() {
    widget.onSave();
    // Give the caller a beat to persist, then refresh.
    Future<void>.delayed(const Duration(milliseconds: 50), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      padding: const EdgeInsets.all(AtriarchSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: _loading
                ? const SizedBox(
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : DropdownButton<DrillTemplate>(
                    isExpanded: true,
                    value: _selected,
                    hint: Text(
                      _templates.isEmpty ? '— NO PRESETS —' : '— PRESET —',
                      style: TextStyle(color: tokens.textTertiary),
                    ),
                    items: _templates
                        .map(
                          (t) => DropdownMenuItem<DrillTemplate>(
                            value: t,
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: tokens.textPrimary),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (t) => setState(() => _selected = t),
                  ),
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          SizedBox(
            width: 120,
            child: TacticalPrimaryButton(
              label: 'LOAD',
              variant: _selected == null
                  ? TacticalButtonVariant.disabled
                  : TacticalButtonVariant.primary,
              onPressed: _selected == null
                  ? null
                  : () => widget.onLoad(_selected!),
            ),
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          SizedBox(
            width: 120,
            child: TacticalPrimaryButton(
              label: 'SAVE',
              onPressed: _onSavePressed,
            ),
          ),
        ],
      ),
    );
  }
}
