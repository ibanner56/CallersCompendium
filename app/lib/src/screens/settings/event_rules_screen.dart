import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/repositories_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../theme/app_spacing.dart';
import '../../utils/confirm_delete.dart';
import '../../utils/undo_snack_bar.dart';
import '../../widgets/app_bar_text_action.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/confirm_discard_changes.dart';
import '../../widgets/event_rule_text.dart';
import '../../widgets/reorder_move_buttons.dart';

/// The names of the readable saved searches, by id, read again with each
/// change to the rules.
Future<Map<String, String>> _savedSearchNames(
  CompendiumRepositories repos,
) async => {
  for (final stored in await repos.savedSearches.list())
    if (stored.search case final search?) search.id: search.name,
};

/// **Manage rules** (#2340): the caller's event rules, to view, add, edit,
/// reorder (#2341) and delete (with Undo). Reached from Settings ▸ Experimental ▸ Event rules,
/// and from Settings ▸ Program while the feature is on.
class EventRulesScreen extends StatefulWidget {
  const EventRulesScreen({super.key});

  @override
  State<EventRulesScreen> createState() => _EventRulesScreenState();
}

class _EventRulesScreenState extends State<EventRulesScreen> {
  StreamSubscription<List<EventRule>>? _subscription;
  List<EventRule>? _rules;
  Map<String, String> _searchNames = const {};

  /// Whether [_searchNames] is the latest read's. After a failed read it is
  /// the last good read's (or empty), which may miss a search a sync has
  /// just brought or still hold one deleted since, so no rule is shown as
  /// needing attention for its search until a read succeeds.
  bool _searchNamesKnown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subscription != null) return;
    final repos = RepositoriesScope.of(context);
    _subscription = repos.eventRules.watchAll().listen(
      (rules) async {
        // A failed read of the saved search names still lists the rules,
        // named with the names last read (or none), rather than never
        // listing them; it flags no rule for its search.
        Map<String, String>? names;
        try {
          names = await _savedSearchNames(repos);
        } catch (error, stackTrace) {
          logCaughtError(
            error,
            stackTrace,
            source: 'event_rules_screen.search_names',
          );
        }
        if (!mounted) return;
        setState(() {
          _rules = rules;
          _searchNamesKnown = names != null;
          if (names != null) _searchNames = names;
        });
      },
      onError: (Object error, StackTrace stackTrace) => logCaughtError(
        error,
        stackTrace,
        source: 'event_rules_screen.rules_watch',
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _edit([EventRule? rule]) async {
    await showEventRuleEditor(context, rule: rule);
  }

  Future<void> _delete(EventRule rule) async {
    final l10n = AppLocalizations.of(context);
    final label = eventRuleTitle(l10n, rule, _searchNames[rule.savedSearchId]);
    if (!await confirmDeleteIfEnabled(context, itemLabel: label)) return;
    if (!mounted) return;
    final repos = RepositoriesScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    try {
      await repos.eventRules.delete(rule.id);
      showUndoSnackBar(
        messenger,
        key: const ValueKey('event-rule-undo-snackbar'),
        actionKey: const ValueKey('event-rule-undo'),
        message: l10n.eventRuleDeletedSnack,
        undoLabel: l10n.commonUndo,
        undoFailedMessage: l10n.commonUndoFailed,
        accessibleNavigation: accessibleNavigation,
        onUndo: () => repos.eventRules.restore(rule.id),
      );
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'event_rules_screen._delete');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rules = _rules;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsExperimentalEventRulesHeader)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('event-rules-new'),
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: Text(l10n.eventRulesNewRule),
      ),
      body: rules == null
          ? const Center(child: CircularProgressIndicator())
          : rules.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                l10n.eventRulesEmpty,
                key: const ValueKey('event-rules-empty'),
              ),
            )
          // The caller's order (#2341): drag a rule by its handle, or move it
          // with Move up / Move down, never drag alone (the Matrix columns
          // editor's precedent). The program's rule picker lists rules in
          // this order under Rule order's My order.
          : ReorderableListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.fabClearance),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) => _move(rules, from, to),
              children: [
                for (var i = 0; i < rules.length; i++)
                  _EventRuleTile(
                    key: ValueKey('event-rule-${rules[i].id}'),
                    rule: rules[i],
                    index: i,
                    searchName: _searchNames[rules[i].savedSearchId],
                    searchNamesKnown: _searchNamesKnown,
                    onTap: () => _edit(rules[i]),
                    onDelete: () => _delete(rules[i]),
                    onMoveUp: i == 0
                        ? null
                        : () => _move(rules, i, i - 1, announce: true),
                    onMoveDown: i == rules.length - 1
                        ? null
                        : () => _move(rules, i, i + 1, announce: true),
                  ),
              ],
            ),
    );
  }

  /// Moves the rule at [from] in [rules] to [to]: on screen at once, then
  /// stored ([EventRuleRepository.reorder]), which the list's watch shows.
  /// With [announce], a screen reader hears where it landed (Move up / Move
  /// down keep their focus while the row moves). If the write fails, the list
  /// goes back to [rules], the order still stored.
  Future<void> _move(
    List<EventRule> rules,
    int from,
    int to, {
    bool announce = false,
  }) async {
    if (from == to || to < 0 || to >= rules.length) return;
    final order = [...rules];
    final moved = order.removeAt(from);
    order.insert(to, moved);
    setState(() => _rules = order);
    final repos = RepositoriesScope.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await repos.eventRules.reorder([for (final r in order) r.id]);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'event_rules_screen._move');
      if (mounted) setState(() => _rules = rules);
      return;
    }
    if (announce && mounted) {
      announceMoved(
        context,
        name: eventRuleTitle(l10n, moved, _searchNames[moved.savedSearchId]),
        position: to + 1,
        count: order.length,
      );
    }
  }
}

