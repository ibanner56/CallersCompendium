import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart'
    show
        BooleanExpressionOperators,
        OrderingTerm,
        ResultSetImplementation,
        StringExpressionOperators,
        TableUpdate,
        TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../screens/settings/event_rules_screen.dart';
import '../search/event_rule_check.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'event_rule_text.dart';
import 'program_slot_list_editor.dart' show SlotRuleMarker;

/// Checks a program's applied event rules whenever the program or the rules
/// change (#2340), for the builder's Rules strip and slot markers.
///
/// It also re-checks when what a check reads changes with no edit to the
/// program: a saved search, the dances and what a search matches on them, the
/// calling history a Called filter counts, or what a search resolves against.
///
/// - **The search context** ([SavedSearchContext], about eight table reads)
///   is read once and kept until a table it reads, or the host's [update]
///   `contextKey`, changes; a slot edit reuses it. It reads nothing from
///   `settings`: the Calling history settings reach it through `contextKey`.
/// - **Settings.** Drift reports a write to `settings` without its key, and
///   that table also takes the builder's draft autosaves, window sizes and
///   sync state. So a `settings` write re-checks only when the saved-search
///   rows (`saved_search:*`, read by every check) differ from the last
///   check's, and never drops the context.
/// - **Bursts.** Changes are gathered until the next frame, and a check never
///   starts while another runs: the latest inputs are checked once it ends,
///   so a sync's stream of writes does not pile checks up.
///
/// It does nothing while the feature is off: [update] with `enabled` false
/// clears the result, drops its watches and never calls the evaluator or
/// reads a rule. It never notifies during the call that changed it, so a host
/// may call [update] from `build`.
class ProgramEventRulesController extends ChangeNotifier {
  ProgramEventRulesController({
    required this.repos,
    this.evaluate = evaluateEventRules,
  });

  final CompendiumRepositories repos;
  final EventRuleEvaluator evaluate;

  EventRuleCheck _check = EventRuleCheck.empty;
  EventRuleCheck get check => _check;

  /// Bumped each time [check] is replaced: a check of the program ran, or
  /// the feature was turned off. A picker marking suggestions
  /// ([checkCandidates]) checks them again when it changes, since the rules
  /// or what they read may have.
  int get checkGeneration => _checkGeneration;
  int _checkGeneration = 0;

  /// The ids of the rules this device holds deleted (tombstones), once read.
  Set<String>? _deletedRuleIds;

  /// What of [ids] the Rules button counts: every id but those of rules this
  /// device holds deleted (kept on the program for their Undo). A rule
  /// another device added that has not arrived here yet still counts: it is
  /// applied, only not yet here.
  int countedRules(List<String> ids) {
    final deleted = _deletedRuleIds;
    return deleted == null
        ? ids.length
        : ids.where((id) => !deleted.contains(id)).length;
  }

  StreamSubscription<List<EventRule>>? _rulesWatch;
  StreamSubscription<Set<TableUpdate>>? _tablesWatch;
  int _rulesGeneration = 0;

  /// Bumped by a write to a table a check reads ([_tablesWatch]).
  int _dataGeneration = 0;

  /// The saved-search rows as the last look found them, to tell a write that
  /// changed one from any other `settings` write.
  String? _savedSearchRows;

  /// The search context, read at most once per [_contextKey] and dropped
  /// when a table it reads changes.
  Future<SavedSearchContext>? _context;
  Object? _contextKey;

  /// Context reads started: a test seam for the cache.
  @visibleForTesting
  int contextReads = 0;

  bool _frameScheduled = false;
  bool _running = false;
  bool _rerun = false;
  int? _lastKey;
  int _seq = 0;
  _Inputs? _inputs;
  bool _disposed = false;

