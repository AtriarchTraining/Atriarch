import 'package:flutter/material.dart';

import '../models/drill_config.dart';
import '../theme/atriarch_theme.dart';
import '../util/preset_store.dart';

/// Header row rendered at the top of both Program Setup screens
/// (addendum §2 Information Architecture). Owns the preset dropdown, the
/// `Save…` button, and the overflow (⋯) menu with rename / delete /
/// set-default / duplicate.
///
/// Rebuilds automatically when [store] notifies. The setup screen passes
/// [onPresetLoaded] so it can push preset values into its controllers after
/// a selection change (including loads triggered by `Duplicate` which
/// switches the selection to the new copy).
class PresetRow extends StatelessWidget {
  const PresetRow({
    super.key,
    required this.store,
    required this.onPresetLoaded,
  });

  final PresetStore store;

  /// Fired after any action that changes [PresetStore.selectedPresetId]
  /// (selection-change via dropdown, duplicate, delete). The callback is
  /// responsible for re-syncing the screen's controllers.
  final VoidCallback onPresetLoaded;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => _buildRow(context),
    );
  }

  Widget _buildRow(BuildContext context) {
    final tokens = context.atriarch;
    final selectedId = store.selectedPresetId;
    final hasSelection = selectedId != null;
    // Save… is enabled when either nothing is selected (so only "Save as
    // new…" appears in the sheet) or a preset is selected AND the live
    // config has drifted from it.
    final canSave = !hasSelection || store.isModified;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AtriarchSpacing.lg,
        vertical: AtriarchSpacing.md,
      ),
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Text('Preset:', style: TextStyle(color: tokens.textSecondary)),
          const SizedBox(width: AtriarchSpacing.sm),
          Expanded(child: _buildDropdown(context)),
          const SizedBox(width: AtriarchSpacing.sm),
          TextButton(
            onPressed: canSave ? () => _openSaveSheet(context) : null,
            child: const Text('Save…'),
          ),
          _buildOverflow(context),
        ],
      ),
    );
  }

  Widget _buildDropdown(BuildContext context) {
    final tokens = context.atriarch;
    final presets = store.presets;
    final defaultId = store.defaultPresetId;
    final selectedId = store.selectedPresetId;

    final dropdownValue = presets.any((p) => p.id == selectedId)
        ? selectedId
        : null;

    final modifiedSuffix = store.isModified ? '  — modified' : '';

    return DropdownButtonFormField<String?>(
      initialValue: dropdownValue,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AtriarchSpacing.md,
          vertical: AtriarchSpacing.sm,
        ),
      ),
      hint: Text(
        presets.isEmpty ? 'No presets saved' : 'None',
        style: TextStyle(color: tokens.textTertiary),
      ),
      // selectedItemBuilder renders the collapsed label row. Items include a
      // synthetic "None" entry at index 0, matching the items list below.
      selectedItemBuilder: (context) {
        return <Widget>[
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('None'),
          ),
          ...presets.map(
            (p) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${p.name}$modifiedSuffix',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ];
      },
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('None'),
        ),
        ...presets.map((p) {
          final isDefault = p.id == defaultId;
          return DropdownMenuItem<String?>(
            value: p.id,
            child: Row(
              children: [
                Expanded(
                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
                if (isDefault)
                  Icon(Icons.check, size: 16, color: tokens.textTertiary),
              ],
            ),
          );
        }),
      ],
      onChanged: (value) async {
        await store.selectPreset(value);
        onPresetLoaded();
      },
    );
  }

  Widget _buildOverflow(BuildContext context) {
    final hasSelection = store.selectedPresetId != null;
    final isAlreadyDefault = hasSelection &&
        store.selectedPresetId == store.defaultPresetId;

    return PopupMenuButton<_PresetAction>(
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => _handleAction(context, action),
      itemBuilder: (_) => <PopupMenuEntry<_PresetAction>>[
        PopupMenuItem<_PresetAction>(
          value: _PresetAction.rename,
          enabled: hasSelection,
          child: const Text('Rename preset'),
        ),
        PopupMenuItem<_PresetAction>(
          value: _PresetAction.delete,
          enabled: hasSelection,
          child: const Text('Delete preset'),
        ),
        PopupMenuItem<_PresetAction>(
          value: _PresetAction.setDefault,
          enabled: hasSelection && !isAlreadyDefault,
          child: const Text('Set as default'),
        ),
        PopupMenuItem<_PresetAction>(
          value: _PresetAction.duplicate,
          enabled: hasSelection,
          child: const Text('Duplicate'),
        ),
      ],
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    _PresetAction action,
  ) async {
    switch (action) {
      case _PresetAction.rename:
        await _openRenameDialog(context);
      case _PresetAction.delete:
        await _openDeleteConfirm(context);
      case _PresetAction.setDefault:
        await store.setSelectedAsDefault();
      case _PresetAction.duplicate:
        await store.duplicateSelected();
        onPresetLoaded();
    }
  }

  Future<void> _openRenameDialog(BuildContext context) async {
    final selId = store.selectedPresetId;
    if (selId == null) return;
    final preset = store.presets.firstWhere(
      (p) => p.id == selId,
      orElse: () => throw StateError('selected preset vanished'),
    );
    final controller = TextEditingController(text: preset.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Rename preset'),
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
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result != null && result.isNotEmpty) {
      await store.renameSelected(result);
    }
  }

  Future<void> _openDeleteConfirm(BuildContext context) async {
    final selId = store.selectedPresetId;
    if (selId == null) return;
    final preset = store.presets.firstWhere(
      (p) => p.id == selId,
      orElse: () => throw StateError('selected preset vanished'),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete preset'),
          content: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Delete '),
                TextSpan(
                  text: preset.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: '?'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed ?? false) {
      await store.deleteSelected();
      onPresetLoaded();
    }
  }

  Future<void> _openSaveSheet(BuildContext context) async {
    final hasSelection = store.selectedPresetId != null;
    final live = store.liveConfig;
    if (live == null) return;

    final action = await showModalBottomSheet<_SaveSheetAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasSelection)
                ListTile(
                  leading: const Icon(Icons.save),
                  title: const Text('Save'),
                  subtitle: const Text('Overwrite selected preset'),
                  onTap: () =>
                      Navigator.of(sheetCtx).pop(_SaveSheetAction.overwrite),
                ),
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('Save as new…'),
                onTap: () =>
                    Navigator.of(sheetCtx).pop(_SaveSheetAction.saveAsNew),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(sheetCtx).pop(null),
              ),
            ],
          ),
        );
      },
    );

    if (!context.mounted) return;

    switch (action) {
      case _SaveSheetAction.overwrite:
        await store.overwriteSelected(live);
      case _SaveSheetAction.saveAsNew:
        await _openSaveAsNewDialog(context, live);
      case null:
        break;
    }
  }

  Future<void> _openSaveAsNewDialog(
    BuildContext context,
    DrillConfig config,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Save as new preset'),
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
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (name != null && name.isNotEmpty) {
      await store.savePresetAsNew(name, config);
    }
  }
}

enum _PresetAction { rename, delete, setDefault, duplicate }

enum _SaveSheetAction { overwrite, saveAsNew }
