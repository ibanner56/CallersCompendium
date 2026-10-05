import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../data/sync_writer_lifecycle_scope.dart';
import '../diagnostics/error_log.dart';
import '../sync/sync_setting_labels.dart';
import '../theme/app_spacing.dart';
import 'settings/sync_notice_labels.dart' show syncRecordKindLabel;
import 'sync_conflict_details.dart';

/// How many records await a conflict choice.
Future<int> syncConflictCount(CompendiumRepositories repositories) =>
    SyncReviewQueueResolver(
      CompendiumSyncStorage(repositories),
    ).conflictCount();

/// The width at which the choice opens as a centred dialog rather than a
/// bottom sheet: below it, a phone-sized screen gets the sheet it expects.
const double kSyncConflictDialogBreakpoint = 600;

/// Opens the conflict choice: every record changed on more than one device
/// whose versions only the user can choose between (sync-spec §6.3, §6.6).
///
/// A dialog on a wide window, a bottom sheet on a narrow one. Returns once it
/// closes. Callers must not open it over Perform or an unsaved editor; the
/// surfaces that do open it — the Collection and Programs toolbars and Device
/// Sync settings — are neither.
///
/// With [reconsider], it offers choices already made again — the undo of a
/// choice — between the versions they were made between, held in memory.
/// Whenever choices are saved, a snackbar offers to undo them once the sheet
/// has closed.
Future<void> showSyncConflictSheet(
  BuildContext context, {
  List<SyncConflictReconsideration>? reconsider,
}) async {
  final repositories = RepositoriesScope.of(context);
  final lifecycle = SyncWriterLifecycleScope.maybeOf(context);
  final resolver = SyncReviewQueueResolver(CompendiumSyncStorage(repositories));
  final saved = <SyncConflictReconsideration>[];
  Widget body(BuildContext _) => SyncConflictChoice(
    resolver: resolver,
    lifecycle: lifecycle,
    reconsider: reconsider,
    onSaved: saved.addAll,
  );
  await _presentSyncConflictChoice(context, body);
  if (saved.isEmpty || !context.mounted) return;
  final l10n = AppLocalizations.of(context);
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      key: const ValueKey('sync-conflict-saved'),
      content: Text(l10n.syncConflictSaved),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        key: const ValueKey('sync-conflict-undo'),
        label: l10n.syncConflictUndo,
        onPressed: () {
          if (context.mounted) {
            showSyncConflictSheet(context, reconsider: List.of(saved));
          }
        },
      ),
    ),
  );
}

Future<void> _presentSyncConflictChoice(
  BuildContext context,
  Widget Function(BuildContext) body,
) {
  if (MediaQuery.sizeOf(context).width >= kSyncConflictDialogBreakpoint) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        key: const ValueKey('sync-conflict-dialog'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: body(context),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      key: const ValueKey('sync-conflict-bottom-sheet'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: body(context),
      ),
    ),
  );
}

/// The list of conflicts and their choices; the content of
/// [showSyncConflictSheet].
class SyncConflictChoice extends StatefulWidget {
  const SyncConflictChoice({
    super.key,
    required this.resolver,
    required this.lifecycle,
    this.reconsider,
    this.onSaved,
  });

  final SyncReviewQueueResolver resolver;

  /// Choices already made, offered again; null for the queued conflicts.
  final List<SyncConflictReconsideration>? reconsider;

  /// Told how to reconsider every batch of choices saved here.
  final void Function(List<SyncConflictReconsideration>)? onSaved;

  /// Serialises the write with sync, and reloads preferences when a setting
  /// was chosen. Null in focused tests, which then write directly.
  final SyncWriterLifecycleScope? lifecycle;

  @override
  State<SyncConflictChoice> createState() => _SyncConflictChoiceState();
}

/// What the user has picked for one record: a version (null for this
/// device's), or to combine both — with, for each entry both devices changed,
/// whether to take the other device's version.
typedef _Choice = ({
  bool picked,
  String? candidateHash,
  bool combine,
  Map<String, bool> takeOther,
});

