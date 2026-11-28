import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../data/event_rules_scope.dart';
import '../data/program_templates.dart' show kProgramTemplateSlotRuleUse;
import '../data/repositories_scope.dart';
import '../data/user_figures_scope.dart';
import '../diagnostics/error_log.dart';
import '../screens/settings/event_rules_screen.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/destructive_button_style.dart';
import '../utils/confirm_delete.dart';
import '../utils/l10n_joins.dart';
import '../utils/undo_snack_bar.dart';
import 'dirty_dialog_guard.dart';
import 'event_rule_text.dart' show eventRuleSentence, eventRuleWarningIcon;

/// A saved search a host is showing: which one, the saved form of the panel
/// as it was loaded (so **Update** appears only once the panel differs from
/// it), and what it refers to that is gone.
///
/// The host, not [SavedSearchActions], keeps this, so clearing the search
/// (and loading another) forgets it.
class SavedSearchLoad {
  const SavedSearchLoad({
    required this.search,
    required this.baseline,
    this.missing = const [],
  });

  final SavedSearch search;

  /// The saved form ([SavedSearchSpec.toJson]) of the panel as the host showed
  /// it once loaded or saved. Compared with the panel's saved form now, rather
  /// than with [search]'s stored spec, so a load that reads a merged-away id as
  /// its survivor, or shows stored text in the active dialect, does not count
  /// as a change the user made.
  final Map<String, Object?> baseline;

  /// What the search refers to that is gone, for the notice. Empty for a
  /// search that resolved whole.
  final List<SavedSearchMissing> missing;

  /// The name of each deleted custom field the search filters on, by id, for
  /// the Filters panel's chip that removes that filter
  /// (`FacetPanel.deletedCustomFieldNames`). A field no name is known for is
  /// left out.
  Map<String, String> get deletedCustomFieldNames => {
    for (final m in missing)
      if (m.reference.kind == MissingReferenceKind.customField)
        m.reference.id: ?m.name,
  };

  SavedSearchLoad copyWith({
    SavedSearch? search,
    Map<String, Object?>? baseline,
  }) => SavedSearchLoad(
    search: search ?? this.search,
    baseline: baseline ?? this.baseline,
    missing: missing,
  );
}

/// One thing a loaded saved search refers to that is gone, with what to call
/// it: the name the record had when it was deleted
/// ([CompendiumRepositories.deletedRecordNames]), or the live field's label
/// for a field that changed. [name] is null when nothing on this device
/// remembers it (never synced here, or purged).
class SavedSearchMissing {
  const SavedSearchMissing(this.reference, {this.name, this.detail});

  final MissingReference reference;
  final String? name;

  /// The removed choice, for [MissingReferenceKind.customFieldChoice].
  final String? detail;
}

/// What a host does with saved searches (#2325), with no widget of its own:
/// load one into the panel (the search field's dropdown), save the panel as a
/// new one, update, rename or delete the loaded one (the Collection's ⋮ menu),
/// and rename or delete any one (Settings ▸ Collection ▸ Saved searches).
///
/// Each call reads the repositories and shows its dialogs, messages and Undo
/// through [context], and returns what the host should now hold. The panel
/// seams ([current], [apply], [readContext]) are needed only by the calls that
/// read or fill a panel; the settings list passes none.
///
/// Loading reads one [SavedSearchContext] from the live data ([readContext])
/// and resolves against it. A search that names something gone is still
/// shown — every part that can be — and the host shows a notice naming each
/// missing thing ([SavedSearchNotice]); it is never applied silently.
class SavedSearchActions {
  SavedSearchActions(
    this.context, {
    required this.clock,
    required this.dialect,
    required this.enrichment,
    this.current,
    this.apply,
    this.readContext,
  });

  final BuildContext context;

  /// Where "today" comes from, for saving a chosen date as months back.
  final SearchClock clock;

  /// The active dialect: search text is saved canonical and shown in it.
  final Dialect dialect;
  final SearchEnrichment enrichment;

  /// The host's panel state now. Read only, never kept.
  final CollectionPanelState Function()? current;

  /// Shows a whole panel state in the host, in place of the current search,
  /// and runs it, without touching the last-used sort.
  final void Function(CollectionPanelState state)? apply;

  /// Reads the context to resolve against, once per load, with the host's
  /// live Calling history settings.
  final Future<SavedSearchContext> Function(SavedSearchTextCodec text)?
  readContext;

