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
import '../data/event_rules_scope.dart' show kEventRuleOrderKey;
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

  /// Changes whenever what a check reads besides the program's slots and
  /// rule ids may have changed: a rule, the data a search matches on, or
  /// the search context. A picker marking suggestions ([checkCandidates])
  /// checks them again when it changes. Each change also re-checks the
  /// program, which notifies.
  Object get readsRevision =>
      Object.hash(_rulesGeneration, _dataGeneration, _contextKey);

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

  /// Table-change batches judged so far, and those judged to need a check:
  /// a test seam, so a test can wait until a write has been looked at and
  /// then tell that it asked for no check.
  @visibleForTesting
  int tableBatchesJudged = 0;
  @visibleForTesting
  int tableBatchesRechecked = 0;

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
    if (_rulesWatch == null) {
      // Numbered as they arrive, before any await: emissions can overlap,
      // and only the first is the list as it was (no re-check), while a
      // slower read never overwrites a newer one's deleted ids.
      var emissions = 0;
      var applied = 0;
      late final StreamSubscription<List<EventRule>> watch;
      watch = repos.eventRules.watchAll().listen((live) async {
        final seq = ++emissions;
        final liveIds = {for (final r in live) r.id};
        final all = await repos.eventRules.listAll(includeDeleted: true);
        if (_disposed || !identical(_rulesWatch, watch)) return;
        if (seq > applied) {
          applied = seq;
          _deletedRuleIds = {
            for (final r in all)
              if (!liveIds.contains(r.id)) r.id,
          };
        }
        if (seq > 1) {
          _rulesGeneration++;
          _schedule();
        }
        _notifyLater();
      });
      _rulesWatch = watch;
    }
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
          // Looked at whenever `settings` is in the batch, so the baseline
          // stays current even when another table already re-checks.
          if (tables.contains(settingsName)) {
            final searchesChanged = await _savedSearchesChanged();
            changed = changed || searchesChanged;
          }
          if (_disposed) return;
          tableBatchesJudged++;
          if (!changed) return;
          tableBatchesRechecked++;
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

  /// Which of the rules [ruleIds] each of [candidateIds] would break in the
  /// place [position] describes (#2345), for the builder's picker under
  /// **Suggested**: [checkCandidateEventRules], sharing this controller's
  /// search context, dialect and enrichment. The host passes the rule ids it
  /// shows, which a picker built in the same frame may read before [update]
  /// has. Empty while the feature is off or [ruleIds] is.
  Future<CandidateRuleMarks> checkCandidates(
    SuggestionPosition position,
    List<String> candidateIds, {
    required List<String> ruleIds,
  }) async {
    final inputs = _inputs;
    if (inputs == null || ruleIds.isEmpty) {
      return CandidateRuleMarks.empty;
    }
    try {
      return await checkCandidateEventRules(
        repos: repos,
        ruleIds: ruleIds,
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
                if (status.rule.nickname != null)
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
  // With the keyboard up the sheet may take all the height above it, which
  // would reach under the status bar or a notch without this (#2341).
  useSafeArea: true,
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

/// The rule count above which the rule picker shows its search field
/// (#2341). The same threshold as the add-to-program sheet's
/// (`kAddToProgramSearchThreshold`, docs/design/add-to-program-sheet.md
/// §4.1): about eight rows fit on a phone beside the title and the pinned New
/// rule line, so a shorter list has little to search. A UI tuning value, not
/// a data rule.
const kEventRulePickerSearchThreshold = 8;

class _RulesPicker extends StatefulWidget {
  const _RulesPicker({required this.applied, required this.onChange});

  final List<String> applied;
  final ApplyEventRuleIdsChange onChange;

  @override
  State<_RulesPicker> createState() => _RulesPickerState();
}

class _RulesPickerState extends State<_RulesPicker> {
  late List<String> _applied = [...widget.applied];

  /// The live rules in the order Rule order chose (#2341), read again by
  /// [_read] whenever a rule changes.
  List<EventRule>? _rules;
  Map<String, String> _names = const {};

  /// The ids of the rules this device holds deleted, kept for their Undo:
  /// the only applied ids that do not count toward the most, and the only
  /// ones dropped to make room. A rule not on this device yet counts. Kept
  /// current from [_rulesWatch], so a rule sync restores meanwhile is never
  /// dropped as deleted.
  Set<String> _deleted = const {};

  /// The search (#2341): session-only, gone when the picker closes.
  final _search = TextEditingController();
  String _query = '';

  /// Reads the rules again whenever one changes (here, or by sync).
  StreamSubscription<List<EventRule>>? _rulesWatch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rulesWatch ??= RepositoriesScope.of(
      context,
    ).eventRules.watchAll().listen((_) => unawaited(_read()));
  }

  @override
  void dispose() {
    unawaited(_rulesWatch?.cancel());
    _search.dispose();
    super.dispose();
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
    // The order is only how the list is sorted: if it can't be read, the
    // rules are listed in My order rather than not at all.
    var order = EventRuleOrder.manual;
    var usage = const <String, int>{};
    try {
      order = EventRuleOrder.fromStored(
        await repos.settings.get(kEventRuleOrderKey),
      );
      // Most used is counted when the picker opens, never stored (#2341).
      if (order == EventRuleOrder.mostUsed) {
        usage = await repos.eventRules.usageCounts();
      }
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'program_rules_picker._read');
      order = EventRuleOrder.manual;
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _rules = orderEventRules(
        rules,
        order,
        usage: usage,
        title: (r) => eventRuleTitle(l10n, r, names[r.savedSearchId]),
      );
      _names = names;
      _deleted = deleted;
    });
  }

  /// Whether the program already applies as many rules as it may: every
  /// applied id but a deleted rule's counts ([toggleEventRuleId]).
  bool get _full =>
      _applied.where((id) => !_deleted.contains(id)).length >=
      maxProgramEventRules;

  /// The applied ids of rules this device has neither live nor deleted: added
  /// on another device and still on their way, or gone for good (a backup
  /// from before #2340's fix, a rule another build could not store).
  List<String> get _notHere {
    final rules = _rules;
    if (rules == null) return const [];
    final live = {for (final r in rules) r.id};
    return [
      for (final id in _applied)
        if (!live.contains(id) && !_deleted.contains(id)) id,
    ];
  }

  /// Ticks or unticks [id]: at once on screen, then on the list as stored
  /// when the write runs, and shows the list stored. A refused tick leaves
  /// the box unticked, and the picker says why.
  Future<void> _toggle(String id, {required bool on}) =>
      // [_deleted] is read when the change runs, inside the write.
      _apply(
        (applied) => toggleEventRuleId(applied, id, on: on, deleted: _deleted),
      );

  /// Takes [_notHere] off the program.
  Future<void> _removeNotHere() {
    final gone = _notHere.toSet();
    return _apply(
      (applied) => [
        for (final id in applied)
          if (!gone.contains(id)) id,
      ],
    );
  }

  /// Applies [change] at once on screen, then to the list as stored when the
  /// write runs, and shows the list stored. When nothing was stored (the
  /// program went to Recently deleted, or the write failed, which the
  /// builder reports), the screen goes back to what it showed before.
  Future<void> _apply(EventRuleIdsChange change) async {
    final before = _applied;
    final shown = change(_applied);
    setState(() {
      if (shown != null) _applied = shown;
    });
    if (shown == null) return;
    final stored = await widget.onChange(change);
    if (!mounted) return;
    setState(() => _applied = stored ?? before);
  }

  Future<void> _add(String id) => _toggle(id, on: true);

  /// Opens the rule editor for a new rule, its nickname [nickname] when the
  /// search found nothing (#2341), and applies the rule once it is saved. The
  /// search is cleared, so the new rule is in view.
  Future<void> _newRule({String? nickname}) async {
    final rule = await showEventRuleEditor(context, nickname: nickname);
    if (rule == null || !mounted) return;
    _search.clear();
    setState(() => _query = '');
    await _read();
    await _add(rule.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rules = _rules;
    String sentence(EventRule r) =>
        eventRuleSentence(l10n, r, _names[r.savedSearchId]);
    final showSearch =
        rules != null && rules.length > kEventRulePickerSearchThreshold;
    // The text filters only while its field is shown: if a rule deleted
    // elsewhere hides the field, nothing on screen could clear it.
    final query = showSearch ? _query.trim() : '';
    final shown = rules == null
        ? null
        : [
            for (final rule in rules)
              if (eventRuleMatchesQuery(
                query,
                nickname: rule.nickname,
                sentence: sentence(rule),
              ))
                rule,
          ];
    // With nothing found, the pinned line offers the typed text as a new
    // rule's nickname (#2341).
    final offerTyped =
        query.isNotEmpty && shown != null && shown.isEmpty && rules!.isNotEmpty;
    // Laid out as the add-to-program sheet is (add-to-program-sheet.md §4.5):
    // the sheet takes the height above the keyboard, and with the keyboard up
    // it drops its title and holds New rule… to two lines, so the pinned line,
    // the search field and the list all stay in view at any text size.
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final keyboardUp = keyboard > 0;
    final searchField = TextField(
      key: const ValueKey('program-rules-search'),
      controller: _search,
      // No autofocus: on a phone the keyboard would cover the list
      // (add-to-program-sheet.md §4.1).
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: l10n.programsRulesPickerSearchHint,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                key: const ValueKey('program-rules-search-clear'),
                icon: const Icon(Icons.clear),
                tooltip: l10n.programsRulesPickerSearchClear,
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
      ),
      onChanged: (value) => setState(() => _query = value),
    );
    final newLabel = offerTyped
        ? l10n.programsRulesPickerNewNamed(query)
        : l10n.eventRulesNewRule;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: keyboardUp ? double.infinity : media.size.height * 0.8,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The title, New rule…, once the program is full why a rule
                // cannot be ticked, and any applied rules not on this device:
                // pinned above the search and the list,
                // capped so a large text size cannot push them out of the
                // sheet (the cap is a backstop once the title is dropped).
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.45,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!keyboardUp)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: Text(
                              l10n.programsRulesPickerTitle,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ListTile(
                          key: const ValueKey('program-rules-new'),
                          leading: const Icon(Icons.add),
                          title: Semantics(
                            label: keyboardUp ? newLabel : null,
                            excludeSemantics: keyboardUp,
                            child: Text(
                              newLabel,
                              maxLines: keyboardUp ? 2 : null,
                              overflow: keyboardUp
                                  ? TextOverflow.ellipsis
                                  : null,
                            ),
                          ),
                          onTap: () =>
                              _newRule(nickname: offerTyped ? query : null),
                        ),
                        if (rules != null && _full)
                          Padding(
                            key: const ValueKey('program-rules-full'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs,
                            ),
                            child: Text(
                              l10n.programsRulesPickerFull(
                                maxProgramEventRules,
                              ),
                            ),
                          ),
                        if (_notHere case final notHere when notHere.isNotEmpty)
                          ListTile(
                            key: const ValueKey('program-rules-not-here'),
                            leading: const Icon(Icons.cloud_off_outlined),
                            title: Text(
                              l10n.programsRulesPickerNotHere(notHere.length),
                            ),
                            subtitle: Text(l10n.programsRulesPickerNotHereHelp),
                            trailing: TextButton(
                              key: const ValueKey(
                                'program-rules-remove-not-here',
                              ),
                              onPressed: _removeNotHere,
                              child: Text(l10n.commonRemove),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xxs,
                      AppSpacing.md,
                      AppSpacing.xs,
                    ),
                    child: searchField,
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
                      else if (shown!.isEmpty)
                        ListTile(
                          key: const ValueKey('program-rules-no-matches'),
                          title: Text(l10n.programsRulesPickerNoMatches(query)),
                        )
                      else
                        for (final rule in shown)
                          CheckboxListTile(
                            key: ValueKey('program-rule-${rule.id}'),
                            value: _applied.contains(rule.id),
                            // The nickname (#2341) is the title, with the
                            // sentence beneath it; a rule without one shows
                            // its sentence alone.
                            title: Text(
                              eventRuleTitle(
                                l10n,
                                rule,
                                _names[rule.savedSearchId],
                              ),
                            ),
                            subtitle: rule.nickname == null
                                ? null
                                : Text(sentence(rule)),
                            onChanged: (on) => _toggle(rule.id, on: on == true),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
