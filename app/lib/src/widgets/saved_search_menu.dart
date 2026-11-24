import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../data/user_figures_scope.dart';
import '../diagnostics/error_log.dart';
import '../theme/app_spacing.dart';
import '../utils/confirm_delete.dart';
import '../utils/undo_snack_bar.dart';

/// A saved search a host is showing: which one, the saved form of the panel
/// as it was loaded (so **Update** appears only once the panel differs from
/// it), and what it refers to that is gone.
///
/// The host, not the menu, keeps this, so **Clear all** (and loading another)
/// forgets it.
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

/// The **Saved** menu (#2325): save the search on screen under a name, load a
/// saved one, and update, rename or delete the one loaded. Shared by the
/// Collection and the collection picker, at the end of their row of search
/// tools.
///
/// The menu is flat: **Save this search…** (offered only while a query is
/// set; **Save as new…** once a loaded search has been changed), then, for a
/// loaded search, **Update "…"** (only once the panel differs from it),
/// **Rename "…"…** and **Delete "…"**, then every saved search by name. One
/// this version cannot read is listed last, under **Needs attention**, and is
/// never applied; it can be deleted, with Undo.
///
/// Loading reads one [SavedSearchContext] from the live data
/// ([readContext]) and resolves against it. A search that names something
/// gone is still shown — every part that can be — and the host shows a
/// notice naming each missing thing ([SavedSearchNotice]); it is never
/// applied silently.
///
/// Disabled while online search is on: a saved search is local only.
class SavedSearchMenu extends StatefulWidget {
  const SavedSearchMenu({
    super.key,
    required this.enabled,
    required this.hasQuery,
    required this.clock,
    required this.dialect,
    required this.enrichment,
    required this.current,
    required this.loaded,
    required this.onLoadedChanged,
    required this.apply,
    required this.readContext,
  });

  /// False while online search is on.
  final bool enabled;

  /// Whether any text, filter, phrase row or Advanced row is set: the
  /// condition for **Save this search…**.
  final bool hasQuery;

  /// Where "today" comes from, for saving a chosen date as months back.
  final SearchClock clock;

  /// The active dialect: search text is saved canonical and shown in it.
  final Dialect dialect;
  final SearchEnrichment enrichment;

  /// The host's panel state now. Read only, never kept.
  final CollectionPanelState Function() current;

  /// The saved search the host is showing, if any.
  final SavedSearchLoad? loaded;

  /// The host keeps [SavedSearchLoad]; null forgets it.
  final ValueChanged<SavedSearchLoad?> onLoadedChanged;

  /// Shows a whole panel state in the host, in place of the current search,
  /// and runs it, without touching the last-used sort.
  final void Function(CollectionPanelState state) apply;

  /// Reads the context to resolve against, once per load, with the host's
  /// live Calling history settings.
  final Future<SavedSearchContext> Function(SavedSearchTextCodec text)
  readContext;

  @override
  State<SavedSearchMenu> createState() => _SavedSearchMenuState();
}

class _SavedSearchMenuState extends State<SavedSearchMenu> {
  final _controller = MenuController();
  List<StoredSavedSearch> _stored = const [];
  bool _changed = false;

  /// The caller's calendar day now, from [SavedSearchMenu.clock].
  DateTime _today() {
    final reading = widget.clock.read();
    return calendarDayAt(reading.instantUtc, reading.offset);
  }

  SavedSearchTextCodec _text() {
    final catalog =
        context
            .getInheritedWidgetOfExactType<UserFiguresScope>()
            ?.notifier
            ?.catalog ??
        UserFigureCatalog.empty;
    return savedSearchTextCodec(
      saveDialect: widget.dialect,
      showDialect: widget.dialect,
      enrichment: widget.enrichment,
      renderer: FigureRenderer(shippedTaxonomies.anyForm, userFigures: catalog),
    );
  }

  /// The saved form of the host's panel now, or null when it is too large.
  Map<String, Object?>? _currentForm() => SavedSearchSpec.fromPanelState(
    widget.current(),
    today: _today(),
    text: _text(),
  ).value?.toJson();

  Future<void> _open() async {
    final repos = RepositoriesScope.of(context);
    final List<StoredSavedSearch> stored;
    try {
      stored = await repos.savedSearches.list();
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_menu._open');
      _showFailed();
      return;
    }
    if (!mounted) return;
    var loaded = widget.loaded;
    // Deleted elsewhere (another device, by sync): nothing is loaded now.
    if (loaded != null &&
        !stored.any((s) => s.search?.id == loaded!.search.id)) {
      widget.onLoadedChanged(null);
      loaded = null;
    }
    final now = loaded == null ? null : _currentForm();
    setState(() {
      _stored = stored;
      _changed =
          loaded != null && (now == null || !_sameJson(now, loaded.baseline));
    });
    _controller.open();
  }