  CompendiumRepositories get _repos => RepositoriesScope.of(context);
  AppLocalizations get _l10n => AppLocalizations.of(context);

  /// The caller's calendar day now, from [clock].
  DateTime _today() => clock.today();

  SavedSearchTextCodec _text() {
    final catalog =
        context
            .getInheritedWidgetOfExactType<UserFiguresScope>()
            ?.notifier
            ?.catalog ??
        UserFigureCatalog.empty;
    return savedSearchTextCodec(
      saveDialect: dialect,
      showDialect: dialect,
      enrichment: enrichment,
      renderer: FigureRenderer(shippedTaxonomies.anyForm, userFigures: catalog),
    );
  }

  /// The saved form of the host's panel now, or null when it is too large.
  Map<String, Object?>? _currentForm() => SavedSearchSpec.fromPanelState(
    current!(),
    today: _today(),
    text: _text(),
  ).value?.toJson();

  /// Whether the host's panel differs from [loaded] as it was loaded or last
  /// saved: the condition for **Update**.
  bool changed(SavedSearchLoad loaded) {
    final now = _currentForm();
    return now == null || !_sameJson(now, loaded.baseline);
  }

  /// Shows [search] in the host and runs it. Returns what the host now holds,
  /// or null when it could not be read (a message says so), or when
  /// [stillWanted], asked once everything is read and just before the panel
  /// is replaced, says the host no longer wants it (a load the host started
  /// in the background, overtaken by what the user did meanwhile). [quiet]
  /// logs a failure without telling the user, for a load that only follows
  /// a write that succeeded.
  Future<SavedSearchLoad?> load(
    SavedSearch search, {
    bool Function()? stillWanted,
    bool quiet = false,
  }) async {
    final text = _text();
    final repos = _repos;
    try {
      final ctx = await readContext!(text);
      final CollectionPanelState state;
      var missing = const <SavedSearchMissing>[];
      switch (resolveSavedSearch(search.spec, ctx)) {
        case ResolvedFilter(state: final resolved):
          state = resolved;
        case UnresolvableSavedSearch(missing: final refs):
          // Everything that can be shown is; the notice names the rest.
          state = search.spec.toPanelState(
            map: (kind, id) => _alias(ctx.aliases, kind, id),
            text: text,
          );
          missing = await describeSavedSearchMissing(repos, refs, ctx);
      }
      if (!context.mounted || !(stillWanted?.call() ?? true)) return null;
      apply!(state);
      final baseline = _currentForm() ?? search.spec.toJson();
      return SavedSearchLoad(
        search: search,
        baseline: baseline,
        missing: missing,
      );
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_actions.load');
      if (!quiet) _showFailed();
      return null;
    }
  }

  /// Saves the host's panel under a name the user gives. Returns the search
  /// just saved, now the loaded one, or null when nothing was saved.
  Future<SavedSearchLoad?> saveNew() async {
    final l10n = _l10n;
    final repos = _repos;
    final state = current!();
    final spec = SavedSearchSpec.fromPanelState(
      state,
      today: _today(),
      text: _text(),
    ).value;
    if (spec == null) {
      await _tell(l10n.savedSearchTooLargeTitle, l10n.savedSearchTooLargeBody);
      return null;
    }
    final name = await _askName(
      title: l10n.savedSearchSaveDialogTitle,
      window: savedSearchWindowText(l10n, state.facets, _today()),
    );
    if (name == null || !context.mounted) return null;
    try {
      final written = await _throughAliases(spec);
      final saved = await repos.savedSearches.create(name: name, spec: written);
      _snack(l10n.savedSearchSavedSnack(saved.name));
      if (!sameSavedSearchSpec(written, spec)) {
        return await _showWritten(saved, spec);
      }
      return SavedSearchLoad(search: saved, baseline: spec.toJson());
    } on SavedSearchLimitReached {
      // diagnostics: silent — an expected refusal, told to the user in full.
      await _tell(
        l10n.savedSearchLimitTitle,
        l10n.savedSearchLimitBody(savedSearchMaxCount),
      );
    } on ArgumentError catch (error, stackTrace) {
      // A name the store cannot keep (only invisible characters).
      logCaughtError(error, stackTrace, source: 'saved_search_actions.saveNew');
      _snack(l10n.savedSearchNameRefused);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_actions.saveNew');
      _showFailed();
    }
    return null;
  }