  /// Re-checks when the inputs differ from the last check's.
  void update({
    required bool enabled,
    required List<String> ruleIds,
    required List<ProgramSlot> slots,
    required Future<SavedSearchContext> Function() readContext,
    Object? contextKey,
    Dialect? dialect,
    SearchEnrichment? enrichment,
  }) {
    if (!enabled) {
      _inputs = null;
      _lastKey = null;
      _seq++;
      unawaited(_rulesWatch?.cancel());
      _rulesWatch = null;
      _deletedRuleIds = null;
      unawaited(_tablesWatch?.cancel());
      _tablesWatch = null;
      _context = null;
      _savedSearchRows = null;
      if (!identical(_check, EventRuleCheck.empty)) {
        _check = EventRuleCheck.empty;
        _checkGeneration++;
        _notifyLater();
      }
      return;
    }
    // The host's own inputs to the context (the program's id, the Calling
    // history settings, the day) changed: read it again.
    if (contextKey != _contextKey) {
      _contextKey = contextKey;
      _context = null;
    }
    _inputs = _Inputs(ruleIds, slots, readContext, dialect, enrichment);
    // A rule edited in the manager (or by sync) changes what it says. The
    // first list only says which rules are here.
    _rulesWatch ??= repos.eventRules.watchAll().listen((live) async {
      final first = _deletedRuleIds == null;
      final liveIds = {for (final r in live) r.id};
      final all = await repos.eventRules.listAll(includeDeleted: true);
      if (_disposed || _rulesWatch == null) return;
      _deletedRuleIds = {
        for (final r in all)
          if (!liveIds.contains(r.id)) r.id,
      };
      if (!first) {
        _rulesGeneration++;
        _schedule();
      }
      _notifyLater();
    });
    _tablesWatch ??= _watchTables();
    // At once, not at the next frame: a host calls this from `build`, and a
    // frame asked for here would ask for the next.
    _run();
  }

  /// Watches every table a check reads besides the rules. A write to one the
  /// search context reads drops the kept context too.
  StreamSubscription<Set<TableUpdate>> _watchTables() {
    final db = repos.db;
    // What the context reads (`readSavedSearchContext`).
    final contextTables = <ResultSetImplementation<dynamic, dynamic>>{
      db.tags,
      db.choreographers,
      db.publishedSources,
      db.difficultyLevels,
      db.venues,
      db.userGlossaryEntries,
      db.customFieldDefs,
      db.idAliases,
    };
    // What a search matches on a dance, and the calling history it counts.
    final dataTables = <ResultSetImplementation<dynamic, dynamic>>{
      db.dances,
      db.danceTags,
      db.danceAuthors,
      db.danceInterpreters,
      db.danceFigures,
      db.danceSources,
      db.customFieldValues,
      db.programs,
      db.programSlots,
    };
    final contextNames = {for (final t in contextTables) t.entityName};
    final dataNames = {for (final t in dataTables) t.entityName};
    final settingsName = db.settings.entityName;
    return db
        .tableUpdates(
          TableUpdateQuery.onAllTables({
            ...contextTables,
            ...dataTables,
            db.settings,
          }),
        )
        .listen((updates) async {
          final tables = {for (final u in updates) u.table};
          if (tables.any(contextNames.contains)) _context = null;
          var changed =
              tables.any(contextNames.contains) ||
              tables.any(dataNames.contains);
          if (!changed && tables.contains(settingsName)) {
            changed = await _savedSearchesChanged();
          }
          if (!changed || _disposed) return;
          _dataGeneration++;
          _schedule();
        });
  }

  /// Whether the saved-search rows differ from the last look: one query over
  /// their keys, values and deletion stamps. The values, not the edit stamps:
  /// the store keeps whole seconds, so an edit in the same second as the last
  /// look can carry the same stamp.
  Future<bool> _savedSearchesChanged() async {
    final db = repos.db;
    final key = db.settings.key;
    final value = db.settings.valueJson;
    final deletedAt = db.settings.deletedAt;
    final rows =
        await (db.selectOnly(db.settings)
              ..addColumns([key, value, deletedAt])
              ..where(key.like('$savedSearchKeyPrefix%'))
              ..orderBy([OrderingTerm.asc(key)]))
            .get();
    final seen = [
      for (final row in rows)
        if (row.read(key) case final k? when k.startsWith(savedSearchKeyPrefix))
          '$k ${row.read(deletedAt)} ${row.read(value)}',
    ].join('\n');
    final before = _savedSearchRows;
    _savedSearchRows = seen;
    return before != null && before != seen;
  }

