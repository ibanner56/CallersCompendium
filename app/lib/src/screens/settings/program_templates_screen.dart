// Program templates (#2337): the Settings ▸ Defaults ▸ Program defaults rows,
// the full-screen manager (add, rename, duplicate, reorder, delete with Undo)
// and the editor for one template's slots and, with Event rules on, its rules
// (#2342). Storage lives in `data/program_templates.dart`.
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/display_defaults.dart';
import '../../data/event_rules_scope.dart';
import '../../data/persisted_preference.dart';
import '../../data/program_templates.dart';
import '../../data/repositories_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../search/collection_data.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../utils/confirm_delete.dart';
import '../../utils/undo_snack_bar.dart';
import '../../widgets/adaptive_fab.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/collection_picker.dart';
import '../../widgets/container_title_length_limit.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/event_rule_text.dart';
import '../../widgets/load_error_view.dart';
import '../../widgets/program_event_rules.dart';
import '../../widgets/program_template_name.dart';
import '../../widgets/reorder_move_buttons.dart';
import '../../widgets/settings_dropdown_row.dart';

Future<ProgramTemplates> _load(BuildContext context) =>
    loadProgramTemplates(RepositoriesScope.of(context).settings);

/// The Program defaults rows: **Program templates**, which opens the manager,
/// and the **Default template** choice (a template or Blank program).
class ProgramTemplatesSettingsRows extends StatefulWidget {
  const ProgramTemplatesSettingsRows({super.key});

  @override
  State<ProgramTemplatesSettingsRows> createState() =>
      _ProgramTemplatesSettingsRowsState();
}

