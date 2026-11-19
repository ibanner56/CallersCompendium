// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import '../../data/dialect_library_controller.dart';
import '../../data/dialect_library_scope.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../utils/confirm_delete.dart';
import '../../utils/undo_snack_bar.dart';
import '../../theme/keyboard_dismiss.dart';
import '../../widgets/dirty_dialog_guard.dart';
import '../../widgets/section_header.dart';
import '../../search/facet_labels.dart';
import '../dialect_editor_screen.dart';
import 'dance_details_section.dart';
import '../../theme/app_shapes.dart';

/// The Dialect settings section: a dance-form selector over the library
/// manager of the chosen form's dialects, read live from
/// [DialectLibraryScope]. Each dance form has its own dialects (ADR-006 §9.1,
/// point 1).
///
/// The selector starts on contra, the form every dance was before other forms
/// were offered (the implementer's call; the alternative, opening on the
/// new-dance form setting as the glossary does, would make a contra-only
/// caller who once chose English land on English dialects here).
class DialectSection extends StatefulWidget {
  const DialectSection({super.key});

  @override
  State<DialectSection> createState() => _DialectSectionState();
}

class _DialectSectionState extends State<DialectSection> {
  DanceForm _form = DanceForm.contra;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      keyboardDismissBehavior: textEntryKeyboardDismiss(),
      children: [
        SectionHeader(title: l10n.settingsDialectHeader),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsDialectFormHelper),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<DanceForm>(
                key: const ValueKey('dialect-form'),
                showSelectedIcon: false,
                segments: [
                  for (final form in DanceForm.values)
                    ButtonSegment(
                      value: form,
                      label: Text(
                        danceFormLabel(l10n, form),
                        key: ValueKey('dialect-form-${form.name}'),
                      ),
                    ),
                ],
                selected: {_form},
                onSelectionChanged: (selected) =>
                    setState(() => _form = selected.single),
              ),
            ],
          ),
        ),
        _DialectLibrarySection(
          key: ValueKey('dialect-library-${_form.name}'),
          controller: DialectLibraryScope.of(context).forForm(_form),
        ),
        const SizedBox(height: AppSpacing.lg),
        const DanceDetailsAndShorthandsSection(),
      ],
    );
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
  const _DialectLibrarySection({super.key, required this.controller});

  final DialectLibraryController controller;

  Future<void> _editCustom(BuildContext context, Dialect dialect) async {
    final edited = await Navigator.of(context).push<Dialect>(
      MaterialPageRoute(
        builder: (_) =>
            DialectEditorScreen(initial: dialect, form: controller.form),
      ),
    );
    if (edited == null) return;
    // By name, not an upsert: the dialect may have been renamed or deleted
    // while the editor was open, and a save must not add it back.
    final saved = await controller.updateTerms(edited);
    if (saved || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(
            context,
          ).settingsDialectEditConflictSnack(dialect.name),
        ),
      ),
    );
  }

  Future<void> _createNew(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final name = await _promptName(
      context,
      title: l10n.settingsDialectNewButton,
      confirmLabel: l10n.settingsDialectCreateConfirm,
      initial: l10n.settingsDialectNewDefaultName,
    );
    if (name == null || !context.mounted) return;
    // Seed a blank dialect and open the editor; only persist on save so a
    // canceled "New dialect" leaves nothing behind.
    final edited = await Navigator.of(context).push<Dialect>(
      MaterialPageRoute(
        builder: (_) => DialectEditorScreen(
          initial: Dialect(name: name),
          form: controller.form,
        ),
      ),
    );
    if (edited == null) return;
    await controller.duplicate(name: edited.name, from: edited);
  }

  Future<void> _duplicateFrom(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final source = await showDialog<Dialect>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.settingsDialectDuplicateFrom),
        children: [
          for (final d in controller.all)
            SimpleDialogOption(
              key: ValueKey('dialect-duplicate-source-${d.name}'),
              onPressed: () => Navigator.of(ctx).pop(d),
              child: Text(d.name),
            ),
        ],
      ),
      animationStyle: AppMotion.styleFor(context),
    );
    if (source == null) return;
    await controller.duplicate(
      name: l10n.commonDuplicateTitleSuffix(source.name),
      from: source,
    );
  }

  Future<void> _duplicateToCustomize(
    BuildContext context,
    Dialect preset,
  ) async {
    final l10n = AppLocalizations.of(context);
    final copy = await controller.duplicate(
      name: l10n.commonDuplicateTitleSuffix(preset.name),
      from: preset,
    );
    if (!context.mounted) return;
    await _editCustom(context, copy);
  }

  Future<void> _rename(BuildContext context, Dialect dialect) async {
    final l10n = AppLocalizations.of(context);
    final name = await _promptName(
      context,
      title: l10n.settingsDialectRenameTitle,
      confirmLabel: l10n.settingsDialectRename,
      initial: dialect.name,
    );
    if (name == null || name == dialect.name) return;
    await controller.rename(dialect.name, name);
  }

  /// Deletes the custom [dialect] at once and offers Undo, asking first only
  /// when "Confirm before delete" is on (see `confirm_delete.dart`).
  Future<void> _confirmDelete(BuildContext context, Dialect dialect) async {
    if (!await confirmDeleteIfEnabled(context, itemLabel: dialect.name)) {
      return;
    }
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    // Read after the confirmation: the library may have changed while it was
    // open, and Undo puts back what this delete actually removed.
    final removed = controller.customByName(dialect.name);
    if (removed == null) return;
    final index = controller.customDialects.indexOf(removed);
    final wasActive = controller.activeName == removed.name;
    await controller.delete(removed.name);
    if (messenger == null) return;
    showUndoSnackBar(
      messenger,
      actionKey: const ValueKey('dialect-delete-undo'),
      message: l10n.commonDeletedSnack(removed.name),
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: accessibleNavigation,
      onUndo: () => controller.restoreDeleted(
        removed,
        index: index,
        wasActive: wasActive,
      ),
    );
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
      animationStyle: AppMotion.styleFor(context),
    );
    if (name == null || name.isEmpty) return null;
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final all = controller.all;
    // The resolved active dialect's name — falls back to the app default, so a
    // preset row is selected by default when nothing has been chosen.
    final activeName = controller.active.name;
    return Column(
      children: [
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
                label: Text(l10n.settingsDialectNewButton),
              ),
              OutlinedButton.icon(
                key: const ValueKey('duplicate-dialect'),
                onPressed: () async => _duplicateFrom(context),
                icon: const Icon(Icons.copy_all_outlined),
                label: Text(l10n.settingsDialectDuplicateFrom),
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
    final l10n = AppLocalizations.of(context);
    return RadioListTile<String>(
      value: dialect.name,
      title: Row(
        children: [
          Flexible(child: Text(dialect.name)),
          if (isPreset) ...[
            const SizedBox(width: AppSpacing.xs),
            _presetBadge(theme, l10n),
          ],
        ],
      ),
      subtitle: _dialectSubtitle(dialect),
      secondary: PopupMenuButton<String>(
        key: ValueKey('dialect-menu-${dialect.name}'),
        tooltip: l10n.settingsDialectActionsTooltip,
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
            ? [
                PopupMenuItem(
                  value: 'duplicate-customize',
                  child: Text(l10n.settingsDialectDuplicateToCustomize),
                ),
              ]
            : [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(l10n.settingsDialectEditTerms),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: Text(l10n.settingsDialectRename),
                ),
                PopupMenuItem(value: 'delete', child: Text(l10n.commonDelete)),
              ],
      ),
    );
  }

  Widget _presetBadge(ThemeData theme, AppLocalizations l10n) {
    return Container(
      key: ValueKey('dialect-preset-badge-${dialect.name}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        // intentional: 2px optical inset, below the 4px AppSpacing grid
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: AppShapes.borderRadiusSmall,
      ),
      child: Text(
        l10n.settingsDialectPresetBadge,
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

  /// The gendered role word the typed name holds, which the app never shows
  /// (ADR-006 §9.1, point 7), or `null`.
  String? get _genderedWord => genderedRoleWordIn(_controller.text);

  void _submit() {
    if (_genderedWord != null) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DirtyDialogGuard(
      listenable: _controller,
      isDirty: () => _controller.text != widget.initial,
      child: AlertDialog(
        title: Text(widget.title),
        content: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => TextField(
            key: const ValueKey('dialect-name-field'),
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.settingsDialectNameLabel,
              errorText: switch (_genderedWord) {
                final word? => l10n.validationGenderedRoleTerm(word),
                null => null,
              },
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => FilledButton(
              key: const ValueKey('dialect-name-confirm'),
              onPressed: _genderedWord == null ? _submit : null,
              child: Text(widget.confirmLabel),
            ),
          ),
        ],
      ),
    );
  }
}