  /// Runs a check at the next frame, once for every change before it.
  void _schedule() {
    if (_frameScheduled || _disposed) return;
    _frameScheduled = true;
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (!_disposed) _run();
    });
    binding.ensureVisualUpdate();
  }

  void _run() {
    final inputs = _inputs;
    if (inputs == null) return;
    // One check at a time: a change while one runs is checked after it, with
    // the inputs as they are then.
    if (_running) {
      _rerun = true;
      return;
    }
    final key = Object.hash(
      Object.hashAll(inputs.ruleIds),
      Object.hashAll(inputs.slots),
      _rulesGeneration,
      _dataGeneration,
      _contextKey,
    );
    if (key == _lastKey) return;
    _lastKey = key;
    final seq = ++_seq;
    if (inputs.ruleIds.isEmpty) {
      if (!identical(_check, EventRuleCheck.empty)) {
        _check = EventRuleCheck.empty;
        _checkGeneration++;
        _notifyLater();
      }
      return;
    }
    _running = true;
    unawaited(() async {
      try {
        // The rows this check reads, so a later `settings` write can be told
        // apart from one that changed none of them.
        if (_savedSearchRows == null) await _savedSearchesChanged();
        final result = await checkEventRules(
          repos: repos,
          ruleIds: inputs.ruleIds,
          slots: inputs.slots,
          readContext: () => _sharedContext(inputs),
          dialect: inputs.dialect,
          enrichment: inputs.enrichment,
          evaluate: evaluate,
        );
        if (_disposed || seq != _seq) return;
        _check = result;
        _checkGeneration++;
        notifyListeners();
      } catch (error, stackTrace) {
        // A rule that cannot be checked never blocks the builder. A context
        // that failed to read is read again next time, not kept.
        _context = null;
        logCaughtError(error, stackTrace, source: 'program_event_rules.check');
      } finally {
        _running = false;
        if (_rerun && !_disposed) {
          _rerun = false;
          _run();
        }
      }
    }());
  }

  /// The search context, read at most once until something it reads changes.
  Future<SavedSearchContext> _sharedContext(_Inputs inputs) => _context ??= () {
    contextReads++;
    return inputs.readContext();
  }();

  /// Which of the program's applied rules each of [candidateIds] would break
  /// in the place [position] describes (#2345), for the builder's picker
  /// under **Suggested**: [checkCandidateEventRules] with this program's
  /// rules, sharing this controller's search context. Empty while the
  /// feature is off or the program applies no rule.
  Future<CandidateRuleMarks> checkCandidates(
    SuggestionPosition position,
    List<String> candidateIds,
  ) async {
    final inputs = _inputs;
    if (inputs == null || inputs.ruleIds.isEmpty) {
      return CandidateRuleMarks.empty;
    }
    try {
      return await checkCandidateEventRules(
        repos: repos,
        ruleIds: inputs.ruleIds,
        position: position,
        candidateIds: candidateIds,
        readContext: () => _sharedContext(inputs),
        dialect: inputs.dialect,
        enrichment: inputs.enrichment,
      );
    } catch (_) {
      // diagnostics: silent — rethrown; the picker that asked logs it. A
      // context that failed to read is read again next time, not kept.
      _context = null;
      rethrow;
    }
  }

  void _notifyLater() => scheduleMicrotask(() {
    if (!_disposed) notifyListeners();
  });

  @override
  void dispose() {
    _disposed = true;
    unawaited(_rulesWatch?.cancel());
    unawaited(_tablesWatch?.cancel());
    super.dispose();
  }
}

class _Inputs {
  _Inputs(
    this.ruleIds,
    this.slots,
    this.readContext,
    this.dialect,
    this.enrichment,
  );
  final List<String> ruleIds;
  final List<ProgramSlot> slots;
  final Future<SavedSearchContext> Function() readContext;
  final Dialect? dialect;
  final SearchEnrichment? enrichment;
}

/// The slot markers [check] calls for, by slot id.
Map<String, SlotRuleMarker> eventRuleSlotMarkers(
  AppLocalizations l10n,
  EventRuleCheck check,
) {
  final primaries = <String, List<String>>{};
  final alternates = <String, List<String>>{};
  for (final status in check.broken) {
    final breach = status.breach!;
    final sentence = eventRuleTitle(l10n, status.rule, status.searchName);
    if (breach.brokenAsPlanned) {
      for (final id in breach.slotIds) {
        primaries.putIfAbsent(id, () => []).add(sentence);
      }
    }
    for (final id in breach.alternateSlotIds) {
      alternates.putIfAbsent(id, () => []).add(sentence);
    }
  }
  return {
    for (final MapEntry(:key, :value) in alternates.entries)
      key: SlotRuleMarker(ifCalled: true, rules: value),
    // A slot both counts and would be swapped in: the plain marker says it.
    for (final MapEntry(:key, :value) in primaries.entries)
      key: SlotRuleMarker(ifCalled: false, rules: value),
  };
}