class _EventRuleTile extends StatelessWidget {
  const _EventRuleTile({
    super.key,
    required this.rule,
    required this.index,
    required this.searchName,
    required this.searchNamesKnown,
    required this.onTap,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final EventRule rule;
  final int index;
  final String? searchName;

  /// Whether the saved search names were read; while not, a rule is flagged
  /// only for what it says itself (a newer version made it).
  final bool searchNamesKnown;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sentence = eventRuleSentence(l10n, rule, searchName);
    final title = rule.nickname ?? sentence;
    final attention = searchNamesKnown || !rule.isReadable
        ? eventRuleListAttention(rule, searchName)
        : null;
    return ListTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: Semantics(
          label: l10n.eventRulesDragToReorder(title),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Icon(Icons.drag_handle),
          ),
        ),
      ),
      // The nickname (#2341) is the title, with the sentence beneath it; a
      // rule without one shows its sentence alone.
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rule.nickname != null) Text(sentence),
          if (attention != null) EventRuleAttentionNote(attention: attention),
        ],
      ),
      // A rule a newer version wrote cannot be edited here; it can still be
      // moved and deleted.
      onTap: rule.isReadable ? onTap : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderMoveButtons(
            keyPrefix: 'event-rule-${rule.id}',
            name: title,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
          ),
          IconButton(
            key: ValueKey('event-rule-delete-${rule.id}'),
            tooltip: l10n.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Opens the rule editor for [rule], or for a new rule when it is null,
/// its Nickname field holding [nickname] (the picker's search text, #2341).
/// Returns the rule as saved, or null when nothing was saved.
Future<EventRule?> showEventRuleEditor(
  BuildContext context, {
  EventRule? rule,
  String? nickname,
}) => Navigator.of(context).push<EventRule>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => EventRuleEditorScreen(rule: rule, nickname: nickname),
  ),
);

/// The rule editor (#2340): which dances (a saved search), how many, and
/// where, with the sentence the rule reads as, and an optional nickname
/// (#2341).
class EventRuleEditorScreen extends StatefulWidget {
  const EventRuleEditorScreen({super.key, this.rule, this.nickname});

  /// The rule to edit, or null for a new one.
  final EventRule? rule;

  /// The nickname a new rule starts with; ignored when editing [rule].
  final String? nickname;

  @override
  State<EventRuleEditorScreen> createState() => _EventRuleEditorScreenState();
}

class _EventRuleEditorScreenState extends State<EventRuleEditorScreen> {
  late final TextEditingController _count = TextEditingController(
    text: '${(widget.rule?.count ?? 0) > 0 ? widget.rule!.count : 1}',
  );
  late final TextEditingController _nickname = TextEditingController(
    text: widget.rule == null
        ? _clipNickname(widget.nickname?.trim() ?? '')
        : widget.rule!.nickname ?? '',
  );

