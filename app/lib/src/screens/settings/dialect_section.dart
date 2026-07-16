// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import '../../data/dialect_library_controller.dart';
import '../../data/dialect_library_scope.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/section_header.dart';
import '../dialect_editor_screen.dart';

/// The Dialect settings section: reads the live dialect library controller
/// from [DialectLibraryScope] and renders the library manager.
class DialectSection extends StatelessWidget {
  const DialectSection({super.key});

  @override
  Widget build(BuildContext context) {
    return _DialectLibrarySection(controller: DialectLibraryScope.of(context));
  }
}

/// The Dialect section: a manager for the user's dialect **library**
/// (`docs/design/ux.md` §6). Lists the shipped presets (read-only) followed by
/// the user's custom dialects, with a single active selection (radio
/// semantics), per-custom actions (edit terms / rename / delete), and buttons
/// to create a new dialect or duplicate one from any preset/custom.
///
/// Presets can't be edited in place (a custom dialect may not reuse a preset
/// name); "Edit terms" on a preset offers to duplicate it for customizing.
/// Mirrors `_CustomThemesSection`'s list + dialog CRUD idiom. Live preview,
/// collision validation, and dance-card/perform quick-switch are a later PR.
class _DialectLibrarySection extends StatelessWidget {
  const _DialectLibrarySection({required this.controller});

  final DialectLibraryController controller;

  Future<void> _editCustom(BuildContext context, Dialect dialect) async {
    final edited = await Navigator.of(context).push<Dialect>(
      MaterialPageRoute(builder: (_) => DialectEditorScreen(initial: dialect)),
    );
    if (edited != null) await controller.upsert(edited);
  }

  Future<void> _createNew(BuildContext context) async {
    final name = await _promptName(
      context,
      title: 'New dialect',
      confirmLabel: 'Create',
      initial: 'My dialect',
    );
    if (name == null || !context.mounted) return;
    // Seed a blank dialect and open the editor; only persist on save so a
    // canceled "New dialect" leaves nothing behind.
    final edited = await Navigator.of(context).push<Dialect>(
      MaterialPageRoute(
        builder: (_) => DialectEditorScreen(initial: Dialect(name: name)),
      ),
    );
    if (edited == null) return;
    await controller.duplicate(name: edited.name, from: edited);
  }

  Future<void> _duplicateFrom(BuildContext context) async {
    final source = await showDialog<Dialect>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Duplicate from…'),
        children: [
          for (final d in controller.all)
            SimpleDialogOption(
              key: ValueKey('dialect-duplicate-source-${d.name}'),
              onPressed: () => Navigator.of(ctx).pop(d),
              child: Text(d.name),
            ),
        ],
      ),
    );
    if (source == null) return;
    await controller.duplicate(name: '${source.name} (copy)', from: source);
  }

  Future<void> _duplicateToCustomize(
    BuildContext context,
    Dialect preset,
  ) async {
    final copy = await controller.duplicate(
      name: '${preset.name} (copy)',
      from: preset,
    );
    if (!context.mounted) return;
    await _editCustom(context, copy);
  }

  Future<void> _rename(BuildContext context, Dialect dialect) async {
    final name = await _promptName(
      context,
      title: 'Rename dialect',
      confirmLabel: 'Rename',
      initial: dialect.name,
    );
    if (name == null || name == dialect.name) return;
    await controller.rename(dialect.name, name);
  }

  Future<void> _confirmDelete(BuildContext context, Dialect dialect) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete dialect?'),
        content: Text('“${dialect.name}” will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.delete(dialect.name);
  }

  /// Prompts for a dialect name via a single-field dialog, returning the
  /// trimmed value or `null` if canceled/blank.
  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required String initial,
  }) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _DialectNameDialog(
        title: title,
        confirmLabel: confirmLabel,
        initial: initial,
      ),
    );
    if (name == null || name.isEmpty) return null;
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final all = controller.all;
    // The resolved active dialect's name — falls back to the app default, so a
    // preset row is selected by default when nothing has been chosen.
    final activeName = controller.active.name;
    return ListView(
      children: [
        SectionHeader(title: 'Dialects'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('new-dialect'),
                onPressed: () async => _createNew(context),
                icon: const Icon(Icons.add),
                label: const Text('New dialect'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('duplicate-dialect'),
                onPressed: () async => _duplicateFrom(context),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Duplicate from…'),
              ),
            ],
          ),
        ),
        RadioGroup<String>(
          groupValue: activeName,
          onChanged: (name) {
            if (name != null) controller.setActive(name);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final dialect in all)
                _DialectRow(
                  key: ValueKey('dialect-tile-${dialect.name}'),
                  dialect: dialect,
                  isPreset: controller.isPreset(dialect.name),
                  onEdit: () async => _editCustom(context, dialect),
                  onRename: () async => _rename(context, dialect),
                  onDelete: () async => _confirmDelete(context, dialect),
                  onDuplicateToCustomize: () async =>
                      _duplicateToCustomize(context, dialect),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// One row in the dialect library: a radio to make the dialect active, its
/// name (presets carry a read-only badge), and an actions menu — edit terms /
/// rename / delete for a custom dialect, or "Duplicate to customize" for a
/// read-only preset.
class _DialectRow extends StatelessWidget {
  const _DialectRow({
    super.key,
    required this.dialect,
    required this.isPreset,
    required this.onEdit,
    required this.onRename,
    required this.onDelete,
    required this.onDuplicateToCustomize,
  });

  final Dialect dialect;
  final bool isPreset;
  final VoidCallback onEdit;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onDuplicateToCustomize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RadioListTile<String>(
      value: dialect.name,
      title: Row(
        children: [
          Flexible(child: Text(dialect.name)),
          if (isPreset) ...[
            const SizedBox(width: AppSpacing.xs),
            _presetBadge(theme),
          ],
        ],
      ),
      subtitle: _dialectSubtitle(dialect),
      secondary: PopupMenuButton<String>(
        key: ValueKey('dialect-menu-${dialect.name}'),
        tooltip: 'Dialect actions',
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEdit();
            case 'duplicate-customize':
              onDuplicateToCustomize();
            case 'rename':
              onRename();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => isPreset
            ? const [
                PopupMenuItem(
                  value: 'duplicate-customize',
                  child: Text('Duplicate to customize'),
                ),
              ]
            : const [
                PopupMenuItem(value: 'edit', child: Text('Edit terms')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
      ),
    );
  }

  Widget _presetBadge(ThemeData theme) {
    return Container(
      key: ValueKey('dialect-preset-badge-${dialect.name}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        // intentional: 2px optical inset, below the 4px AppSpacing grid
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Preset',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  static Text? _dialectSubtitle(Dialect dialect) {
    if (dialect.roles.isEmpty) return null;
    final terms = dialect.roles.values.map((r) => r.plural).join(' / ');
    return Text(terms);
  }
}

/// A single-field name prompt for creating/renaming a dialect. Owns its
/// [TextEditingController] so it is disposed only after the dialog's exit
/// transition completes (disposing it eagerly in the caller triggers a
/// use-after-dispose during the pop animation).
class _DialectNameDialog extends StatefulWidget {
  const _DialectNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initial,
  });

  final String title;
  final String confirmLabel;
  final String initial;

  @override
  State<_DialectNameDialog> createState() => _DialectNameDialogState();
}

class _DialectNameDialogState extends State<_DialectNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('dialect-name-field'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('dialect-name-confirm'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