/// The Rules strip on the Build tab (#2340): how many applied rules the
/// program does not meet, and how many need attention; expanded, each rule's
/// sentence and the dances that break it. It never blocks anything.
class EventRulesStrip extends StatelessWidget {
  const EventRulesStrip({
    super.key,
    required this.check,
    required this.slotTitle,
  });

  final EventRuleCheck check;

  /// What a slot is called, by slot id, or null when it is not in the
  /// program.
  final String? Function(String slotId) slotTitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final broken = check.broken.toList();
    final attention = check.needingAttention.toList();
    if (broken.isEmpty && attention.isEmpty) return const SizedBox.shrink();
    final summary = [
      if (broken.isNotEmpty) l10n.programsRulesStripBroken(broken.length),
      if (attention.isNotEmpty)
        l10n.programsRulesStripAttention(attention.length),
    ].join(' · ');
    String titles(Iterable<String> ids) =>
        [for (final id in ids) ?slotTitle(id)].join(', ');
    return Card(
      key: const ValueKey('program-rules-strip'),
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: const PageStorageKey('program-rules-strip-tile'),
        leading: Icon(eventRuleWarningIcon, color: theme.colorScheme.error),
        title: Text(summary, key: const ValueKey('program-rules-summary')),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in broken)
            _StripEntry(
              key: ValueKey('program-rule-broken-${status.rule.id}'),
              title: eventRuleTitle(l10n, status.rule, status.searchName),
              lines: [
                if (status.rule.name != null)
                  eventRuleSentence(l10n, status.rule, status.searchName),
                if (status.breach!.brokenAsPlanned) ...[
                  if (status.rule.scope == EventRuleScope.neighbouring)
                    l10n.programsRuleBreachPairs(status.breach!.count)
                  else
                    l10n.programsRuleBreachMatching(status.breach!.count),
                  if (status.breach!.slotIds.isNotEmpty)
                    l10n.programsRuleBreachDances(
                      titles(status.breach!.slotIds),
                    ),
                ],
                for (final id in status.breach!.alternateSlotIds)
                  if (slotTitle(id) case final title?)
                    l10n.programsRuleBreachIfCalled(title),
              ],
            ),
          for (final status in attention)
            _StripEntry(
              key: ValueKey('program-rule-attention-${status.rule.id}'),
              title: eventRuleTitle(l10n, status.rule, status.searchName),
              lines: [
                l10n.savedSearchNeedsAttention,
                ...eventRuleAttentionLines(l10n, status.attention!),
              ],
            ),
        ],
      ),
    );
  }
}