  /// [text] cut to the field's [maxEventRuleNicknameLength] code units, by
  /// whole characters, so an emoji is never split.
  static String _clipNickname(String text) {
    if (text.length <= maxEventRuleNicknameLength) return text;
    final kept = StringBuffer();
    for (final character in text.characters) {
      if (kept.length + character.length > maxEventRuleNicknameLength) break;
      kept.write(character);
    }
    return kept.toString();
  }

  late String? _searchId = widget.rule?.savedSearchId;
  late EventRuleQuantifier _quantifier =
      widget.rule?.quantifier ?? EventRuleQuantifier.atMost;
  late EventRuleScope _scope =
      widget.rule?.scope ?? EventRuleScope.wholeProgram;
  Map<String, String>? _searches;
  bool _saving = false;

  /// The fields as the editor opened, for [_dirty]. The search is the one
  /// the editor could offer: a rule whose search is gone opens with none.
  late final String _initialCount;
  late final String _initialNickname;
  String? _initialSearchId;
  late final EventRuleQuantifier _initialQuantifier;
  late final EventRuleScope _initialScope;

  /// Whether leaving now would lose a change made here. While it would,
  /// Back and the app bar's back arrow ask first ([DiscardChangesGuard]).
  bool get _dirty =>
      _count.text != _initialCount ||
      _nickname.text != _initialNickname ||
      _searchId != _initialSearchId ||
      _quantifier != _initialQuantifier ||
      _scope != _initialScope;

  /// Whether the number, the quantifier or the scope has changed here. Until
  /// then a stored rule's number stands as it is, even one past what its
  /// scope now allows (stored before that limit, or by another build), so
  /// the rule can still be renamed and saved.
  bool _countTouched = false;

