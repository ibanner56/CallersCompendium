import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../screens/settings/event_rules_screen.dart';
import '../search/event_rule_check.dart';
import '../theme/app_spacing.dart';
import 'event_rule_text.dart';
import 'program_slot_list_editor.dart' show SlotRuleMarker;

/// Checks a program's applied event rules whenever the program or the rules
/// change (#2340), for the builder's Rules strip and slot markers.
///
/// It does nothing while the feature is off: [update] with `enabled` false
/// clears the result, drops its watch on the rules and never calls the
/// evaluator or reads a rule. It never notifies during the call that changed
/// it, so a host may call [update] from `build`.
class ProgramEventRulesController extends ChangeNotifier {
  ProgramEventRulesController({
    required this.repos,
    this.evaluate = evaluateEventRules,
  });

  final CompendiumRepositories repos;
  final EventRuleEvaluator evaluate;

  EventRuleCheck _check = EventRuleCheck.empty;
  EventRuleCheck get check => _check;

  StreamSubscription<List<EventRule>>? _rulesWatch;
  int _rulesGeneration = 0;
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
    Dialect? dialect,
    SearchEnrichment? enrichment,
  }) {
    if (!enabled) {
      _inputs = null;
      _lastKey = null;
      _seq++;
      unawaited(_rulesWatch?.cancel());
      _rulesWatch = null;
      if (!identical(_check, EventRuleCheck.empty)) {
        _check = EventRuleCheck.empty;
        _notifyLater();
      }
      return;
    }
    _inputs = _Inputs(ruleIds, slots, readContext, dialect, enrichment);
    // A rule edited in the manager (or by sync) changes what it says.
    _rulesWatch ??= repos.eventRules.watchAll().skip(1).listen((_) {
      _rulesGeneration++;
      _run();
    });
    _run();
  }

  void _run() {
    final inputs = _inputs;
    if (inputs == null) return;
    final key = Object.hash(
      Object.hashAll(inputs.ruleIds),
      Object.hashAll(inputs.slots),
      _rulesGeneration,
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
    unawaited(() async {
      try {
        final result = await checkEventRules(
          repos: repos,
          ruleIds: inputs.ruleIds,
          slots: inputs.slots,
          readContext: inputs.readContext,
          dialect: inputs.dialect,
          enrichment: inputs.enrichment,
          evaluate: evaluate,
        );
        if (_disposed || seq != _seq) return;
        _check = result;
        notifyListeners();
      } catch (error, stackTrace) {
        // A rule that cannot be checked never blocks the builder.
        logCaughtError(error, stackTrace, source: 'program_event_rules.check');
      }
    }());
  }

  void _notifyLater() => scheduleMicrotask(() {
    if (!_disposed) notifyListeners();
  });

  @override
  void dispose() {
    _disposed = true;
    unawaited(_rulesWatch?.cancel());
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

/// The program's rule picker (#2340): a pinned **New rule…** line, which
/// opens the rule editor and applies the rule once it is saved, then every
/// rule with a check box. Each change is passed to [onChanged] at once, with
/// the program's applied rule ids in the order they were applied.
Future<void> showProgramRulesPicker(
  BuildContext context, {
  required List<String> applied,
  required Future<void> Function(List<String> ids) onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _RulesPicker(applied: applied, onChanged: onChanged),
);

class _RulesPicker extends StatefulWidget {
  const _RulesPicker({required this.applied, required this.onChanged});

  final List<String> applied;
  final Future<void> Function(List<String> ids) onChanged;

  @override
  State<_RulesPicker> createState() => _RulesPickerState();
}

class _RulesPickerState extends State<_RulesPicker> {
  late List<String> _applied = [...widget.applied];
  List<EventRule>? _rules;
  Map<String, String> _names = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rules == null) unawaited(_read());
  }

  Future<void> _read() async {
    final repos = RepositoriesScope.of(context);
    final rules = await repos.eventRules.listAll();
    final names = {
      for (final stored in await repos.savedSearches.list())
        if (stored.search case final search?) search.id: search.name,
    };
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _names = names;
    });
  }

  Future<void> _set(List<String> ids) async {
    setState(() => _applied = ids);
    await widget.onChanged(ids);
  }

  Future<void> _newRule() async {
    final rule = await showEventRuleEditor(context);
    if (rule == null || !mounted) return;
    await _read();
    await _set([..._applied, rule.id]);
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
        child: ListView(
          shrinkWrap: true,
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
            const Divider(height: 1),
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
                    eventRuleTitle(l10n, rule, _names[rule.savedSearchId]),
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
                  onChanged: (on) => _set(
                    on == true
                        ? [..._applied, rule.id]
                        : [
                            for (final id in _applied)
                              if (id != rule.id) id,
                          ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