class _StripEntry extends StatelessWidget {
  const _StripEntry({super.key, required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          for (final line in lines)
            Text(line, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// A change to a program's applied rule ids: given the list as stored now,
/// the list to store, or `null` to store nothing ([toggleEventRuleId]).
typedef EventRuleIdsChange = List<String>? Function(List<String> applied);

/// Applies a picker's [EventRuleIdsChange] to the program's list as it is
/// stored when the write runs, and answers the list stored afterwards (or
/// `null` when there is none to show).
typedef ApplyEventRuleIdsChange =
    Future<List<String>?> Function(EventRuleIdsChange change);

/// The program's rule picker (#2340): a pinned **New rule…** line, which
/// opens the rule editor and applies the rule once it is saved, then every
/// rule with a check box. Each tick or untick is passed to [onChange] at
/// once, as a change to apply to the list as stored then
/// ([ProgramRepository.updateEventRuleIds]), so a rule another writer
/// applied while the picker was open is kept; the picker then shows the
/// list stored.
Future<void> showProgramRulesPicker(
  BuildContext context, {
  required List<String> applied,
  required ApplyEventRuleIdsChange onChange,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  sheetAnimationStyle: AppMotion.styleFor(context),
  builder: (_) => _RulesPicker(applied: applied, onChange: onChange),
);

/// Calls [onStored] with the rule ids stored for the program [programId]
/// names (none while it returns `null`) after each write to `programs`, so
/// the builder takes a list sync or another writer changed (#2340).
StreamSubscription<Set<TableUpdate>> watchStoredEventRuleIds(
  CompendiumRepositories repos, {
  required String? Function() programId,
  required void Function(List<String> ids) onStored,
}) {
  final db = repos.db;
  return db.tableUpdates(TableUpdateQuery.onAllTables([db.programs])).listen((
    _,
  ) async {
    final id = programId();
    if (id == null) return;
    final column = db.programs.eventRuleIds;
    final row =
        await (db.selectOnly(db.programs)
              ..addColumns([column])
              ..where(
                db.programs.id.equals(id) & db.programs.deletedAt.isNull(),
              ))
            .getSingleOrNull();
    if (row == null || programId() != id) return;
    onStored(decodeEventRuleIds(row.read(column)));
  });
}

class _RulesPicker extends StatefulWidget {
  const _RulesPicker({required this.applied, required this.onChange});

  final List<String> applied;
  final ApplyEventRuleIdsChange onChange;

  @override
  State<_RulesPicker> createState() => _RulesPickerState();
}

class _RulesPickerState extends State<_RulesPicker> {
  late List<String> _applied = [...widget.applied];
  List<EventRule>? _rules;
  Map<String, String> _names = const {};

  /// The ids of the rules this device holds deleted, kept for their Undo:
  /// the only applied ids that do not count toward the most, and the only
  /// ones dropped to make room. A rule not on this device yet counts.
  Set<String> _deleted = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rules == null) unawaited(_read());
  }

  Future<void> _read() async {
    final repos = RepositoriesScope.of(context);
    final rules = await repos.eventRules.listAll();
    final live = {for (final r in rules) r.id};
    final deleted = {
      for (final r in await repos.eventRules.listAll(includeDeleted: true))
        if (!live.contains(r.id)) r.id,
    };
    final names = {
      for (final stored in await repos.savedSearches.list())
        if (stored.search case final search?) search.id: search.name,
    };
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _names = names;
      _deleted = deleted;
    });
  }

  /// Whether the program already applies as many rules as it may: every
  /// applied id but a deleted rule's counts ([toggleEventRuleId]).
  bool get _full =>
      _applied.where((id) => !_deleted.contains(id)).length >=
      maxProgramEventRules;

  /// Ticks or unticks [id]: at once on screen, then on the list as stored
  /// when the write runs, and shows the list stored. A refused tick leaves
  /// the box unticked, and the picker says why.
  Future<void> _toggle(String id, {required bool on}) async {
    final deleted = _deleted;
    List<String>? change(List<String> applied) =>
        toggleEventRuleId(applied, id, on: on, deleted: deleted);
    final shown = change(_applied);
    setState(() {
      if (shown != null) _applied = shown;
    });
    if (shown == null) return;
    final stored = await widget.onChange(change);
    if (!mounted || stored == null) return;
    setState(() => _applied = stored);
  }

  Future<void> _add(String id) => _toggle(id, on: true);

  Future<void> _newRule() async {
    final rule = await showEventRuleEditor(context);
    if (rule == null || !mounted) return;
    await _read();
    await _add(rule.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rules = _rules;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        // The title, New rule… and, once the program is full, why a rule
        // cannot be ticked stay in view above the list as it scrolls.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                l10n.programsRulesPickerTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              key: const ValueKey('program-rules-new'),
              leading: const Icon(Icons.add),
              title: Text(l10n.eventRulesNewRule),
              onTap: _newRule,
            ),
            if (rules != null && _full)
              Padding(
                key: const ValueKey('program-rules-full'),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Text(l10n.programsRulesPickerFull(maxProgramEventRules)),
              ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (rules == null)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (rules.isEmpty)
                    ListTile(title: Text(l10n.programsRulesPickerEmpty))
                  else
                    for (final rule in rules)
                      CheckboxListTile(
                        key: ValueKey('program-rule-${rule.id}'),
                        value: _applied.contains(rule.id),
                        title: Text(
                          eventRuleTitle(
                            l10n,
                            rule,
                            _names[rule.savedSearchId],
                          ),
                        ),
                        subtitle: rule.name == null
                            ? null
                            : Text(
                                eventRuleSentence(
                                  l10n,
                                  rule,
                                  _names[rule.savedSearchId],
                                ),
                              ),
                        onChanged: (on) => _toggle(rule.id, on: on == true),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