class _ProgramTemplatesSettingsRowsState
    extends State<ProgramTemplatesSettingsRows> {
  ProgramTemplates? _templates;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    try {
      final templates = await _load(context);
      if (mounted) setState(() => _templates = templates);
    } catch (error, stackTrace) {
      // A failed read leaves the rows showing no templates; the manager
      // retries on its own.
      logCaughtError(
        error,
        stackTrace,
        source: 'program_templates_screen.settings_rows',
      );
    }
  }

  Future<void> _openManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ProgramTemplatesScreen()),
    );
    if (mounted) await _reload();
  }

  Future<void> _setDefault(String? id) async {
    final templates = _templates;
    if (templates == null) return;
    setState(
      () => _templates = ProgramTemplates(
        templates: templates.templates,
        defaultId: id,
      ),
    );
    await persistSetting(
      RepositoriesScope.of(context).settings,
      kProgramTemplateDefaultKey,
      id ?? kProgramTemplateBlankDefault,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final templates = _templates ?? ProgramTemplates.empty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('defaults-program-templates'),
          title: Text(l10n.settingsProgramTemplatesTitle),
          subtitle: Text(
            l10n.settingsProgramTemplatesCount(templates.templates.length),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openManager,
        ),
        SettingsDropdownRow(
          title: Text(l10n.settingsProgramTemplateDefaultTitle),
          subtitle: Text(l10n.settingsProgramTemplateDefaultSubtitle),
          isThreeLine: true,
          dropdownBuilder: (expanded) => AppDropdownField<String?>(
            key: const ValueKey('defaults-program-template-default'),
            compact: true,
            // The list grows with the user's own templates.
            filterable: true,
            fillWidth: expanded,
            value: templates.defaultId,
            onChanged: _templates == null ? null : _setDefault,
            entries: [
              AppDropdownEntry(
                value: null,
                label: l10n.programTemplateBlankProgram,
              ),
              for (final template in templates.templates)
                AppDropdownEntry(
                  value: template.id,
                  label: _displayName(l10n, template),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _displayName(AppLocalizations l10n, ProgramTemplate template) =>
    programTemplateDisplayName(l10n, template);

/// Holds a name field to [kMaxProgramTemplateNameLength] UTF-16 code units of
/// trimmed text, as the name is stored, so saving never cuts what the field
/// shows (a plain `maxLength` counts characters, and lets 60 emoji through).
const _nameLengthLimit = ContainerTitleLengthLimit(
  measure: _trimmedLength,
  max: kMaxProgramTemplateNameLength,
);

int _trimmedLength(String text) => text.trim().length;

/// Asks for a template name, starting from [initial]. Returns the trimmed
/// name, or `null` when cancelled or left blank.
Future<String?> _askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final name = await showDialog<String>(
    context: context,
    animationStyle: AppMotion.styleFor(context),
    builder: (_) => _TemplateNameDialog(title: title, initial: initial),
  );
  return name == null || name.isEmpty ? null : name;
}

/// The name prompt. Owns its controller, so the controller outlives the
/// dialog's closing animation.
class _TemplateNameDialog extends StatefulWidget {
  const _TemplateNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_TemplateNameDialog> createState() => _TemplateNameDialogState();
}

class _TemplateNameDialogState extends State<_TemplateNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('program-template-name-field'),
        controller: _controller,
        autofocus: true,
        inputFormatters: const [_nameLengthLimit],
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: l10n.programTemplateNameLabel),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('program-template-name-save'),
          onPressed: _submit,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

/// The full-screen template manager: add, rename, duplicate, reorder (drag or
/// move up / move down), and delete with Undo. Tapping a template opens its
/// editor.
class ProgramTemplatesScreen extends StatefulWidget {
  const ProgramTemplatesScreen({super.key});

  @override
  State<ProgramTemplatesScreen> createState() => _ProgramTemplatesScreenState();
}

class _ProgramTemplatesScreenState extends State<ProgramTemplatesScreen> {
  late SettingsRepository _settings;
  bool _started = false;
  bool _loading = true;
  Object? _error;
  ProgramTemplates _templates = ProgramTemplates.empty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _settings = RepositoriesScope.of(context).settings;
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    try {
      final templates = await _load(context);
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loading = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'program_templates_screen.load',
      );
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  List<String> get _ids => [for (final t in _templates.templates) t.id];

  /// Whether another template can be added: the order key holds at most
  /// [kMaxProgramTemplateOrderLength] ids.
  bool get _canAdd =>
      _templates.templates.length < kMaxProgramTemplateOrderLength;

  /// Runs a settings write, and on failure logs it and says so, so a failed
  /// save never looks like a saved one. Returns whether it succeeded.
  Future<bool> _write(String action, Future<void> Function() write) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context).programTemplateSaveError;
    final repos = RepositoriesScope.of(context);
    try {
      // One transaction, so a failure leaves nothing half-saved.
      await repos.transaction(write);
      return true;
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'program_templates_screen.$action',
      );
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return false;
    }
  }

  Future<void> _create() async {
    if (!_canAdd) return;
    final l10n = AppLocalizations.of(context);
    final name = await _askName(context, title: l10n.programTemplateNew);
    if (name == null || !mounted) return;
    final template = ProgramTemplate(id: uuidV4(), name: name);
    final ids = _ids;
    final saved = await _write('create', () async {
      await saveProgramTemplate(_settings, template);
      await saveProgramTemplateOrder(_settings, [...ids, template.id]);
      await saveProgramTemplateDefaultIfUnset(_settings, template.id);
    });
    if (!mounted) return;
    await _reload();
    if (saved && mounted) await _edit(template);
  }

  Future<void> _edit(ProgramTemplate template) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProgramTemplateEditorScreen(template: template),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _rename(ProgramTemplate template) async {
    final l10n = AppLocalizations.of(context);
    final name = await _askName(
      context,
      title: l10n.programTemplateRenameTitle,
      initial: programTemplateInitialName(l10n, template),
    );
    if (name == null || !mounted) return;
    await _write(
      'rename',
      () => saveProgramTemplate(_settings, template.copyWith(name: name)),
    );
    if (mounted) await _reload();
  }

  Future<void> _duplicate(ProgramTemplate template) async {
    if (!_canAdd) return;
    final l10n = AppLocalizations.of(context);
    final copy = ProgramTemplate(
      id: uuidV4(),
      name: l10n.programTemplateCopyName(_displayName(l10n, template)),
      entries: template.entries,
      eventRuleIds: template.eventRuleIds,
    );
    final ids = _ids;
    ids.insert(ids.indexOf(template.id) + 1, copy.id);
    await _write('duplicate', () async {
      await saveProgramTemplate(_settings, copy);
      await saveProgramTemplateOrder(_settings, ids);
    });
    if (mounted) await _reload();
  }

  /// Deletes [template] at once and offers Undo, asking first only when
  /// "Confirm before delete" is on. Undo writes the template back under its
  /// own key; the order and default were left alone, so it comes back as the
  /// default if it was one, and in its place unless the order changed since
  /// ([deleteProgramTemplate]).
  Future<void> _delete(ProgramTemplate template) async {
    final l10n = AppLocalizations.of(context);
    final name = _displayName(l10n, template);
    if (!await confirmDeleteIfEnabled(context, itemLabel: name)) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    final settings = _settings;
    final deleted = await _write(
      'delete',
      () => deleteProgramTemplate(settings, template.id),
    );
    if (!mounted) return;
    await _reload();
    if (!deleted) return;
    showUndoSnackBar(
      messenger,
      key: const ValueKey('program-template-delete-undo-snackbar'),
      actionKey: const ValueKey('program-template-delete-undo'),
      message: l10n.commonDeletedSnack(name),
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: accessibleNavigation,
      onUndo: () async {
        await saveProgramTemplate(settings, template);
        if (mounted) await _reload();
      },
    );
  }

  Future<void> _move(int oldIndex, int newIndex) async {
    final list = [..._templates.templates];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    setState(
      () => _templates = ProgramTemplates(
        templates: list,
        defaultId: _templates.defaultId,
      ),
    );
    final saved = await _write(
      'reorder',
      () => saveProgramTemplateOrder(_settings, [for (final t in list) t.id]),
    );
    if (!saved && mounted) await _reload();
  }

  Future<void> _moveBy(int index, int delta) async {
    final l10n = AppLocalizations.of(context);
    final target = index + delta;
    final name = _displayName(l10n, _templates.templates[index]);
    await _move(index, target);
    if (!mounted) return;
    announceMoved(
      context,
      name: name,
      position: target + 1,
      count: _templates.templates.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasList =
        !_loading && _error == null && _templates.templates.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsProgramTemplatesTitle)),
      // The floating New is for a list: the empty state carries its own
      // button, so it waits until there is a template.
      floatingActionButton: hasList
          ? adaptiveExtendedFab(
              context,
              key: const ValueKey('program-templates-add'),
              heroTag: 'program-templates-add',
              onPressed: _canAdd ? _create : null,
              icon: const Icon(Icons.add),
              label: l10n.programTemplateNew,
            )
          : null,
      body: SafeArea(child: _buildBody(l10n)),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return LoadErrorView(
        icon: LoadErrorView.errorGlyph(context),
        message: l10n.programTemplatesLoadError,
        onRetry: () {
          setState(() {
            _loading = true;
            _error = null;
          });
          unawaited(_reload());
        },
      );
    }
    final templates = _templates.templates;
    if (templates.isEmpty) {
      return EmptyState(
        key: const ValueKey('program-templates-empty'),
        icon: EmptyState.glyph(context, Icons.article_outlined),
        title: l10n.programTemplatesEmptyTitle,
        body: l10n.programTemplatesEmptyBody,
        actions: [
          FilledButton.icon(
            key: const ValueKey('program-templates-empty-add'),
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: Text(l10n.programTemplateNew),
          ),
        ],
      );
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: AppSpacing.fabClearance),
      itemCount: templates.length,
      onReorderItem: (oldIndex, newIndex) {
        if (newIndex == oldIndex) return;
        unawaited(_move(oldIndex, newIndex));
      },
      itemBuilder: (context, index) {
        final template = templates[index];
        final name = _displayName(l10n, template);
        final isDefault = template.id == _templates.defaultId;
        final slots = l10n.programTemplateSlotCount(template.entries.length);
        return ListTile(
          key: ValueKey('program-template-tile-${template.id}'),
          leading: ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle),
          ),
          title: Text(name),
          subtitle: Text(
            isDefault ? l10n.programTemplateDefaultWithSlots(slots) : slots,
          ),
          onTap: () => _edit(template),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReorderMoveButtons(
                keyPrefix: 'program-template-${template.id}',
                name: name,
                onMoveUp: index == 0 ? null : () => _moveBy(index, -1),
                onMoveDown: index == templates.length - 1
                    ? null
                    : () => _moveBy(index, 1),
              ),
              PopupMenuButton<_TemplateAction>(
                key: ValueKey('program-template-menu-${template.id}'),
                tooltip: l10n.programTemplateActionsTooltip(name),
                onSelected: (action) => switch (action) {
                  _TemplateAction.rename => _rename(template),
                  _TemplateAction.duplicate => _duplicate(template),
                  _TemplateAction.delete => _delete(template),
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: const ValueKey('program-template-rename'),
                    value: _TemplateAction.rename,
                    child: Text(l10n.programTemplateRename),
                  ),
                  PopupMenuItem(
                    key: const ValueKey('program-template-duplicate'),
                    value: _TemplateAction.duplicate,
                    enabled: _canAdd,
                    child: Text(l10n.commonDuplicate),
                  ),
                  PopupMenuItem(
                    key: const ValueKey('program-template-delete'),
                    value: _TemplateAction.delete,
                    child: Text(l10n.commonDelete),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _TemplateAction { rename, duplicate, delete }

/// Edits one template's name and slots. Every change is written at once, to
/// that template's own key only.
class ProgramTemplateEditorScreen extends StatefulWidget {
  const ProgramTemplateEditorScreen({super.key, required this.template});

  final ProgramTemplate template;

  @override
  State<ProgramTemplateEditorScreen> createState() =>
      _ProgramTemplateEditorScreenState();
}

class _ProgramTemplateEditorScreenState
    extends State<ProgramTemplateEditorScreen> {
  late ProgramTemplate _template = widget.template;
  // First read in build, where the localized name is available.
  late final TextEditingController _nameController = TextEditingController(
    text: programTemplateInitialName(
      AppLocalizations.of(context),
      widget.template,
    ),
  );
  late final List<ProgramTemplateEntry> _entries = [...widget.template.entries];

  /// The template's event rules (#2342), kept and saved whatever the Event
  /// rules toggle says: with it off the Rules row is hidden, but a save still
  /// writes this list, so turning the feature back on finds it unchanged.
  late List<String> _eventRuleIds = [...widget.template.eventRuleIds];

  /// Every event rule this device holds, tombstones included, by id, so the
  /// Rules row can name a deleted rule as removed (`null` until read).
  Map<String, EventRule>? _rulesById;

  /// The ids of the live rules in [_rulesById].
  Set<String> _liveRuleIds = const {};

  /// Re-reads the rules on each change to them, so a rule deleted, or brought
  /// back by Undo, while the editor is open shows as it now is.
  StreamSubscription<List<EventRule>>? _rulesWatch;

  /// Dance titles for the slot list, from the titles-only projection (`null`
  /// until it resolves, and for good if it failed). The full [CollectionData]
  /// is loaded only when the picker opens.
  Map<String, String>? _danceTitles;

  /// The names of the saved searches the slot rules can use (#2338), by id;
  /// a rule whose id is not here names a saved search that is gone. `null`
  /// until read.
  Map<String, String>? _savedSearchNames;

  /// Saved searches that are stored but cannot be read (Needs attention).
  Set<String> _unreadableSearchIds = const {};
  bool _started = false;
  CollectionData? _collectionData;
  Future<CollectionData?>? _collectionDataLoad;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final repos = RepositoriesScope.of(context);
      unawaited(_loadDanceTitles(repos.dances));
      unawaited(_loadSavedSearchNames(repos.savedSearches));
      _rulesWatch = repos.eventRules.watchAll().listen(
        (_) => unawaited(_loadRules(repos.eventRules)),
        onError: (Object error, StackTrace stackTrace) => logCaughtError(
          error,
          stackTrace,
          source: 'program_templates_screen.rules_watch',
        ),
      );
    }
  }

  /// Reads every rule, tombstones included, for the Rules row (#2342).
  Future<void> _loadRules(EventRuleRepository rules) async {
    try {
      final all = await rules.listAll(includeDeleted: true);
      final live = await rules.listAll();
      if (!mounted) return;
      setState(() {
        _rulesById = {for (final rule in all) rule.id: rule};
        _liveRuleIds = {for (final rule in live) rule.id};
      });
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'program_templates_screen.rules',
      );
    }
  }

  /// The Rules row (#2342): opens the program's rule picker, its ticks
  /// changing this template's list. The picker lists only live rules, so a
  /// deleted rule stays on the template, shown as removed, for its Undo;
  /// only once the template lists [maxProgramEventRules] ids is a deleted
  /// rule's let go to make room, as on a program ([toggleEventRuleId]).
  ///
  /// Unlike a program's picker, a tick applies to this editor's copy of the
  /// list, not to the list as stored at that moment: the editor writes the
  /// whole template, name and slots included, from its copy on every change,
  /// so a template edit synced in while it is open is overwritten either way
  /// (last writer wins, as for the template's other fields).
  Future<void> _openRules() async {
    await showProgramRulesPicker(
      context,
      applied: _eventRuleIds,
      forTemplate: true,
      onChange: (change) async {
        final next = change(_eventRuleIds);
        if (next != null && mounted) {
          _change(() => _eventRuleIds = normalizeEventRuleIds(next));
        }
        return _eventRuleIds;
      },
    );
  }

  /// What the Rules row says of rule [id]: its title, or that it is removed.
  String _ruleLine(AppLocalizations l10n, String id) {
    final rule = _rulesById?[id];
    if (rule == null) return l10n.programTemplateRuleRemovedUnknown;
    final title = eventRuleTitle(
      l10n,
      rule,
      _savedSearchNames?[rule.savedSearchId],
    );
    return _liveRuleIds.contains(id)
        ? title
        : l10n.programTemplateRuleRemoved(title);
  }

  Widget _rulesRow(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final known = _rulesById != null;
    return ListTile(
      key: const ValueKey('program-template-rules'),
      leading: const Icon(Icons.rule),
      title: Text(l10n.programTemplateRulesLabel),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_eventRuleIds.isEmpty)
            Text(l10n.programTemplateRulesNone)
          else if (known)
            for (final id in _eventRuleIds)
              Text(
                _ruleLine(l10n, id),
                key: ValueKey('program-template-rule-$id'),
                style: _liveRuleIds.contains(id)
                    ? null
                    : TextStyle(color: theme.colorScheme.onSurfaceVariant),
              )
          else
            // The rules are not read yet, or could not be: say how many the
            // template lists rather than nothing.
            Text(l10n.programsRulesButton(_eventRuleIds.length)),
          Text(l10n.programTemplateRulesHelp, style: theme.textTheme.bodySmall),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _openRules,
    );
  }

  /// Reads the saved searches a slot rule can name: the readable ones.
  Future<Map<String, String>?> _loadSavedSearchNames(
    SavedSearchRepository savedSearches,
  ) async {
    try {
      final stored = await savedSearches.list();
      final names = {
        for (final s in stored)
          if (s.search case final search?) search.id: search.name,
      };
      final unreadable = {
        for (final s in stored)
          if (s.search == null) s.savedSearchId,
      };
      if (mounted) {
        setState(() {
          _savedSearchNames = names;
          _unreadableSearchIds = unreadable;
        });
      }
      return names;
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'program_templates_screen.saved_searches',
      );
      return null;
    }
  }

  /// **Add slot rule** (#2338): a label and the saved search that says which
  /// dances it means. Without a saved search there is nothing to choose, and
  /// the dialog says where to make one.
  Future<void> _addRule() async {
    if (_ruleDialogBusy) return;
    _ruleDialogBusy = true;
    try {
      final names = await _loadSavedSearchNames(
        RepositoriesScope.of(context).savedSearches,
      );
      if (!mounted || names == null) return;
      final rule = await showDialog<ProgramTemplateEntry>(
        context: context,
        animationStyle: AppMotion.styleFor(context),
        builder: (_) => _SlotRuleDialog(savedSearches: names),
      );
      if (rule == null || !mounted) return;
      _change(() => _entries.add(rule));
    } finally {
      _ruleDialogBusy = false;
    }
  }

  /// Whether a slot rule dialog is opening or open, so a second tap on Add
  /// slot rule or Edit opens no second dialog.
  bool _ruleDialogBusy = false;

  /// **Edit** on the slot rule at [index]: the same dialog, filled in with its
  /// label and, while it can still be chosen, its saved search.
  Future<void> _editRule(int index) async {
    if (_ruleDialogBusy) return;
    final entry = _entries.elementAtOrNull(index);
    if (entry == null || !entry.isRule) return;
    _ruleDialogBusy = true;
    try {
      final names = await _loadSavedSearchNames(
        RepositoriesScope.of(context).savedSearches,
      );
      if (!mounted || names == null) return;
      final rule = await showDialog<ProgramTemplateEntry>(
        context: context,
        animationStyle: AppMotion.styleFor(context),
        builder: (_) => _SlotRuleDialog(savedSearches: names, initial: entry),
      );
      if (rule == null || !mounted) return;
      // The dialog is modal; still, find the rule again rather than trust
      // index.
      final at = identical(_entries.elementAtOrNull(index), entry)
          ? index
          : _entries.indexWhere((e) => identical(e, entry));
      if (at < 0) return;
      _change(() => _entries[at] = rule);
    } finally {
      _ruleDialogBusy = false;
    }
  }

  @override
  void dispose() {
    unawaited(_rulesWatch?.cancel());
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadDanceTitles(DanceRepository dances) async {
    try {
      final rows = await dances.listIdsAndTitles();
      if (!mounted) return;
      setState(
        () => _danceTitles = {for (final row in rows) row.id: row.title},
      );
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'program_templates_screen.dance_titles',
      );
    }
  }

  Future<void> _persist() async {
    final name = _nameController.text.trim();
    _template = _template.copyWith(
      // A blank name keeps the last one rather than saving an unnamed template.
      name: name.isEmpty ? _template.name : name,
      entries: List.unmodifiable(_entries),
      eventRuleIds: List.unmodifiable(_eventRuleIds),
    );
    try {
      await saveProgramTemplate(
        RepositoriesScope.of(context).settings,
        _template,
        checkNewSlotRules: true,
      );
    } on SavedSearchGone {
      // diagnostics: silent — expected, not a fault: a slot rule named a saved search deleted while its dialog was open (#2529); _slotRuleSearchGone says so.
      await _slotRuleSearchGone();
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'program_templates_screen.save',
      );
    }
  }

  /// A save was refused because a new or changed slot rule names a saved
  /// search that is no longer stored (#2529): nothing was written. Says so,
  /// puts the slots back as they are saved, and saves the rest (the name, the
  /// rules) again.
  Future<void> _slotRuleSearchGone() async {
    if (!mounted) return;
    final settings = RepositoriesScope.of(context).settings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('program-template-slot-rule-search-gone'),
        content: Text(
          AppLocalizations.of(
            context,
          ).programTemplateSlotRuleNotSavedSearchGone,
        ),
      ),
    );
    final templates = await loadProgramTemplates(settings);
    final stored = templates.templates
        .where((t) => t.id == _template.id)
        .firstOrNull;
    if (!mounted || stored == null) return;
    setState(
      () => _entries
        ..clear()
        ..addAll(stored.entries),
    );
    unawaited(
      _loadSavedSearchNames(RepositoriesScope.of(context).savedSearches),
    );
    await _persist();
  }

  void _change(VoidCallback edit) {
    setState(edit);
    unawaited(_persist());
  }

  /// The full collection snapshot, for the dance picker only. Each explicit
  /// tap on "add dance" retries a failed load.
  Future<CollectionData?> _ensureCollectionData() async {
    if (_collectionData != null) return _collectionData;
    final inFlight = _collectionDataLoad;
    if (inFlight != null) return inFlight;
    final repos = RepositoriesScope.of(context);
    final load = () async {
      try {
        final data = await CollectionData.load(repos);
        if (mounted) {
          setState(() {
            _collectionData = data;
            _danceTitles = {
              for (final entry in data.dancesById.entries)
                entry.key: entry.value.title,
            };
          });
        }
        return data;
      } catch (error, stackTrace) {
        logCaughtError(
          error,
          stackTrace,
          source: 'program_templates_screen.picker',
        );
        return null;
      } finally {
        _collectionDataLoad = null;
      }
    }();
    _collectionDataLoad = load;
    return load;
  }

  Future<void> _addDance() async {
    final data = await _ensureCollectionData();
    if (!mounted || data == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            ListTile(
              title: Text(
                AppLocalizations.of(
                  context,
                ).settingsDefaultsStartingProgramPickerTitle,
              ),
              trailing: IconButton(
                tooltip: AppLocalizations.of(context).commonClose,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ),
            Expanded(
              child: CollectionPicker(
                data: data,
                dialect: ActiveDialectScope.contraOf(context),
                enrichment: SearchEnrichment.empty,
                scrollController: scrollController,
                onAddDance: (danceId) => _change(
                  () => _entries.add(ProgramTemplateEntry(danceId: danceId)),
                ),
              ),
            ),
          ],
        ),
      ),
      sheetAnimationStyle: AppMotion.styleFor(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.programTemplateEditorTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: TextField(
                key: const ValueKey('program-template-editor-name'),
                controller: _nameController,
                inputFormatters: const [_nameLengthLimit],
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.programTemplateNameLabel,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => unawaited(_persist()),
              ),
            ),
            // Only while Event rules is on (#2342); the list is kept and
            // saved either way.
            if (EventRulesEnabledScope.of(context)) _rulesRow(l10n),
            ProgramTemplateSlotsEditor(
              entries: _entries,
              danceTitles: _danceTitles ?? const {},
              savedSearchNames: _savedSearchNames,
              unreadableSearchIds: _unreadableSearchIds,
              onAddDance: _addDance,
              onAddRule: _addRule,
              onEditRule: _editRule,
              onAddText: (text) =>
                  _change(() => _entries.add(ProgramTemplateEntry(text: text))),
              onUpdateText: (index, text) {
                final entry = _entries[index];
                _entries[index] = ProgramTemplateEntry(
                  danceId: entry.danceId,
                  text: text.isEmpty ? null : text,
                );
                unawaited(_persist());
              },
              onAddBreak: () => _change(
                () => _entries.add(
                  const ProgramTemplateEntry(text: Program.breakSlotText),
                ),
              ),
              onRemove: (index) => _change(() => _entries.removeAt(index)),
              onReorder: (oldIndex, newIndex) => _change(() {
                final entry = _entries.removeAt(oldIndex);
                _entries.insert(newIndex, entry);
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// A template's slot list: dances (each with an optional caller note), notes
/// and breaks, with move up / move down and remove, and buttons to add a
/// dance, a note or a break. Reports every edit through its callbacks.
class ProgramTemplateSlotsEditor extends StatefulWidget {
  const ProgramTemplateSlotsEditor({
    super.key,
    required this.entries,
    required this.danceTitles,
    this.savedSearchNames,
    this.unreadableSearchIds = const {},
    required this.onAddDance,
    this.onAddRule,
    this.onEditRule,
    required this.onAddText,
    required this.onUpdateText,
    required this.onAddBreak,
    required this.onRemove,
    required this.onReorder,
  });

  final List<ProgramTemplateEntry> entries;
  final Map<String, String> danceTitles;

  /// Saved-search names by id, to say which search each slot rule uses; an id
  /// missing from it is a search that is gone. `null` while unknown.
  final Map<String, String>? savedSearchNames;

  /// Saved searches that are stored but cannot be read, by id.
  final Set<String> unreadableSearchIds;
  final VoidCallback onAddDance;

  /// **Edit** on a slot rule (#2338); no Edit button when null.
  final ValueChanged<int>? onEditRule;

  /// **Add slot rule** (#2338), a secondary action after the two primary
  /// ones; omitted when null.
  final VoidCallback? onAddRule;
  final ValueChanged<String> onAddText;
  final void Function(int index, String text) onUpdateText;
  final VoidCallback onAddBreak;
  final ValueChanged<int> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  State<ProgramTemplateSlotsEditor> createState() =>
      _ProgramTemplateSlotsEditorState();
}

class _ProgramTemplateSlotsEditorState
    extends State<ProgramTemplateSlotsEditor> {
  final _textController = TextEditingController();
  late List<Object> _entryKeys;

  @override
  void initState() {
    super.initState();
    _entryKeys = List<Object>.generate(widget.entries.length, (_) => Object());
  }

  @override
  void didUpdateWidget(covariant ProgramTemplateSlotsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_entryKeys.length < widget.entries.length) {
      _entryKeys.addAll(
        List<Object>.generate(
          widget.entries.length - _entryKeys.length,
          (_) => Object(),
        ),
      );
    } else if (_entryKeys.length > widget.entries.length) {
      _entryKeys = _entryKeys.sublist(0, widget.entries.length);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String _ruleSubtitle(AppLocalizations l10n, String savedSearchId) {
    final names = widget.savedSearchNames;
    if (names == null) return l10n.programTemplateSlotRuleBadge;
    final name = names[savedSearchId];
    if (name != null) return l10n.programTemplateSlotRuleSubtitle(name);
    return widget.unreadableSearchIds.contains(savedSearchId)
        ? l10n.programTemplateSlotRuleSearchUnreadable
        : l10n.programTemplateSlotRuleSearchGone;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.programTemplateSlotsHeader,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.programTemplateSlotsSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (var index = 0; index < widget.entries.length; index++)
            Builder(
              builder: (context) {
                final entry = widget.entries[index];
                return ListTile(
                  key: ValueKey(
                    'program-template-slot-${identityHashCode(_entryKeys[index])}',
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: entry.isRule
                      ? Icon(
                          Icons.manage_search,
                          semanticLabel: l10n.programTemplateSlotRuleBadge,
                        )
                      : null,
                  title: Text(
                    entry.danceId == null
                        ? entry.text ?? ''
                        : widget.danceTitles[entry.danceId] ??
                              l10n.settingsDefaultsStartingProgramUnavailableDance,
                  ),
                  subtitle: entry.isRule
                      ? Text(
                          _ruleSubtitle(l10n, entry.savedSearchId!),
                          key: ValueKey(
                            'program-template-rule-subtitle-$index',
                          ),
                        )
                      : entry.danceId == null
                      ? null
                      : TextFormField(
                          key: ValueKey(_entryKeys[index]),
                          initialValue: entry.text ?? '',
                          decoration: InputDecoration(
                            labelText:
                                l10n.settingsDefaultsStartingProgramNoteLabel,
                          ),
                          onChanged: (value) =>
                              widget.onUpdateText(index, value.trim()),
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (entry.isRule && widget.onEditRule != null)
                        IconButton(
                          key: ValueKey('program-template-rule-edit-$index'),
                          tooltip: l10n.commonEdit,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => widget.onEditRule!(index),
                        ),
                      IconButton(
                        tooltip: l10n.settingsDefaultsStartingProgramMoveUp,
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: index == 0
                            ? null
                            : () {
                                setState(() {
                                  final key = _entryKeys.removeAt(index);
                                  _entryKeys.insert(index - 1, key);
                                });
                                widget.onReorder(index, index - 1);
                              },
                      ),
                      IconButton(
                        tooltip: l10n.settingsDefaultsStartingProgramMoveDown,
                        icon: const Icon(Icons.arrow_downward),
                        onPressed: index == widget.entries.length - 1
                            ? null
                            : () {
                                setState(() {
                                  final key = _entryKeys.removeAt(index);
                                  _entryKeys.insert(index + 1, key);
                                });
                                widget.onReorder(index, index + 1);
                              },
                      ),
                      IconButton(
                        tooltip: l10n.commonDelete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() => _entryKeys.removeAt(index));
                          widget.onRemove(index);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('program-template-add-dance'),
                onPressed: widget.onAddDance,
                icon: const Icon(Icons.library_music_outlined),
                label: Text(l10n.programsAddDanceButton),
              ),
              OutlinedButton.icon(
                key: const ValueKey('program-template-add-text'),
                onPressed: () {
                  final text = _textController.text.trim();
                  if (text.isEmpty) return;
                  widget.onAddText(text);
                  _textController.clear();
                },
                icon: const Icon(Icons.notes_outlined),
                label: Text(l10n.programsAddNoteBreakButton),
              ),
              OutlinedButton.icon(
                key: const ValueKey('program-template-insert-break'),
                onPressed: widget.onAddBreak,
                icon: const Icon(Icons.free_breakfast_outlined),
                label: Text(l10n.programsInsertBreakButton),
              ),
              // Secondary (#2338): a template of fixed dances and text is
              // complete without one, so it is a text button after the
              // primary actions, never the default kind of slot.
              if (widget.onAddRule case final onAddRule?)
                TextButton.icon(
                  key: const ValueKey('program-template-add-rule'),
                  onPressed: onAddRule,
                  icon: const Icon(Icons.manage_search),
                  label: Text(l10n.programTemplateAddSlotRule),
                ),
            ],
          ),
          TextField(
            key: const ValueKey('program-template-text-field'),
            controller: _textController,
            decoration: InputDecoration(
              labelText: l10n.settingsDefaultsStartingProgramTextLabel,
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a slot rule (#2338): a label, and one of the user's saved searches
/// ([savedSearches], names by id). Pops the rule, or nothing on Cancel. With no
/// saved search it only says where to save one.
class _SlotRuleDialog extends StatefulWidget {
  const _SlotRuleDialog({required this.savedSearches, this.initial});

  /// The rule being edited, or null for a new one.
  final ProgramTemplateEntry? initial;

  final Map<String, String> savedSearches;

  @override
  State<_SlotRuleDialog> createState() => _SlotRuleDialogState();
}

class _SlotRuleDialogState extends State<_SlotRuleDialog> {
  final _label = TextEditingController();
  String? _searchId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _label.text = initial.text ?? '';
      // A search that is gone or unreadable cannot be chosen again: the
      // field starts empty, and Save waits for one that can.
      if (widget.savedSearches.containsKey(initial.savedSearchId)) {
        _searchId = initial.savedSearchId;
      }
    }
    _label.addListener(() => setState(() {}));
  }

  /// The label is the word that marks a break slot: refused, since a slot
  /// with it would read as a break (as the slot edit dialog's break check).
  bool get _labelIsBreak => isProgramTemplateBreakText(_label.text);

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _searchId != null && _label.text.trim().isNotEmpty && !_labelIsBreak;

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(
      ProgramTemplateEntry.rule(
        savedSearchId: _searchId!,
        label: _label.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final searches = widget.savedSearches.entries.toList()
      ..sort((a, b) {
        final byName = a.value.toLowerCase().compareTo(b.value.toLowerCase());
        return byName != 0 ? byName : a.key.compareTo(b.key);
      });
    // Adding needs a saved search to choose; editing still lets the label
    // change, and says there is no search to choose.
    if (searches.isEmpty && widget.initial == null) {
      return AlertDialog(
        key: const ValueKey('program-template-rule-no-searches'),
        title: Text(l10n.programTemplateSlotRuleDialogTitle),
        content: Text(l10n.programTemplateSlotRuleNoSearches),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonOk),
          ),
        ],
      );
    }
    return AlertDialog(
      key: const ValueKey('program-template-rule-dialog'),
      title: Text(
        widget.initial == null
            ? l10n.programTemplateSlotRuleDialogTitle
            : l10n.programTemplateSlotRuleEditTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.programTemplateSlotRuleDialogBody),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('program-template-rule-label'),
              controller: _label,
              autofocus: true,
              maxLength: kMaxProgramTemplateTextLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.programTemplateSlotRuleLabel,
                hintText: l10n.programTemplateSlotRuleLabelHint,
                counterText: '',
                errorText: _labelIsBreak
                    ? l10n.programTemplateSlotRuleLabelBreak
                    : null,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (searches.isEmpty)
              Text(
                l10n.programTemplateSlotRuleNoSearches,
                key: const ValueKey('program-template-rule-no-searches-note'),
              )
            else
              AppDropdownField<String?>(
                key: const ValueKey('program-template-rule-search'),
                value: _searchId,
                filterable: searches.length >= appDropdownFilterFrom,
                decoration: InputDecoration(
                  labelText: l10n.programTemplateSlotRuleSearch,
                ),
                entries: [
                  for (final search in searches)
                    AppDropdownEntry<String?>(
                      value: search.key,
                      label: search.value,
                      key: ValueKey(
                        'program-template-rule-search-${search.key}',
                      ),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _searchId = id;
                  // A rule is often named after its search: start from that.
                  if (_label.text.trim().isEmpty && id != null) {
                    _label.text = widget.savedSearches[id] ?? '';
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('program-template-rule-save'),
          onPressed: _canSave ? _save : null,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