class _SyncConflictChoiceState extends State<SyncConflictChoice> {
  List<SyncConflictGroup>? _groups;

  /// The choices still to reconsider, by record, in reconsider mode.
  late final Map<(SyncRecordKind, String), SyncConflictReconsideration>
  _remembered = {
    for (final earlier
        in widget.reconsider ?? const <SyncConflictReconsideration>[])
      (earlier.kind, earlier.recordId): earlier,
  };
  SyncConflictLookups _lookups = const SyncConflictLookups();
  final Map<(SyncRecordKind, String), _Choice> _choices = {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final groups = widget.reconsider == null
          ? await widget.resolver.listConflicts()
          : [
              for (final earlier in _remembered.values)
                syncConflictGroupFor(earlier),
            ];
      // Names for what records refer to, only when a record (not just a
      // setting) is in conflict.
      final lookups = groups.any((g) => g.kind != SyncRecordKind.setting)
          ? await SyncConflictLookups.load(widget.resolver.storage.repositories)
          : const SyncConflictLookups();
      if (!mounted) return;
      _lookups = lookups;
      setState(() {
        _groups = groups;
        _choices.removeWhere(
          (key, _) => !groups.any((g) => (g.kind, g.recordId) == key),
        );
      });
    } on Object catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'sync_conflict_sheet._load');
      if (mounted) setState(() => _groups = const []);
    }
  }

  void _choose(SyncConflictGroup group, String? candidateHash) => setState(
    () => _choices[(group.kind, group.recordId)] = (
      picked: true,
      candidateHash: candidateHash,
      combine: false,
      takeOther: const {},
    ),
  );

  void _chooseCombine(SyncConflictGroup group) => setState(
    () => _choices[(group.kind, group.recordId)] = (
      picked: true,
      candidateHash: null,
      combine: true,
      takeOther: const {},
    ),
  );

  void _pickEntry(SyncConflictGroup group, String key, bool takeOther) {
    final current = _choices[(group.kind, group.recordId)];
    if (current == null || !current.combine) return;
    setState(
      () => _choices[(group.kind, group.recordId)] = (
        picked: true,
        candidateHash: null,
        combine: true,
        takeOther: {...current.takeOther, key: takeOther},
      ),
    );
  }

  /// Whether every pick is complete: a combination needs a choice for each
  /// entry both devices changed.
  bool get _picksComplete {
    for (final group in _groups ?? const <SyncConflictGroup>[]) {
      final choice = _choices[(group.kind, group.recordId)];
      if (choice == null || !choice.picked || !choice.combine) continue;
      final diff = compareSyncCollection(
        group.recordId,
        group.localBody?['value'],
        group.candidates.single.candidate?.body['value'],
      );
      for (final pair in diff?.changed ?? const []) {
        if (!choice.takeOther.containsKey(pair.local.key)) return false;
      }
    }
    return true;
  }

  void _chooseAll({required bool thisDevice}) => setState(() {
    for (final group in _groups ?? const <SyncConflictGroup>[]) {
      if (thisDevice) {
        if (group.localBody != null) _choose(group, null);
      } else if (group.candidates.length == 1) {
        _choose(group, group.candidates.single.row.candidateHash);
      }
    }
  });

  Future<void> _apply() async {
    final picks = [
      for (final entry in _choices.entries)
        if (entry.value.picked) entry,
    ];
    if (picks.isEmpty || !_picksComplete) return;
    Set<String>? combineTaking(_Choice choice) => choice.combine
        ? {
            for (final e in choice.takeOther.entries)
              if (e.value) e.key,
          }
        : null;
    final reconsidering = widget.reconsider != null;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Future<SyncConflictResolution> write() => reconsidering
          ? widget.resolver.reconsiderConflicts([
              for (final pick in picks)
                SyncConflictRechoice(
                  reconsideration: _remembered[pick.key]!,
                  keepVersionHash: pick.value.combine
                      ? null
                      : pick.value.candidateHash,
                  combineTakingOther: combineTaking(pick.value),
                ),
            ])
          : widget.resolver.resolveConflicts([
              for (final pick in picks)
                SyncConflictDecision(
                  kind: pick.key.$1,
                  recordId: pick.key.$2,
                  keepCandidateHash: pick.value.combine
                      ? null
                      : pick.value.candidateHash,
                  combineTakingOther: combineTaking(pick.value),
                ),
            ]);
      final runWrite = widget.lifecycle?.runWrite;
      final resolution = runWrite == null
          ? await write()
          : await runWrite(write);
      widget.onSaved?.call(resolution.reconsiderations);
      if (resolution.kinds.contains(SyncRecordKind.setting)) {
        await widget.lifecycle?.onRestored?.call();
      }
      for (final pick in picks) {
        _remembered.remove(pick.key);
      }
      _choices.clear();
      await _load();
      if (mounted && (_groups?.isEmpty ?? true)) Navigator.of(context).pop();
    } on SyncReviewException catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'sync_conflict_sheet._apply');
      if (!mounted) return;
      setState(
        () => _error = switch (error.code) {
          SyncReviewFailureCode.clockOutOfRange => l10n.syncConflictClockWrong,
          SyncReviewFailureCode.combineOverLimit =>
            l10n.syncConflictCombineOverLimitError,
          SyncReviewFailureCode.combineUnavailable =>
            l10n.syncConflictCombineUnavailable,
          _ when reconsidering => l10n.syncConflictUndoChanged,
          _ => l10n.syncReviewCandidateChanged,
        },
      );
      await _load();
    } on Object catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'sync_conflict_sheet._apply');
      if (mounted) setState(() => _error = l10n.syncConflictFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final groups = _groups;
    final anyPicked =
        _choices.values.any((choice) => choice.picked) && _picksComplete;
    final everyGroupHasOneOther =
        groups != null &&
        groups.isNotEmpty &&
        groups.every((group) => group.candidates.length == 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.syncConflictTitle,
                style: theme.textTheme.titleLarge,
                semanticsLabel: l10n.syncConflictTitle,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.reconsider == null
                    ? l10n.syncConflictIntro
                    : l10n.syncConflictReconsiderIntro,
              ),
            ],
          ),
        ),
        if (groups == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              l10n.syncConflictNone,
              key: const ValueKey('sync-conflict-none'),
            ),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final group in groups)
                  _ConflictGroupTile(
                    key: ValueKey(
                      'sync-conflict-${group.kind.name}-${group.recordId}',
                    ),
                    group: group,
                    lookups: _lookups,
                    // One conflict gets the whole comparison at once; several
                    // stay compact, each with its own way in.
                    expanded: groups.length == 1,
                    choice: _choices[(group.kind, group.recordId)],
                    onChoose: _busy ? null : (hash) => _choose(group, hash),
                    onCombine: _busy ? null : () => _chooseCombine(group),
                    onPickEntry: _busy
                        ? null
                        : (key, takeOther) => _pickEntry(group, key, takeOther),
                  ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              _error!,
              key: const ValueKey('sync-conflict-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (groups != null && groups.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                TextButton(
                  key: const ValueKey('sync-conflict-all-this-device'),
                  onPressed: _busy ? null : () => _chooseAll(thisDevice: true),
                  child: Text(l10n.syncConflictKeepAllThisDevice),
                ),
                if (everyGroupHasOneOther)
                  TextButton(
                    key: const ValueKey('sync-conflict-all-other-device'),
                    onPressed: _busy
                        ? null
                        : () => _chooseAll(thisDevice: false),
                    child: Text(l10n.syncConflictKeepAllOtherDevice),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          // Wraps rather than overflows at large text sizes.
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: AppSpacing.sm,
            overflowAlignment: OverflowBarAlignment.end,
            children: [
              TextButton(
                key: const ValueKey('sync-conflict-later'),
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(l10n.syncConflictDecideLater),
              ),
              FilledButton(
                key: const ValueKey('sync-conflict-apply'),
                onPressed: _busy || !anyPicked ? null : _apply,
                child: Text(l10n.syncConflictApply),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConflictGroupTile extends StatelessWidget {
  const _ConflictGroupTile({
    super.key,
    required this.group,
    required this.lookups,
    required this.expanded,
    required this.choice,
    required this.onChoose,
    required this.onCombine,
    required this.onPickEntry,
  });

  final SyncConflictGroup group;
  final SyncConflictLookups lookups;
  final bool expanded;
  final _Choice? choice;
  final VoidCallback? onCombine;

  /// Called with an entry both devices changed, and whether to take the
  /// other device's version of it in the combination.
  final void Function(String key, bool takeOther)? onPickEntry;

  /// Called with the chosen candidate's hash, or null for this device's.
  final void Function(String? candidateHash)? onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final local = group.localBody;
    // Nothing is preselected: a choice is only ever the user's.
    final picked = choice?.picked == true ? choice : null;
    final selected = picked == null
        ? null
        : picked.combine
        ? _combineBoth
        : (picked.candidateHash ?? _thisDevice);
    // Combine both is offered for a whole-collection setting with two
    // versions to combine.
    final combinable =
        group.kind == SyncRecordKind.setting &&
        syncWholeCollectionSettingKeys.contains(group.recordId) &&
        group.candidates.length == 1 &&
        local != null;
    final otherValue = group.candidates.first.candidate?.body['value'];
    final combination = combinable
        ? combineSyncCollection(group.recordId, local['value'], otherValue)
        : null;
    final changedEntries = combinable
        ? compareSyncCollection(
                group.recordId,
                local['value'],
                otherValue,
              )?.changed ??
              const []
        : const <({SyncCollectionEntry local, SyncCollectionEntry other})>[];
    final numbered = group.candidates.length > 1;
    final summaries = {
      for (final item in group.candidates)
        ?syncConflictSummary(l10n, group, item),
    };
    // Times are shown only when they tell the versions apart: an exact tie
    // has one time on every version.
    final times = {
      ?group.localUpdatedAt?.toUtc(),
      for (final item in group.candidates) ?item.candidate?.updatedAt.toUtc(),
    };
    final showTimes = times.length > 1;
    String subtitle(String text, DateTime? when) => showTimes && when != null
        ? '$text\n${l10n.syncConflictChangedAt(syncConflictWhen(context, when))}'
        : text;
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: RadioGroup<String>(
          groupValue: selected,
          onChanged: (value) {
            if (value == null) return;
            if (value == _combineBoth) {
              onCombine?.call();
              return;
            }
            onChoose?.call(value == _thisDevice ? null : value);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  _recordTitle(l10n),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              for (final summary in summaries)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Text(summary, style: theme.textTheme.bodySmall),
                ),
              if (local != null)
                RadioListTile<String>(
                  key: ValueKey('sync-conflict-option-${group.recordId}-local'),
                  value: _thisDevice,
                  enabled: onChoose != null,
                  title: Text(l10n.syncConflictThisDevice),
                  subtitle: Text(
                    subtitle(_versionText(l10n, local), group.localUpdatedAt),
                  ),
                ),
              for (final (index, item) in group.candidates.indexed)
                RadioListTile<String>(
                  key: ValueKey(
                    'sync-conflict-option-${group.recordId}-$index',
                  ),
                  value: item.row.candidateHash,
                  enabled: onChoose != null && item.isActionable,
                  title: Text(
                    numbered
                        ? l10n.syncConflictOtherDeviceNumbered(index + 1)
                        : l10n.syncConflictOtherDevice,
                  ),
                  subtitle: Text(
                    subtitle(
                      _versionText(l10n, item.candidate?.body),
                      item.candidate?.updatedAt,
                    ),
                  ),
                ),
              if (combination != null)
                RadioListTile<String>(
                  key: ValueKey(
                    'sync-conflict-option-${group.recordId}-combine',
                  ),
                  value: _combineBoth,
                  enabled: onCombine != null && !combination.overLimit,
                  title: Text(l10n.syncConflictCombineBoth),
                  subtitle: Text(
                    combination.overLimit
                        ? l10n.syncConflictCombineOverLimit(
                            combination.count,
                            combination.limit!,
                          )
                        : l10n.syncConflictCombineSummary(combination.count),
                  ),
                ),
              if (choice?.combine == true && changedEntries.isNotEmpty)
                Padding(
                  key: ValueKey('sync-conflict-pick-each-${group.recordId}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.syncConflictCombinePickEach,
                        style: theme.textTheme.bodySmall,
                      ),
                      for (final pair in changedEntries)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_entryLabel(pair.local)),
                              SegmentedButton<bool>(
                                key: ValueKey(
                                  'sync-conflict-entry-${pair.local.key}',
                                ),
                                emptySelectionAllowed: true,
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(
                                    value: false,
                                    label: Text(l10n.syncConflictThisDevice),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: Text(l10n.syncConflictOtherDevice),
                                  ),
                                ],
                                selected: {?choice?.takeOther[pair.local.key]},
                                onSelectionChanged: onPickEntry == null
                                    ? null
                                    : (picked) {
                                        if (picked.isEmpty) return;
                                        onPickEntry!(
                                          pair.local.key,
                                          picked.first,
                                        );
                                      },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: SyncConflictComparison(
                    key: ValueKey('sync-conflict-comparison-${group.recordId}'),
                    group: group,
                    lookups: lookups,
                  ),
                )
              else
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: TextButton(
                      key: ValueKey(
                        'sync-conflict-show-differences-${group.recordId}',
                      ),
                      onPressed: () => _showDifferences(context),
                      child: Text(l10n.syncConflictShowDifferences),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The full comparison for this record: a page of its own on a phone, a
  /// dialog over the list on a wide window.
  Future<void> _showDifferences(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = _recordTitle(l10n);
    Widget body(BuildContext context) => SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SyncConflictComparison(group: group, lookups: lookups),
    );
    if (MediaQuery.sizeOf(context).width >= kSyncConflictDialogBreakpoint) {
      return showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('sync-conflict-differences-dialog'),
          title: Text(title),
          content: SizedBox(width: 520, child: body(dialogContext)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).closeButtonLabel,
              ),
            ),
          ],
        ),
      );
    }
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (pageContext) => Scaffold(
          key: const ValueKey('sync-conflict-differences-page'),
          appBar: AppBar(title: Text(title)),
          body: body(pageContext),
        ),
      ),
    );
  }

  /// The radio value for this device's version. Candidate values are wire
  /// hashes, which this can never equal.
  static const String _thisDevice = 'this-device';

  /// The radio value for combining both versions.
  static const String _combineBoth = 'combine-both';

  /// What a collection entry is known by: its name, or for a walkthrough
  /// snippet (which has none) its text.
  static String _entryLabel(SyncCollectionEntry entry) {
    final value = entry.value;
    return entry.label ?? (value is String ? value : entry.key);
  }

  String _recordTitle(AppLocalizations l10n) {
    if (group.kind == SyncRecordKind.setting) {
      return syncSettingLabel(l10n, group.recordId) ??
          syncRecordKindLabel(l10n, group.kind);
    }
    final name =
        _name(group.localBody) ?? _name(group.candidates.first.candidate?.body);
    final kind = syncRecordKindLabel(l10n, group.kind);
    return name == null ? kind : l10n.settingsSyncNoticeRecordNamed(kind, name);
  }

  String _versionText(AppLocalizations l10n, Map<String, Object?>? body) {
    if (body == null) return l10n.syncConflictValueNotSet;
    if (group.kind == SyncRecordKind.setting) {
      return syncSettingValueText(l10n, body['value']);
    }
    return _name(body) ?? syncRecordKindLabel(l10n, group.kind);
  }

  static String? _name(Map<String, Object?>? body) {
    final value =
        body?['title'] ?? body?['name'] ?? body?['label'] ?? body?['key'];
    return value is String && value.isNotEmpty ? value : null;
  }
}