  Future<void> _load(SavedSearch search) async {
    final repos = RepositoriesScope.of(context);
    final text = _text();
    try {
      final ctx = await widget.readContext(text);
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
          missing = await _describe(repos, refs, ctx);
      }
      if (!mounted) return;
      widget.apply(state);
      final baseline = _currentForm() ?? search.spec.toJson();
      widget.onLoadedChanged(
        SavedSearchLoad(search: search, baseline: baseline, missing: missing),
      );
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_menu._load');
      _showFailed();
    }
  }

  Future<void> _saveNew() async {
    final l10n = AppLocalizations.of(context);
    final repos = RepositoriesScope.of(context);
    final state = widget.current();
    final spec = SavedSearchSpec.fromPanelState(
      state,
      today: _today(),
      text: _text(),
    ).value;
    if (spec == null) {
      await _tell(l10n.savedSearchTooLargeTitle, l10n.savedSearchTooLargeBody);
      return;
    }
    final name = await _askName(
      title: l10n.savedSearchSaveDialogTitle,
      window: savedSearchWindowText(l10n, state.facets, _today()),
    );
    if (name == null || !mounted) return;
    try {
      final saved = await repos.savedSearches.create(name: name, spec: spec);
      if (!mounted) return;
      // The search just saved is the one on screen now.
      widget.onLoadedChanged(
        SavedSearchLoad(search: saved, baseline: spec.toJson()),
      );
      _snack(l10n.savedSearchSavedSnack(saved.name));
    } on SavedSearchLimitReached {
      await _tell(
        l10n.savedSearchLimitTitle,
        l10n.savedSearchLimitBody(savedSearchMaxCount),
      );
    } on ArgumentError catch (error, stackTrace) {
      // A name the store cannot keep (only invisible characters).
      logCaughtError(error, stackTrace, source: 'saved_search_menu._saveNew');
      _snack(l10n.savedSearchNameRefused);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_menu._saveNew');
      _showFailed();
    }
  }

  Future<void> _update(SavedSearchLoad loaded) async {
    final l10n = AppLocalizations.of(context);
    final repos = RepositoriesScope.of(context);
    final spec = SavedSearchSpec.fromPanelState(
      widget.current(),
      today: _today(),
      text: _text(),
    ).value;
    if (spec == null) {
      await _tell(l10n.savedSearchTooLargeTitle, l10n.savedSearchTooLargeBody);
      return;
    }
    final updated = SavedSearch(
      id: loaded.search.id,
      name: loaded.search.name,
      spec: spec,
    );
    try {
      await repos.savedSearches.save(updated);
      if (!mounted) return;
      widget.onLoadedChanged(
        loaded.copyWith(search: updated, baseline: spec.toJson()),
      );
      _snack(l10n.savedSearchUpdatedSnack(updated.name));
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_menu._update');
      _showFailed();
    }
  }

  Future<void> _rename(SavedSearchLoad loaded) async {
    final l10n = AppLocalizations.of(context);
    final repos = RepositoriesScope.of(context);
    final name = await _askName(
      title: l10n.savedSearchRenameDialogTitle,
      initial: loaded.search.name,
    );
    if (name == null || !mounted) return;
    // The stored search under a new name; the panel's edits are not saved.
    final renamed = SavedSearch(
      id: loaded.search.id,
      name: name,
      spec: loaded.search.spec,
    );
    try {
      await repos.savedSearches.save(renamed);
      if (!mounted) return;
      widget.onLoadedChanged(loaded.copyWith(search: renamed));
    } on ArgumentError catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_menu._rename');
      _snack(l10n.savedSearchNameRefused);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_menu._rename');
      _showFailed();
    }
  }

  /// Deletes [id] (a readable search named [label], or one that needs
  /// attention), with Undo. Undo writes back the stored value exactly as it
  /// was read, so even a value this version cannot read comes back unchanged.
  Future<void> _delete(String id, String label) async {
    if (!await confirmDeleteIfEnabled(context, itemLabel: label)) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final repos = RepositoriesScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    final key = '$savedSearchKeyPrefix$id';
    try {
      final before = await repos.settings.get(key);
      await repos.savedSearches.delete(id);
      if (!mounted) return;
      if (widget.loaded?.search.id == id) widget.onLoadedChanged(null);
      if (before == null) return;
      showUndoSnackBar(
        messenger,
        key: const ValueKey('saved-search-undo-snackbar'),
        actionKey: const ValueKey('saved-search-undo'),
        message: l10n.savedSearchDeletedSnack(label),
        undoLabel: l10n.commonUndo,
        undoFailedMessage: l10n.commonUndoFailed,
        accessibleNavigation: accessibleNavigation,
        onUndo: () => repos.settings.set(key, before),
      );
    } on SavedSearchInUse catch (inUse) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('saved-search-in-use'),
          title: Text(l10n.savedSearchInUseTitle(label)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.savedSearchInUseBody),
              const SizedBox(height: AppSpacing.xs),
              for (final use in inUse.uses)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: Text(use.label),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonOk),
            ),
          ],
        ),
      );
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'saved_search_menu._delete');
      _showFailed();
    }
  }

  Future<void> _showUnreadable(StoredSavedSearch entry) async {
    final l10n = AppLocalizations.of(context);
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('saved-search-unreadable'),
        title: Text(l10n.savedSearchUnreadableTitle),
        content: Text(l10n.savedSearchUnreadableBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const ValueKey('saved-search-unreadable-delete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (delete != true || !mounted) return;
    await _delete(entry.savedSearchId, l10n.savedSearchUnreadableItem);
  }

  Future<String?> _askName({
    required String title,
    String initial = '',
    String? window,
  }) => showDialog<String>(
    context: context,
    builder: (context) =>
        _SavedSearchNameDialog(title: title, initial: initial, window: window),
  );

  Future<void> _tell(String title, String body) => showDialog<void>(
    context: context,
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
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  void _showFailed() => _snack(AppLocalizations.of(context).savedSearchFailed);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loaded = widget.loaded;
    final readable = [for (final s in _stored) ?s.search];
    final unreadable = [
      for (final s in _stored)
        if (s.search == null) s,
    ];
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('saved-search-save'),
          onPressed: widget.hasQuery ? _saveNew : null,
          child: Text(
            loaded != null && _changed
                ? l10n.savedSearchSaveAsNew
                : l10n.savedSearchSaveThis,
          ),
        ),
        if (loaded != null && _changed)
          MenuItemButton(
            key: const ValueKey('saved-search-update'),
            onPressed: () => _update(loaded),
            child: Text(l10n.savedSearchUpdate(loaded.search.name)),
          ),
        if (loaded != null) ...[
          MenuItemButton(
            key: const ValueKey('saved-search-rename'),
            onPressed: () => _rename(loaded),
            child: Text(l10n.savedSearchRename(loaded.search.name)),
          ),
          MenuItemButton(
            key: const ValueKey('saved-search-delete'),
            onPressed: () => _delete(loaded.search.id, loaded.search.name),
            child: Text(l10n.savedSearchDelete(loaded.search.name)),
          ),
        ],
        const Divider(height: 1),
        if (_stored.isEmpty)
          MenuItemButton(
            key: const ValueKey('saved-search-none'),
            onPressed: null,
            child: Text(l10n.savedSearchNoneYet),
          ),
        for (final search in readable)
          MenuItemButton(
            key: ValueKey('saved-search-item-${search.id}'),
            leadingIcon: Icon(
              loaded?.search.id == search.id
                  ? Icons.check
                  : Icons.bookmark_border,
            ),
            onPressed: () => _load(search),
            child: Text(search.name),
          ),
        if (unreadable.isNotEmpty) ...[
          MenuItemButton(
            onPressed: null,
            child: Text(l10n.savedSearchNeedsAttention),
          ),
          for (final entry in unreadable)
            MenuItemButton(
              key: ValueKey('saved-search-unreadable-${entry.savedSearchId}'),
              leadingIcon: Icon(Icons.warning_amber, color: scheme.error),
              onPressed: () => _showUnreadable(entry),
              child: Text(l10n.savedSearchUnreadableItem),
            ),
        ],
      ],
      builder: (context, controller, child) => Tooltip(
        message: widget.enabled
            ? l10n.savedSearchTooltip
            : l10n.savedSearchOnlineTooltip,
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          enabled: widget.enabled,
          label: l10n.savedSearchButton,
          hint: widget.enabled ? null : l10n.savedSearchOnlineTooltip,
          onTap: widget.enabled ? _toggle : null,
          excludeSemantics: true,
          child: IconButton(
            key: const ValueKey('saved-search-menu'),
            isSelected: loaded != null,
            icon: const Icon(Icons.bookmarks_outlined),
            selectedIcon: const Icon(Icons.bookmarks),
            // Compact, as the Online search icon beside it, so the row still
            // holds Filters, By phrase and Advanced on a phone.
            visualDensity: VisualDensity.compact,
            onPressed: widget.enabled ? _toggle : null,
          ),
        ),
      ),
    );
  }

  void _toggle() {
    if (_controller.isOpen) {
      _controller.close();
    } else {
      unawaited(_open());
    }
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
Future<List<SavedSearchMissing>> _describe(
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
class SavedSearchNotice extends StatelessWidget {
  const SavedSearchNotice({
    super.key,
    required this.load,
    required this.onClose,
  });

  final SavedSearchLoad load;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
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

  void _submit() {
    if (_name.isEmpty) return;
    Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final window = widget.window;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('saved-search-name-field'),
            controller: _controller,
            autofocus: true,
            maxLength: savedSearchMaxNameLength,
            decoration: InputDecoration(labelText: l10n.savedSearchNameLabel),
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
          onPressed: _name.isEmpty ? null : _submit,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