  /// Shows [written] in the host as it was just stored, when that differs
  /// from the panel (a merged-away id written as its survivor), so the panel
  /// and the list are on the survivor too, and the next change compares with
  /// what is stored. It was stored either way: if it cannot be shown, the
  /// host still holds it, with the panel's own form ([panel]) as the
  /// baseline and the [missing] it had. Not shown if the user changed the
  /// panel while it was being read: their change stands, and Update offers
  /// to save it.
  Future<SavedSearchLoad> _showWritten(
    SavedSearch written,
    SavedSearchSpec panel, {
    List<SavedSearchMissing> missing = const [],
  }) async {
    final panelForm = panel.toJson();
    final shown = apply == null || readContext == null || !context.mounted
        ? null
        : await load(
            written,
            quiet: true,
            stillWanted: () {
              final now = _currentForm();
              return now != null && _sameJson(now, panelForm);
            },
          );
    return shown ??
        SavedSearchLoad(search: written, baseline: panelForm, missing: missing);
  }

  /// [spec] with each tag, author, source, level or custom-field id that a
  /// merge on this device moved (a user's, or sync's reconciliation, which
  /// also merges levels and custom fields) read as the id that survived it,
  /// so a panel that still shows a merged-away id (it was on screen when the
  /// merge ran) does not write that id back over the merge's rewrite of the
  /// stored search ([SavedSearchSpec.movingReferences], as the merge itself
  /// uses). The baseline stays the panel's own form, which is what the panel
  /// is compared with.
  Future<SavedSearchSpec> _throughAliases(SavedSearchSpec spec) async {
    final aliases = await _repos.syncLocal.aliasMaps();
    var out = spec;
    for (final kind in const [
      SyncRecordKind.tag,
      SyncRecordKind.choreographer,
      SyncRecordKind.publishedSource,
      SyncRecordKind.difficultyLevel,
      SyncRecordKind.customFieldDef,
    ]) {
      final losers = aliases[kind]?.keys ?? const <String>[];
      if (losers.isEmpty) continue;
      final moves = {for (final id in losers) id: _alias(aliases, kind, id)};
      out = out.movingReferences(kind, moves) ?? out;
    }
    return out;
  }

  /// The saved search [id] as it is stored now, or null (after telling the
  /// user, and calling [onGone]) when it has been deleted, here in another
  /// screen or by sync. Read before every write that keeps part of what is
  /// stored, so a rename made elsewhere is not undone by an Update here, an
  /// Update made elsewhere is not undone by a Rename, and a deleted search is
  /// never brought back by either.
  Future<SavedSearch?> _storedNow(
    String id,
    String label,
    VoidCallback? onGone,
  ) async {
    final stored = await _repos.savedSearches.get(id);
    if (stored == null && context.mounted) {
      _snack(_l10n.savedSearchGone(label));
      onGone?.call();
    }
    return stored;
  }

  /// Writes the host's panel back into [loaded], under the name it is stored
  /// under now. Returns what the host now holds, or null when nothing was
  /// written; [onGone] runs when it was deleted meanwhile, so the host can
  /// forget it.
  Future<SavedSearchLoad?> update(
    SavedSearchLoad loaded, {
    VoidCallback? onGone,
  }) async {
    final l10n = _l10n;
    final repos = _repos;
    // A panel with nothing set is not worth saving (Save refuses it), so
    // Update must not write one over the stored search either.
    if (!current!().hasQuery) return null;
    final spec = SavedSearchSpec.fromPanelState(
      current!(),
      today: _today(),
      text: _text(),
    ).value;
    if (spec == null) {
      await _tell(l10n.savedSearchTooLargeTitle, l10n.savedSearchTooLargeBody);
      return null;
    }
    try {
      final stored = await _storedNow(
        loaded.search.id,
        loaded.search.name,
        onGone,
      );
      if (stored == null) return null;
      final written = await _throughAliases(spec);
      final updated = SavedSearch(
        id: stored.id,
        name: stored.name,
        spec: written,
      );
      await repos.savedSearches.save(updated);
      _snack(l10n.savedSearchUpdatedSnack(updated.name));
      if (!sameSavedSearchSpec(written, spec)) {
        return await _showWritten(updated, spec, missing: loaded.missing);
      }
      return loaded.copyWith(search: updated, baseline: spec.toJson());
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_actions.update');
      _showFailed();
      return null;
    }
  }