  @override
  void initState() {
    super.initState();
    _initialCount = _count.text;
    _initialNickname = _nickname.text;
    _initialSearchId = _searchId;
    _initialQuantifier = _quantifier;
    _initialScope = _scope;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_searches == null) unawaited(_read());
  }

  Future<void> _read() async {
    final names = await _savedSearchNames(RepositoriesScope.of(context));
    if (!mounted) return;
    final first = _searches == null;
    setState(() {
      _searches = names;
      if (_searchId != null && !names.containsKey(_searchId)) {
        _searchId = null;
      }
      // Nothing can be edited until the first read is in, so a search found
      // gone then is not a change the user made.
      if (first) _initialSearchId = _searchId;
    });
  }

  @override
  void dispose() {
    _count.dispose();
    _nickname.dispose();
    super.dispose();
  }

  /// The most the number may be for the quantifier and scope chosen: a
  /// neighbouring pair holds only two dances.
  int get _countLimit => eventRuleCountLimit(_quantifier, _scope);

  int? get _countValue {
    if (_quantifier == EventRuleQuantifier.none) return 0;
    final value = int.tryParse(_count.text.trim());
    if (value == null || value < 1) return null;
    if (!_countTouched && widget.rule != null) return value;
    if (value > _countLimit) return null;
    return value;
  }

  /// After the quantifier or scope changed: a number past what it now allows
  /// becomes the most it allows, so "at most 3" moved to neighbouring dances
  /// reads "at most 1" rather than a rule that could never break.
  void _clampCount() {
    _countTouched = true;
    final value = int.tryParse(_count.text.trim());
    if (value != null && value > _countLimit) _count.text = '$_countLimit';
  }

  bool get _canSave => !_saving && _searchId != null && _countValue != null;

  EventRule _draft(String id, int position) => EventRule.of(
    id: id,
    savedSearchId: _searchId!,
    quantifier: _quantifier,
    count: _countValue!,
    scope: _scope,
    nickname: _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
    position: position,
  );

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final repos = RepositoriesScope.of(context);
    final navigator = Navigator.of(context);
    try {
      final existing = widget.rule;
      final EventRule saved;
      if (existing == null) {
        saved = await repos.eventRules.create(
          savedSearchId: _searchId!,
          quantifier: _quantifier,
          count: _countValue!,
          scope: _scope,
          nickname: _nickname.text.trim().isEmpty
              ? null
              : _nickname.text.trim(),
        );
      } else {
        await repos.eventRules.save(_draft(existing.id, existing.position));
        saved = (await repos.eventRules.get(existing.id))!;
      }
      navigator.pop(saved);
    } on SavedSearchGone {
      // diagnostics: silent — expected, not a fault: the saved search was deleted after the editor opened (#2529); the editor says so and offers the searches that are left.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('event-rule-saved-search-gone'),
          content: Text(AppLocalizations.of(context).eventRuleSavedSearchGone),
        ),
      );
      setState(() {
        _saving = false;
        // Cleared now, not only once the list is read again, so a second tap
        // cannot try the same search.
        _searchId = null;
      });
      await _read();
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'event_rule_editor._save');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final searches = _searches;
    final countError =
        _quantifier != EventRuleQuantifier.none && _countValue == null
        ? (_countLimit == 1
              ? l10n.eventRuleCountOnlyOne
              : l10n.eventRuleCountInvalid(_countLimit))
        : null;
    final preview = _searchId == null || _countValue == null
        ? null
        : eventRuleSentence(
            l10n,
            _draft(widget.rule?.id ?? 'new', 0),
            searches?[_searchId],
          );
    // The text fields are read through their controllers; the other fields
    // change by setState, which rebuilds this too.
    return ListenableBuilder(
      listenable: Listenable.merge([_count, _nickname]),
      builder: (context, child) =>
          // While a save is in flight the editor cannot be left: leaving then
          // would hide the save's failure.
          DiscardChangesGuard(dirty: _dirty, busy: _saving, child: child!),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.rule == null
                ? l10n.eventRuleEditorNewTitle
                : l10n.eventRuleEditorEditTitle,
          ),
          actions: [
            AppBarTextAction(
              key: const ValueKey('event-rule-save'),
              label: l10n.commonSave,
              icon: Icons.check,
              onPressed: _canSave ? _save : null,
            ),
          ],
        ),
        body: searches == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  if (preview != null) ...[
                    Text(
                      preview,
                      key: const ValueKey('event-rule-preview'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (searches.isEmpty)
                    Text(
                      l10n.eventRuleNoSavedSearches,
                      key: const ValueKey('event-rule-no-searches'),
                    )
                  else
                    AppDropdownField<String?>(
                      key: const ValueKey('event-rule-search'),
                      value: _searchId,
                      filterable: searches.length >= appDropdownFilterFrom,
                      decoration: InputDecoration(
                        labelText: l10n.eventRuleSearchLabel,
                      ),
                      entries: [
                        for (final MapEntry(key: id, value: name)
                            in searches.entries)
                          AppDropdownEntry(
                            value: id,
                            label: name,
                            key: ValueKey('event-rule-search-$id'),
                          ),
                      ],
                      onChanged: (id) => setState(() => _searchId = id),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.eventRuleQuantifierLabel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SegmentedButton<EventRuleQuantifier>(
                    key: const ValueKey('event-rule-quantifier'),
                    segments: [
                      for (final q in EventRuleQuantifier.values)
                        ButtonSegment(
                          value: q,
                          label: Text(eventRuleQuantifierLabel(l10n, q)),
                        ),
                    ],
                    selected: {_quantifier},
                    onSelectionChanged: (s) => setState(() {
                      _quantifier = s.single;
                      _clampCount();
                    }),
                  ),
                  if (_quantifier != EventRuleQuantifier.none) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      key: const ValueKey('event-rule-count'),
                      controller: _count,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l10n.eventRuleCountLabel,
                        errorText: countError,
                        helperText: _scope == EventRuleScope.neighbouring
                            ? l10n.eventRuleCountNeighbouringHelp
                            : null,
                        helperMaxLines: 3,
                      ),
                      onChanged: (_) => setState(() => _countTouched = true),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.eventRuleScopeLabel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  RadioGroup<EventRuleScope>(
                    groupValue: _scope,
                    onChanged: (s) {
                      if (s == null) return;
                      setState(() {
                        _scope = s;
                        _clampCount();
                      });
                    },
                    child: Column(
                      children: [
                        for (final s in EventRuleScope.values)
                          RadioListTile<EventRuleScope>(
                            key: ValueKey('event-rule-scope-${s.name}'),
                            value: s,
                            title: Text(eventRuleScopeLabel(l10n, s)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const ValueKey('event-rule-nickname'),
                    controller: _nickname,
                    maxLength: maxEventRuleNicknameLength,
                    decoration: InputDecoration(
                      labelText: l10n.eventRuleNicknameLabel,
                      helperText: l10n.eventRuleNicknameHelp,
                      helperMaxLines: 3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