  /// Renames [search], keeping what is stored for it now (never saving a
  /// panel's edits, nor putting back what it held when it was loaded).
  /// Returns it as stored under its new name, or null when it was not
  /// renamed; [onGone] runs when it was deleted meanwhile.
  Future<SavedSearch?> rename(
    SavedSearch search, {
    VoidCallback? onGone,
  }) async {
    final l10n = _l10n;
    final repos = _repos;
    try {
      final before = await _storedNow(search.id, search.name, onGone);
      if (before == null || !context.mounted) return null;
      final name = await _askName(
        title: l10n.savedSearchRenameDialogTitle,
        initial: before.name,
      );
      if (name == null || !context.mounted) return null;
      // Read again: the dialog may have been open while sync changed it.
      final stored = await _storedNow(search.id, before.name, onGone);
      if (stored == null) return null;
      final renamed = SavedSearch(id: stored.id, name: name, spec: stored.spec);
      await repos.savedSearches.save(renamed);
      return renamed;
    } on ArgumentError catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_actions.rename');
      _snack(l10n.savedSearchNameRefused);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_actions.rename');
      _showFailed();
    }
    return null;
  }

  /// Deletes the saved search [id] (named [label] to the user), with Undo.
  /// Returns whether it was deleted. Undo writes back the stored value
  /// exactly as it was read, so even a value this version cannot read comes
  /// back unchanged; [onUndone] runs after it has.
  Future<bool> delete(
    String id,
    String label, {
    VoidCallback? onUndone,
    VoidCallback? onGone,
  }) async {
    if (!await confirmDeleteIfEnabled(context, itemLabel: label)) return false;
    if (!context.mounted) return false;
    final l10n = _l10n;
    final repos = _repos;
    final messenger = ScaffoldMessenger.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    final key = '$savedSearchKeyPrefix$id';
    try {
      final before = await repos.settings.get(key);
      if (before == null) {
        // Deleted meanwhile, here in another screen or by sync.
        _snack(l10n.savedSearchGone(label));
        onGone?.call();
        return false;
      }
      await repos.savedSearches.delete(id);
      showUndoSnackBar(
        messenger,
        key: const ValueKey('saved-search-undo-snackbar'),
        actionKey: const ValueKey('saved-search-undo'),
        message: l10n.savedSearchDeletedSnack(label),
        undoLabel: l10n.commonUndo,
        undoFailedMessage: l10n.commonUndoFailed,
        accessibleNavigation: accessibleNavigation,
        onUndo: () async {
          await repos.settings.set(key, before);
          onUndone?.call();
        },
      );
      return true;
    } on SavedSearchInUse catch (inUse) {
      // diagnostics: silent — an expected refusal; the dialog names each use.
      // An event rule (#2340) is named by its sentence, or its nickname
      // (#2341) above it, and the search it uses is the one being deleted.
      final uses = <(IconData, String, String?)>[];
      var usedByRules = false;
      for (final use in inUse.uses) {
        final rule = use.kind == eventRuleUseKind && use.id != null
            ? await repos.eventRules.get(use.id!)
            : null;
        if (rule == null) {
          // Anything else (a template's slot rule, #2338) in its own words.
          // An unnamed event rule deleted since it was counted has neither a
          // name nor a sentence left to show, and no longer uses the search.
          final text = savedSearchUseText(l10n, use);
          if (text.trim().isEmpty) continue;
          uses.add((Icons.link, text, null));
        } else {
          usedByRules = true;
          final sentence = eventRuleSentence(l10n, rule, label);
          uses.add(
            rule.nickname == null
                ? (eventRuleWarningIcon, sentence, null)
                : (eventRuleWarningIcon, rule.nickname!, sentence),
          );
        }
      }
      if (!context.mounted) return false;
      // The rules are refused here whether or not Event rules is on, but
      // Settings shows Manage rules only while it is: so say where they are,
      // and open the manager from here, which works either way.
      final rulesOn = EventRulesEnabledScope.of(context);
      final navigator = Navigator.of(context);
      await showDialog<void>(
        context: context,
        animationStyle: AppMotion.styleFor(context),
        builder: (context) => AlertDialog(
          key: const ValueKey('saved-search-in-use'),
          scrollable: true,
          title: Text(l10n.savedSearchInUseTitle(label)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.savedSearchInUseBody),
              const SizedBox(height: AppSpacing.xs),
              for (final (icon, title, subtitle) in uses)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon),
                  title: Text(title),
                  subtitle: subtitle == null ? null : Text(subtitle),
                ),
              if (usedByRules && !rulesOn) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.savedSearchInUseRulesOff),
              ],
            ],
          ),
          actions: [
            if (usedByRules)
              TextButton(
                key: const ValueKey('saved-search-in-use-manage-rules'),
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(
                    navigator.push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EventRulesScreen(),
                      ),
                    ),
                  );
                },
                child: Text(l10n.eventRulesManageTitle),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonOk),
            ),
          ],
        ),
      );
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_actions.delete');
      _showFailed();
    }
    return false;
  }

  /// Explains why the saved search [id] cannot be read and offers to delete
  /// it, with Undo. Returns whether it was deleted.
  Future<bool> showUnreadable(String id, {VoidCallback? onUndone}) async {
    final l10n = _l10n;
    final delete = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.styleFor(context),
      builder: (context) => AlertDialog(
        key: const ValueKey('saved-search-unreadable'),
        title: Text(l10n.savedSearchUnreadableTitle),
        content: Text(l10n.savedSearchUnreadableBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('saved-search-unreadable-delete'),
            style: destructiveFilledButtonStyle(Theme.of(context).colorScheme),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (delete != true || !context.mounted) return false;
    return this.delete(id, l10n.savedSearchUnreadableItem, onUndone: onUndone);
  }

  Future<String?> _askName({
    required String title,
    String initial = '',
    String? window,
  }) => showDialog<String>(
    context: context,
    animationStyle: AppMotion.styleFor(context),
    builder: (context) =>
        _SavedSearchNameDialog(title: title, initial: initial, window: window),
  );

  Future<void> _tell(String title, String body) => showDialog<void>(
    context: context,
    animationStyle: AppMotion.styleFor(context),
    builder: (context) => AlertDialog(
      key: const ValueKey('saved-search-message'),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context).commonOk),
        ),
      ],
    ),
  );

  void _snack(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  void _showFailed() {
    if (!context.mounted) return;
    _snack(_l10n.savedSearchFailed);
  }
}

/// [id] read through [aliases] (losing id → surviving id), following chains;
/// a cycle leaves [id] as it is. The same reading the resolver gives a search
/// that resolves whole, for one that does not.
String _alias(
  Map<SyncRecordKind, Map<String, String>> aliases,
  SyncRecordKind kind,
  String id,
) {
  final map = aliases[kind];
  if (map == null) return id;
  final seen = <String>{id};
  var current = id;
  while (true) {
    final next = map[current];
    if (next == null) return current;
    if (!seen.add(next)) return id;
    current = next;
  }
}

/// Names each of [refs]: one read of deleted names per kind of record, and the
/// live definition for a custom field that changed.
Future<List<SavedSearchMissing>> describeSavedSearchMissing(
  CompendiumRepositories repos,
  List<MissingReference> refs,
  SavedSearchContext ctx,
) async {
  const recordKinds = {
    MissingReferenceKind.tag: SyncRecordKind.tag,
    MissingReferenceKind.author: SyncRecordKind.choreographer,
    MissingReferenceKind.source: SyncRecordKind.publishedSource,
    MissingReferenceKind.level: SyncRecordKind.difficultyLevel,
    MissingReferenceKind.venue: SyncRecordKind.venue,
    MissingReferenceKind.customField: SyncRecordKind.customFieldDef,
  };
  final deleted = <MissingReferenceKind, Map<String, String>>{};
  for (final MapEntry(key: kind, value: recordKind) in recordKinds.entries) {
    final ids = [
      for (final r in refs)
        if (r.kind == kind) r.id,
    ];
    if (ids.isNotEmpty) {
      deleted[kind] = await repos.deletedRecordNames(recordKind, ids);
    }
  }
  final defs = {for (final d in ctx.customFieldDefs) d.id: d.label};
  return [
    for (final r in refs)
      switch (r.kind) {
        MissingReferenceKind.customFieldType => SavedSearchMissing(
          r,
          name: defs[r.id],
        ),
        MissingReferenceKind.customFieldChoice => SavedSearchMissing(
          r,
          name: defs[r.id.split('=').first],
          detail: r.id.substring(r.id.indexOf('=') + 1),
        ),
        _ => SavedSearchMissing(r, name: deleted[r.kind]?[r.id]),
      },
  ];
}

/// Whether [a] and [b] are the same search, as stored.
bool sameSavedSearchSpec(SavedSearchSpec a, SavedSearchSpec b) =>
    _sameJson(a.toJson(), b.toJson());

bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || !_sameJson(e.value, b[e.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// What a saved search keeps of the calling-history window, as the save
/// dialog says it ("Not called in the last 12 months"): a chosen date is kept
/// as the whole months back it is from [today] ([monthsBackFromDate]). Null
/// when the search has no window.
String? savedSearchWindowText(
  AppLocalizations l10n,
  FacetSelections facets,
  DateTime today,
) {
  final since = facets.historySince;
  final months =
      facets.historyMonths ??
      (since == null ? null : monthsBackFromDate(since, today));
  if (months == null) return null;
  if (!facets.scopesApply) return l10n.savedSearchWindowInert(months);
  return facets.callStatuses.single
      ? l10n.savedSearchWindowCalled(months)
      : l10n.savedSearchWindowNotCalled(months);
}

/// What the notice says of one missing thing.
String savedSearchMissingText(AppLocalizations l10n, SavedSearchMissing m) {
  final name = m.name;
  return switch (m.reference.kind) {
    MissingReferenceKind.tag =>
      name == null
          ? l10n.savedSearchMissingTagUnnamed
          : l10n.savedSearchMissingTag(name),
    MissingReferenceKind.author =>
      name == null
          ? l10n.savedSearchMissingAuthorUnnamed
          : l10n.savedSearchMissingAuthor(name),
    MissingReferenceKind.source =>
      name == null
          ? l10n.savedSearchMissingSourceUnnamed
          : l10n.savedSearchMissingSource(name),
    MissingReferenceKind.level =>
      name == null
          ? l10n.savedSearchMissingLevelUnnamed
          : l10n.savedSearchMissingLevel(name),
    MissingReferenceKind.venue =>
      name == null
          ? l10n.savedSearchMissingVenueUnnamed
          : l10n.savedSearchMissingVenue(name),
    MissingReferenceKind.customField =>
      name == null
          ? l10n.savedSearchMissingFieldUnnamed
          : l10n.savedSearchMissingField(name),
    MissingReferenceKind.customFieldType => l10n.savedSearchMissingFieldType(
      name ?? m.reference.id,
    ),
    MissingReferenceKind.customFieldChoice =>
      l10n.savedSearchMissingFieldChoice(
        m.detail ?? '',
        name ?? m.reference.id,
      ),
    MissingReferenceKind.figureParam => l10n.savedSearchMissingFigureDetail,
    MissingReferenceKind.userFigure => l10n.savedSearchMissingUserFigure,
    MissingReferenceKind.invalid => l10n.savedSearchMissingInvalid,
  };
}

/// The lasting notice a host shows while a loaded saved search refers to
/// things that are gone: each one by name, and that the rest of the search is
/// shown. The user removes each criterion themselves; nothing is dropped.
///
/// A screen-reader user hears it when it appears: what is missing is the
/// reason the results may not be what they expect.
class SavedSearchNotice extends StatefulWidget {
  const SavedSearchNotice({
    super.key,
    required this.load,
    required this.onClose,
  });

  final SavedSearchLoad load;
  final VoidCallback onClose;

  @override
  State<SavedSearchNotice> createState() => _SavedSearchNoticeState();
}

class _SavedSearchNoticeState extends State<SavedSearchNotice> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  @override
  void didUpdateWidget(SavedSearchNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.load.missing, widget.load.missing)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
    }
  }

  void _announce() {
    if (!mounted || !MediaQuery.supportsAnnounceOf(context)) return;
    final l10n = AppLocalizations.of(context);
    final load = widget.load;
    final message = joinSentences(l10n, [
      l10n.savedSearchNoticeTitle(load.search.name),
      for (final m in load.missing) savedSearchMissingText(l10n, m),
    ]);
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    ).catchError((Object _) {
      // diagnostics: silent — a screen-reader announcement is best-effort;
      // the notice itself is still on screen and in the semantics tree.
    });
  }

  @override
  Widget build(BuildContext context) {
    final load = widget.load;
    final onClose = widget.onClose;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final skipsField = load.missing.any(
      (m) => m.reference.kind == MissingReferenceKind.customField,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Material(
        key: const ValueKey('saved-search-notice'),
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.xs),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            0,
            AppSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Icon(
                  Icons.warning_amber,
                  color: scheme.onErrorContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: scheme.onErrorContainer),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.savedSearchNoticeTitle(load.search.name),
                        style: textTheme.titleSmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                      for (final m in load.missing)
                        Text(savedSearchMissingText(l10n, m)),
                      Text(l10n.savedSearchNoticeRest),
                      if (skipsField) Text(l10n.savedSearchNoticeFieldSkipped),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('saved-search-notice-close'),
                tooltip: l10n.savedSearchNoticeClose,
                color: scheme.onErrorContainer,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedSearchNameDialog extends StatefulWidget {
  const _SavedSearchNameDialog({
    required this.title,
    required this.initial,
    this.window,
  });

  final String title;
  final String initial;
  final String? window;

  @override
  State<_SavedSearchNameDialog> createState() => _SavedSearchNameDialogState();
}

class _SavedSearchNameDialogState extends State<_SavedSearchNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  /// Whether [_name] is one the store keeps. The field's formatter holds it
  /// to the limit, except while an input method is composing.
  bool get _canSave =>
      _name.isNotEmpty && _name.length <= savedSearchMaxNameLength;

  void _submit() {
    if (!_canSave) return;
    Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final window = widget.window;
    // Once the name differs from what the dialog opened with, a tap outside,
    // Escape and Back do nothing, so a stray tap does not lose it (#2219).
    return DirtyDialogGuard(
      listenable: _controller,
      isDirty: () => _controller.text != widget.initial,
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('saved-search-name-field'),
              controller: _controller,
              autofocus: true,
              // Limited, and counted, in UTF-16 code units, as the store limits
              // a name: `maxLength` counts characters, so a name of emoji it
              // accepted could be refused on save.
              inputFormatters: const [
                _CodeUnitLimitFormatter(savedSearchMaxNameLength),
              ],
              decoration: InputDecoration(
                labelText: l10n.savedSearchNameLabel,
                counterText:
                    '${_controller.text.length}/$savedSearchMaxNameLength',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            ?(window == null
                ? null
                : Text(window, key: const ValueKey('saved-search-window'))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const ValueKey('saved-search-name-save'),
            onPressed: _canSave ? _submit : null,
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }
}

/// Keeps a field's text to at most [maxLength] UTF-16 code units. An edit
/// that would go past it keeps what was there and as much of what it inserted
/// as fits, never splitting a surrogate pair.
class _CodeUnitLimitFormatter extends TextInputFormatter {
  const _CodeUnitLimitFormatter(this.maxLength);

  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final next = newValue.text;
    if (next.length <= maxLength) return newValue;
    // An input method may pass the limit while it composes; cut once it has
    // committed, as Flutter's own length limiter does, so it is not broken
    // off mid-word.
    if (newValue.composing.isValid) return newValue;
    final old = oldValue.text;
    // What the edit inserted: next less the longest common prefix and suffix
    // it shares with the old text.
    var prefix = 0;
    final shorter = old.length < next.length ? old.length : next.length;
    while (prefix < shorter &&
        old.codeUnitAt(prefix) == next.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shorter - prefix &&
        old.codeUnitAt(old.length - 1 - suffix) ==
            next.codeUnitAt(next.length - 1 - suffix)) {
      suffix++;
    }
    // Matched by code unit, either can end inside a surrogate pair: keep
    // pairs whole by giving the split half back to the insertion.
    bool isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
    bool isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
    if (prefix > 0 && isHigh(next.codeUnitAt(prefix - 1))) prefix--;
    if (suffix > 0 && isLow(next.codeUnitAt(next.length - suffix))) suffix--;
    final room = maxLength - prefix - suffix;
    if (room < 0) {
      final text = truncateOnRuneBoundary(next, maxLength);
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    final inserted = truncateOnRuneBoundary(
      next.substring(prefix, next.length - suffix),
      room,
    );
    final text =
        next.substring(0, prefix) +
        inserted +
        next.substring(next.length - suffix);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: prefix + inserted.length),
    );
  }
}

/// How the in-use message names [use]: a template's slot rule (#2338) by its
/// label and its template, anything else by its own label.
String savedSearchUseText(AppLocalizations l10n, SavedSearchUse use) {
  if (use.kind == kProgramTemplateSlotRuleUse) {
    final template = use.detail;
    return l10n.savedSearchUsedBySlotRule(
      use.label,
      template == null
          ? l10n.settingsProgramTemplatesMigratedName
          : template.trim().isEmpty
          ? l10n.programTemplateUntitled
          : template,
    );
  }
  return use.label;
}
