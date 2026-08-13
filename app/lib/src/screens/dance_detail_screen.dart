import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/collection_filter_scope.dart';
import '../data/dialect_library_scope.dart';
import '../data/display_defaults.dart';
import '../data/collection_refresh_scope.dart';
import '../data/formation_colors_scope.dart';
import '../data/refresh_coalescer.dart';
import '../data/repositories_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../data/track_history_for_all_callers_scope.dart';
import '../diagnostics/error_log.dart';
import '../export/dance_pdf.dart';
import '../export/export_labels_l10n.dart';
import '../search/dance_detail_data.dart';
import '../search/facet_labels.dart';
import '../theme/app_spacing.dart';
import '../utils/confirm_delete.dart';
import '../utils/launch_external_url.dart';
import '../utils/undo_snack_bar.dart';
import '../utils/safe_name.dart';
import '../widgets/add_to_program_sheet.dart';
import '../widgets/dance_export_menu.dart';
import '../widgets/dialect_quick_switch.dart';
import '../widgets/colour_dance_theme.dart';
import '../widgets/figure_table.dart';
import '../widgets/formation_color_badge.dart';
import '../widgets/skeleton.dart';
import '../widgets/tag_chip.dart';
import 'dance_detail/calling_history_section.dart';
import 'dance_editor_screen.dart';
import 'perform_dance_screen.dart';
import 'program_summary_screen.dart';

/// Dance detail / card (`docs/design/ux.md` §2): header (title, authors,
/// formation, hook, tags, status banner, provenance line), a figure table
/// grouped by derived section with a canonical ⇄ dialect toggle, and the
/// calling notes / links / custom-field sections. The Edit action opens the
/// [DanceEditorScreen] (roadmap 3.3).
///
/// [onRestored] is called (if provided) when the user taps the Undo action
/// on the delete snackbar — allowing the caller (e.g. the Collection screen)
/// to reload its list so the restored dance reappears immediately.
///
/// [onDeleted] is called (if provided) instead of [Navigator.pop] when a
/// delete is confirmed — used by [CollectionShell] when this screen is
/// embedded in the split-pane detail pane rather than pushed as a route.
///
/// [onNavigateTo] is called (if provided) instead of [Navigator.pushReplacement]
/// when the user duplicates a dance — used by [CollectionShell] to update the
/// selected dance id in the detail pane without a route push.
class DanceDetailScreen extends StatefulWidget {
  const DanceDetailScreen({
    super.key,
    required this.danceId,
    this.onRestored,
    this.onDeleted,
    this.onNavigateTo,
  }) : previewData = null,
       onImport = null;

  /// Preview mode for a **non-persisted** dance (e.g. an online Caller's Box
  /// search result before it is imported). Renders [data] directly with the
  /// same body as a saved dance, but hides the collection-only actions (dialect
  /// switch, Perform, Export, Duplicate, Add-to-program, Delete) and the calling
  /// history, and swaps the Edit FAB for an **Import** FAB wired to [onImport].
  const DanceDetailScreen.preview({
    super.key,
    required DanceDetailData data,
    required this.onImport,
  }) : danceId = null,
       previewData = data,
       onRestored = null,
       onDeleted = null,
       onNavigateTo = null;

  /// Id of the persisted dance to load, or `null` in preview mode (see
  /// [DanceDetailScreen.preview]).
  final String? danceId;

  /// In-memory detail data to render instead of loading from the database.
  /// Non-null only in preview mode.
  final DanceDetailData? previewData;

  /// Called when the preview-mode Import FAB is tapped. Non-null only in
  /// preview mode; the caller performs the direct import (and its snackbar /
  /// collection refresh).
  final Future<void> Function()? onImport;

  /// Optional callback invoked after a soft-delete is undone (restored).
  /// The Collection screen passes `() => _boot()` here so the list reloads.
  final VoidCallback? onRestored;

  /// Optional callback invoked after a soft-delete is confirmed. When set
  /// (split-pane embedded mode), the parent handles navigation; when null
  /// (routed mode), [Navigator.pop] with `true` is used instead.
  final VoidCallback? onDeleted;

  /// Optional callback invoked with a [danceId] when navigation to a different
  /// dance is needed (e.g. after duplication). When set (split-pane mode), the
  /// parent updates the selected id; when null (routed mode), the screen uses
  /// [Navigator.pushReplacement] instead.
  final void Function(String danceId)? onNavigateTo;

  /// App-bar action layout breakpoint (logical pixels). Below this width the
  /// screen collapses its secondary actions (dialect switch, Export, Duplicate,
  /// Delete) into a single overflow menu so the bar never overflows on a phone;
  /// at or above it the full action row is shown. 600 mirrors Material 3's
  /// compact window-size-class cutoff, so phones get the decluttered layout
  /// while tablets/desktop keep the one-tap row.
  static const double compactActionsBreakpoint = 600;

  @override
  State<DanceDetailScreen> createState() => _DanceDetailScreenState();
}

class _DanceDetailScreenState extends State<DanceDetailScreen> {
  late CompendiumRepositories _repos;
  Future<DanceDetailData?>? _future;

  /// Whether this screen is rendering a non-persisted preview dance (online
  /// Caller's Box result) rather than a saved one. Guards all collection-only
  /// behavior (loading, reload-on-setting-change, app-bar actions, delete/etc).
  bool get _isPreview => widget.previewData != null;

  /// The last-seen value of the "require mark-performed for calling history"
  /// setting (ROADMAP G.2). Tracked so [didChangeDependencies] can reload the
  /// calling history when the setting is toggled while this screen is open.
  bool _requirePerformedForHistory = false;

  /// The last-seen value of the "track calling history for all callers" setting
  /// (issue #583). Tracked so [didChangeDependencies] can reload the calling
  /// history when the setting is toggled while this screen is open.
  bool _trackHistoryForAllCallers = false;

  /// When `false` the figure table renders in the user's active dialect;
  /// when `true` it renders canonical role/move tokens.  The toggle is hidden
  /// when the active dialect is already [Dialect.canonical] (toggling would
  /// be a no-op).
  ///
  /// Seeded from the saved default dance-detail rendering (ROADMAP G.6b) on
  /// first load; the in-view toggle overrides it for this session.
  bool _canonicalView = false;

  /// Whether the user has flipped the in-view canonical⇄dialect toggle this
  /// session. Guards the saved-default seed against clobbering a user change
  /// (mirrors the settings-screen load-vs-toggle race guard).
  bool _canonicalUserSet = false;

  static final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

  /// The app-level dance-data refresh notifier (issue #768), if provided. A
  /// batch edit in the Collection list can change the dance this screen is
  /// showing while the wide layout's detail pane is showing it — the pane is
  /// keyed on the *selection*, so it never rebuilds for an edit.
  ///
  /// The only program-derived thing this screen renders is the **Calling
  /// history** section, which watches the database itself
  /// ([CallingHistorySection]); a program-side listener here as well would
  /// reload the whole screen on top of that section's own emit — one write,
  /// two rebuilds, issue #340's failure. `ProgramsRefreshScope` has since been
  /// retired outright for want of any subscriber.
  ///
  /// **This is the last remaining refresh-scope subscription in the app.** The
  /// dance fields above still come from a one-shot [_load], so this channel is
  /// the only thing that makes an edit made elsewhere appear here; it retires
  /// when this screen's own data moves to a stream, and not before.
  ValueListenable<int>? _collectionRefresh;

  /// Collapses several collection bumps arriving in the same synchronous block
  /// into one reload, so this screen — which composes the most queries of any —
  /// does not load twice per mutation (issue #340).
  late final RefreshCoalescer _refreshCoalescer = RefreshCoalescer(() {
    if (mounted) _reload();
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Preview mode renders in-memory data directly and reads no scopes (repos,
    // calling-history setting) — none of the collection-only paths apply.
    if (_isPreview) {
      _future ??= Future.value(widget.previewData);
      return;
    }
    // Subscribe to the app-level dance-data refresh notifier. Registers a
    // rebuild dependency; the notifier is stable across the app's lifetime, so
    // this attaches once.
    final collectionRefresh = CollectionRefreshScope.maybeOf(context);
    if (!identical(collectionRefresh, _collectionRefresh)) {
      _collectionRefresh?.removeListener(_onExternalRefresh);
      _collectionRefresh = collectionRefresh;
      _collectionRefresh?.addListener(_onExternalRefresh);
    }
    // The two calling-history settings are passed straight down to
    // [CallingHistorySection], which rebuilds its query when either changes.
    // didChangeDependencies is always followed by a build, so keeping the
    // fields current is all that is needed — toggling a setting no longer
    // reloads this whole screen to re-run one query (issue #768).
    _requirePerformedForHistory = RequirePerformedForHistoryScope.of(context);
    _trackHistoryForAllCallers = TrackHistoryForAllCallersScope.of(context);
    if (_future == null) {
      _repos = RepositoriesScope.of(context);
      _future = _load();
    }
  }

  Future<DanceDetailData?> _load() async {
    // Seed the initial rendering from the saved default (ROADMAP G.6b) before
    // the body first renders; skip if the user already flipped the toggle (the
    // body only shows after this future resolves, so this is a belt-and-braces
    // guard mirroring the settings-screen load-vs-toggle race). A settings
    // read/decode failure must not fail the whole detail load — fall back
    // silently to the historical active-dialect rendering.
    if (!_canonicalUserSet) {
      try {
        final storedRendering = await _repos.settings.get(
          kDefaultDanceDetailRenderingKey,
        );
        if (!_canonicalUserSet) {
          _canonicalView =
              danceDetailRenderingFromStored(storedRendering) ==
              DanceDetailRendering.canonical;
        }
      } catch (_) {
        // diagnostics: silent — rendering preference read failed; keeps historical default (active dialect).
      }
    }

    return DanceDetailData.load(_repos, widget.danceId!);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// Reloads after a refresh broadcast. Ignored before the first load has been
  /// scheduled: [_future] is `null` only until [didChangeDependencies] runs, and
  /// reloading ahead of it would read `_repos` before it is assigned.
  void _onExternalRefresh() {
    if (mounted && _future != null) _refreshCoalescer.request();
  }

  @override
  void dispose() {
    _collectionRefresh?.removeListener(_onExternalRefresh);
    super.dispose();
  }

  /// Human-readable difficulty label for the export card, combining the
  /// ordered [Dance.level] with the [Dance.mixedLevel] flag. Returns `null`
  /// when neither is set so the export omits the Level line.
  static String? _levelLabel(AppLocalizations l10n, Dance dance) {
    final base = dance.level == null
        ? null
        : danceLevelLabel(l10n, dance.level!);
    if (base != null) {
      return dance.mixedLevel ? l10n.exportLevelWithMixed(base) : base;
    }
    return dance.mixedLevel ? l10n.exportLevelMixedOnly : null;
  }

  /// Opens the full-screen large-print [PerformDanceScreen] for this dance,
  /// passing the shared [FigureRenderer] and the already-resolved author names.
  Future<void> _perform(DanceDetailData detail) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PerformDanceScreen(
          dance: detail.dance,
          renderer: _renderer,
          authorNames: detail.authorNames,
        ),
      ),
    );
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DanceEditorScreen(danceId: widget.danceId!),
      ),
    );
    // The editor bumps CollectionRefreshScope on save, which reloads this
    // screen through its subscription; reloading here as well would load twice
    // for one edit (issue #340). Only reload directly when no scope is mounted
    // (focused widget tests).
    if (mounted && _collectionRefresh == null) _reload();
  }

  /// Opens another dance's detail — from an auto cross-reference link in the
  /// hook / calling notes, or from a `relatedDance` link row. Both route here
  /// so the two kinds of dance-to-dance link behave identically *and* so the
  /// await/reload contract exists in one place rather than two copies that can
  /// drift (issue #768).
  ///
  /// Awaited because the pushed screen can edit, duplicate or delete the dance
  /// it shows, and this screen renders that dance's title in its cross-
  /// reference and related-link rows.
  ///
  /// An **edit** arrives through this screen's subscription, because the editor
  /// broadcasts on save. A **delete** does not: [_delete] soft-deletes and pops
  /// `true` without broadcasting, relying on the list screen's pop-result
  /// reload — which does nothing for a sibling detail screen sitting under the
  /// pushed route. So the popped result is consumed here and drives the reload
  /// for exactly that case, leaving the edit path to the broadcast rather than
  /// reloading for both (issue #340). The unscoped branch keeps focused widget
  /// tests, which mount no scope, behaving as they did.
  Future<void> _openDance(String danceId) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DanceDetailScreen(danceId: danceId),
      ),
    );
    if (!mounted) return;
    if (deleted == true || _collectionRefresh == null) _reload();
  }

  /// Duplicates the dance, appends " (copy)" to the copy's title (since
  /// [Dance.duplicate] preserves the original title verbatim), then navigates
  /// to the new copy's detail screen. In routed mode, uses
  /// [Navigator.pushReplacement]; in embedded split-pane mode, calls
  /// [widget.onNavigateTo] so the parent shell updates the selected id.
  Future<void> _duplicate() async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now().toUtc();
    final copy = await _repos.dances.duplicate(
      id: widget.danceId!,
      newId: uuidV4(),
      now: now,
    );
    // Append the localized " (copy)" suffix so the duplicate is visually
    // distinct in the list. This wording is persisted into the copy's title.
    await _repos.dances.update(
      copy.copyWith(
        title: l10n.commonDuplicateTitleSuffix(copy.title),
        updatedAt: now,
      ),
    );
    if (!mounted) return;
    if (widget.onNavigateTo != null) {
      // Embedded (split-pane) mode: let the shell display the new dance.
      widget.onNavigateTo!(copy.id);
    } else {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DanceDetailScreen(danceId: copy.id),
        ),
      );
    }
  }

  /// Soft-deletes the dance immediately and shows an "Undo" snackbar that
  /// calls [DanceRepository.restore] if tapped. In routed mode (no [onDeleted]
  /// callback), pops back to the list with `true` so the caller can reload.
  /// In embedded split-pane mode ([onDeleted] is set), calls that callback
  /// instead of popping (the screen is not on the Navigator stack).
  /// [widget.onRestored] is called on undo so the Collection can re-display
  /// the dance without requiring user-initiated navigation.
  ///
  /// Note: the snackbar is shown BEFORE [onDeleted] or pop so the current
  /// Scaffold is still registered with its [ScaffoldMessenger] when the
  /// snackbar is enqueued. In split-pane mode, this ensures the snackbar
  /// appears in the detail pane rather than being lost on unmount.
  Future<void> _delete() async {
    final resolvedTitle = (await _future)?.dance.title;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final title = resolvedTitle ?? l10n.danceScreenTitle;
    // ROADMAP G.7: optional confirm dialog before the (still-undoable) delete.
    if (!await confirmDeleteIfEnabled(context, itemLabel: title)) return;
    if (!mounted) return;
    final now = DateTime.now().toUtc();
    await _repos.dances.softDelete(widget.danceId!, at: now);
    if (!mounted) return;
    // Capture ScaffoldMessengerState before any navigation/callback so we
    // don't read a deactivating context after the widget is removed.
    final messenger = ScaffoldMessenger.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    // Show the snackbar first so the Scaffold is still in the tree when the
    // messenger enqueues it — then notify the parent (which may unmount this
    // widget) or pop the route.
    showUndoSnackBar(
      messenger,
      key: const ValueKey('deleted-snackbar'),
      message: l10n.commonDeletedSnack(title),
      undoLabel: l10n.commonUndo,
      accessibleNavigation: accessibleNavigation,
      onUndo: () async {
        await _repos.dances.restore(
          widget.danceId!,
          at: DateTime.now().toUtc(),
        );
        // Broadcast rather than relying on [onRestored]. By the time undo runs
        // this screen has usually been popped or unmounted — that is what an
        // undo snackbar is for — and five of the routes that push it pass no
        // [onRestored] at all, so the callback reaches nothing. The notifier is
        // resolved in `didChangeDependencies`, long before any of that, so the
        // broadcast does not depend on this widget still being alive; that
        // ordering is the whole defect.
        final revision = _collectionRefresh;
        if (revision is ValueNotifier<int>) revision.value++;
        widget.onRestored?.call();
      },
    );
    if (widget.onDeleted != null) {
      // Embedded (split-pane) mode: notify the parent; no route to pop.
      widget.onDeleted!.call();
    } else {
      // Routed mode: pop with true so the list screen can reload.
      Navigator.of(context).pop(true);
    }
  }

  /// Opens the shared "Add to program" sheet (`showAddToProgramSheet`) so this
  /// dance can be appended to an existing program or seed a new one. The flow
  /// (and its snackbars) is shared with the Collection list's row action menu.
  ///
  /// Nothing is reloaded when the sheet closes, and that is now correct rather
  /// than the gap-1 bug it once was (issue #768: this was expression-bodied and
  /// returned the sheet's future without awaiting or reloading, so the
  /// **Calling history** section kept the pre-add data). The section watches
  /// `program_slots` itself, so the sheet's write reaches it directly — with no
  /// broadcast to remember, and no dependence on a scope being mounted.
  Future<void> _addToProgram(String danceTitle) => showAddToProgramSheet(
    context,
    repositories: _repos,
    danceId: widget.danceId!,
    danceTitle: danceTitle,
  );

  // --- App-bar actions -------------------------------------------------------
  // The dance-detail bar carries seven affordances (dialect switch, Perform,
  // Export, Duplicate, Add-to-program, Delete, plus the Edit FAB). On a phone
  // that full row clips, so below [DanceDetailScreen.compactActionsBreakpoint]
  // we keep the primary one-tap actions (Perform, Add-to-program; Edit stays
  // the FAB) and fold the secondary actions into a single overflow menu. Every
  // action keeps its key, tooltip/label and behaviour in both layouts.

  Widget _performButton(DanceDetailData detail) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: const ValueKey('perform-dance'),
      tooltip: l10n.dancePerformTooltip,
      icon: const Icon(Icons.slideshow),
      onPressed: () => _perform(detail),
    );
  }

  Widget _addToProgramButton(DanceDetailData detail) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: const ValueKey('add-dance-to-program'),
      tooltip: l10n.commonAddToProgram,
      icon: const Icon(Icons.playlist_add),
      onPressed: () => _addToProgram(detail.dance.title),
    );
  }

  DanceExportMenu _exportMenu(BuildContext context, DanceDetailData detail) {
    final l10n = AppLocalizations.of(context);
    return DanceExportMenu(
      dance: detail.dance,
      dialect: ActiveDialectScope.of(context),
      authorNames: detail.authorNames,
      formationLabel: formationLabel(l10n, detail.dance.formation),
      levelLabel: _levelLabel(l10n, detail.dance),
      statusLabel: danceStatusLabel(l10n, detail.dance.status),
      renderer: _renderer,
    );
  }

  /// Wide layout: the full one-tap action row.
  Widget _fullActions(BuildContext context, DanceDetailData detail) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DialectQuickSwitch(),
        _performButton(detail),
        _exportMenu(context, detail),
        IconButton(
          key: const ValueKey('duplicate-dance'),
          tooltip: l10n.danceDuplicateTooltip,
          icon: const Icon(Icons.copy_all_outlined),
          onPressed: _duplicate,
        ),
        _addToProgramButton(detail),
        IconButton(
          key: const ValueKey('delete-dance'),
          tooltip: l10n.danceDeleteTooltip,
          icon: const Icon(Icons.delete_outline),
          onPressed: _delete,
        ),
      ],
    );
  }

  /// Narrow layout: primary actions stay as icon buttons; the rest collapse
  /// into the overflow menu.
  Widget _compactActions(BuildContext context, DanceDetailData detail) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _performButton(detail),
      _addToProgramButton(detail),
      _overflowMenu(context, detail),
    ],
  );

  /// Single "⋮" menu holding the secondary actions on narrow widths. Every
  /// entry is a first-class [PopupMenuItem] so it stays keyboard- and
  /// screen-reader-activatable: the dialect choices are [CheckedPopupMenuItem]s
  /// (mirroring [DialectQuickSwitch]), the three Export actions are flattened in
  /// from [DanceExportMenu], and Duplicate / Delete call the same handlers as
  /// the wide layout. Nothing is a nested popup, so activating any row performs
  /// its action rather than dismissing the menu.
  Widget _overflowMenu(BuildContext context, DanceDetailData detail) {
    final l10n = AppLocalizations.of(context);
    final controller = DialectLibraryScope.maybeOf(context);
    final activeDialectName = controller == null
        ? null
        : (controller.activeName ?? controller.active.name);
    final dialect = ActiveDialectScope.of(context);
    String exportText() => danceToPlainText(
      detail.dance,
      dialect: dialect,
      authorNames: detail.authorNames,
      formationLabel: formationLabel(l10n, detail.dance.formation),
      levelLabel: _levelLabel(l10n, detail.dance),
      statusLabel: danceStatusLabel(l10n, detail.dance.status),
      renderer: _renderer,
      labels: danceExportLabels(l10n),
    );

    return PopupMenuButton<void>(
      key: const ValueKey('dance-actions-overflow'),
      tooltip: l10n.danceMoreActions,
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        if (controller != null) ...[
          for (final entry in controller.all)
            CheckedPopupMenuItem<void>(
              key: ValueKey('dialect-quick-switch-${entry.name}'),
              checked: entry.name == activeDialectName,
              onTap: () => controller.setActive(entry.name),
              child: Text(entry.name),
            ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem<void>(
          key: const ValueKey('overflow-share-dance'),
          onTap: () => _shareDance(exportText(), detail.dance.title),
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(l10n.exportShareDanceText),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<void>(
          key: const ValueKey('overflow-copy-dance'),
          onTap: () => _copyDance(exportText()),
          child: ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(l10n.exportCopyDance),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<void>(
          key: const ValueKey('overflow-export-pdf'),
          onTap: () => _exportDancePdf(dialect, detail),
          child: ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(l10n.exportPrintPdf),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          key: const ValueKey('duplicate-dance'),
          onTap: _duplicate,
          child: ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: Text(l10n.danceDuplicateTooltip),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<void>(
          key: const ValueKey('delete-dance'),
          onTap: _delete,
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.danceDeleteTooltip),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  // Compact-layout Export handlers. On wide layouts the Export control is the
  // reusable [DanceExportMenu]; on narrow widths its three actions are flattened
  // into the overflow menu (above) so each stays an individually activatable
  // item instead of a nested popup. The shareable card and PDF are built from
  // the same public `danceToPlainText` / `buildDancePdf` helpers the widget
  // uses, so only the thin share / clipboard / print wiring lives here.
  Future<void> _shareDance(String text, String subject) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    } on Exception catch (e, stackTrace) {
      logCaughtError(e, stackTrace, source: 'dance_detail_screen._shareDance');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.exportShareDanceError)),
      );
    }
  }

  Future<void> _copyDance(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(l10n.exportDanceCopied)));
  }

  Future<void> _exportDancePdf(Dialect dialect, DanceDetailData detail) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await Printing.layoutPdf(
        name: sanitizeExportName(detail.dance.title, fallback: 'dance'),
        onLayout: (format) => buildDancePdf(
          detail.dance,
          dialect: dialect,
          authorNames: detail.authorNames,
          formationLabel: formationLabel(l10n, detail.dance.formation),
          levelLabel: _levelLabel(l10n, detail.dance),
          statusLabel: danceStatusLabel(l10n, detail.dance.status),
          renderer: _renderer,
          labels: danceExportLabels(l10n),
        ),
      );
    } on Exception catch (e, stackTrace) {
      logCaughtError(
        e,
        stackTrace,
        source: 'dance_detail_screen._exportDancePdf',
      );
      messenger.showSnackBar(SnackBar(content: Text(l10n.exportDanceError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Wrap the whole screen (AppBar + body + FAB) so the colour tint covers the
    // dance's entire view, consistent with the Perform screens. The title comes
    // from the same cached [_future]; until it resolves the tint is a no-op.
    return FutureBuilder<DanceDetailData?>(
      future: _future,
      builder: (context, titleSnapshot) {
        return ColourDanceTheme(
          title: titleSnapshot.data?.dance.title,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth <
                  DanceDetailScreen.compactActionsBreakpoint;
              return Scaffold(
                appBar: AppBar(
                  title: Text(l10n.danceScreenTitle),
                  actions: [
                    if (!_isPreview)
                      FutureBuilder<DanceDetailData?>(
                        future: _future,
                        builder: (context, snapshot) {
                          if (snapshot.data == null) {
                            return const SizedBox.shrink();
                          }
                          final detail = snapshot.data!;
                          return compact
                              ? _compactActions(context, detail)
                              : _fullActions(context, detail);
                        },
                      ),
                  ],
                ),
                body: FutureBuilder<DanceDetailData?>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const SkeletonDetailView();
                    }
                    final detail = snapshot.data;
                    if (detail == null) {
                      return Center(child: Text(l10n.danceNotFound));
                    }
                    return _buildBody(detail);
                  },
                ),
                // Edit mirrors the program preview's builder affordance: a bottom-right
                // extended FAB (`docs/design/ux.md` §2/§3) rather than an AppBar action,
                // so opening the editor is consistent across the dance and program views.
                // In preview mode the same slot becomes an Import button.
                floatingActionButton: FutureBuilder<DanceDetailData?>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.data == null) return const SizedBox.shrink();
                    if (_isPreview) {
                      return FloatingActionButton.extended(
                        key: const ValueKey('import-dance'),
                        heroTag: 'import-dance',
                        onPressed: widget.onImport == null
                            ? null
                            : () => widget.onImport!(),
                        icon: const Icon(Icons.library_add_outlined),
                        label: Text(l10n.importAction),
                      );
                    }
                    return FloatingActionButton.extended(
                      key: const ValueKey('edit-dance'),
                      heroTag: 'edit-dance',
                      onPressed: _openEditor,
                      icon: const Icon(Icons.edit_note),
                      label: Text(l10n.danceEditFab),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBody(DanceDetailData detail) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dance = detail.dance;
    final activeDialect = ActiveDialectScope.of(context);
    // When the active dialect is already canonical, _canonicalView is a no-op
    // (both sides of the toggle are identical).  In that case hide the toggle.
    final isCanonicalDialect = activeDialect == Dialect.canonical;
    final dialect = _canonicalView ? Dialect.canonical : activeDialect;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          color: theme.colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dance.title, style: theme.textTheme.headlineMedium),
                if (detail.authorNames.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    detail.authorNames.join(', '),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    const Icon(formationIcon, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          // Per-formation label colour (issue #367): highlight
                          // only when the user overrode this shape.
                          final color = FormationColorsScope.of(
                            context,
                          )?.overrideFor(dance.formation.shape);
                          final text = Text(
                            formationLabel(l10n, dance.formation),
                          );
                          if (color == null) return text;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: FormationColorBadge(
                              color: color,
                              child: text,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    const Icon(progressionIcon, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Text(progressionLabel(l10n, dance.progression)),
                  ],
                ),
                if (dance.mixer) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      const Icon(Icons.sync_alt, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Text(l10n.commonMixer),
                    ],
                  ),
                ],
                if (dance.status != DanceStatus.active) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _StatusBanner(status: dance.status),
                ],
                if (dance.provenance != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _ProvenanceLine(provenance: dance.provenance!),
                ],
                if (dance.hook.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  _CrossReferenceText(
                    text: _renderer.renderFreeText(dance.hook, dialect),
                    style: theme.textTheme.bodyLarge,
                    linker: detail.crossRefLinker,
                    onOpenDance: _openDance,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (detail.tags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Builder(
            builder: (context) {
              // Tapping a tag filters the Collection to it (issue #414). Only
              // wired for a saved dance (not an online preview) and only when
              // the app-level coordinator scope is present; otherwise the chips
              // stay non-interactive, preserving prior behaviour.
              final filter = _isPreview
                  ? null
                  : CollectionFilterScope.maybeOf(context);
              return Wrap(
                spacing: 8,
                children: [
                  for (final tag in detail.tags)
                    if (filter != null)
                      TagChip(
                        key: ValueKey('tag-filter-chip-${tag.id}'),
                        name: tag.name,
                        color: tag.color,
                        tooltip: l10n.commonShowDancesTaggedTooltip(tag.name),
                        onPressed: () => filter.filterByTag(tag.id),
                      )
                    else
                      TagChip(name: tag.name, color: tag.color),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Text(l10n.danceSectionFigures, style: theme.textTheme.titleMedium),
            const Spacer(),
            if (!isCanonicalDialect)
              _DialectToggle(
                canonical: _canonicalView,
                onChanged: (value) => setState(() {
                  _canonicalUserSet = true;
                  _canonicalView = value;
                }),
              ),
          ],
        ),
        FigureTable(
          figures: dance.figures,
          phraseStructure: dance.phraseStructure,
          renderer: _renderer,
          dialect: dialect,
        ),
        if (dance.callingNotes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.danceSectionCallingNotes,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xxs),
          _CrossReferenceText(
            text: _renderer.renderFreeText(dance.callingNotes, dialect),
            style: theme.textTheme.bodyMedium,
            linker: detail.crossRefLinker,
            onOpenDance: _openDance,
          ),
        ],
        if (dance.walkthrough.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.danceSectionWalkthrough,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xxs),
          _CrossReferenceText(
            text: _renderer.renderFreeText(dance.walkthrough.trim(), dialect),
            style: theme.textTheme.bodyMedium,
            linker: detail.crossRefLinker,
            onOpenDance: _openDance,
          ),
        ],
        if (dance.tunes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.danceSectionTunes, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(dance.tunes.join(', ')),
        ],
        if (dance.links.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.danceSectionLinks, style: theme.textTheme.titleMedium),
          for (final link in dance.links)
            _LinkRow(
              key: ValueKey('link-row-${link.id}'),
              link: link,
              relatedDanceTitle: link.kind == LinkKind.relatedDance
                  ? (detail.relatedDanceTitles[link.targetDanceId ?? ''] ??
                        l10n.danceMissingRelated)
                  : null,
              // Routed through [_openDance] rather than pushing inline: this
              // was a second, un-awaited copy of the same navigation, so a
              // dance renamed on the pushed screen left this row showing the
              // old title (issue #768).
              onTap:
                  link.kind == LinkKind.relatedDance &&
                      link.targetDanceId != null &&
                      detail.relatedDanceTitles.containsKey(link.targetDanceId)
                  ? () => _openDance(link.targetDanceId!)
                  : null,
            ),
        ],
        if (dance.sourceCitations.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.danceSectionPublishedSources,
            style: theme.textTheme.titleMedium,
          ),
          for (final citation in dance.sourceCitations)
            _SourceCitationRow(
              key: ValueKey('source-citation-${citation.sourceId}'),
              citation: citation,
              source: detail.sourcesById[citation.sourceId],
            ),
        ],
        if (detail.customFields.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.danceSectionCustomFields,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (final field in detail.customFields)
            Padding(
              // intentional: 2px optical inset, below the 4px AppSpacing grid
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${field.label}: ${field.value}'),
            ),
        ],
        // Calling history is a collection-only concept — hidden for a
        // not-yet-imported online preview. Unlike every other section here it
        // is NOT read from [detail]: it subscribes to the database directly
        // (issue #768), so a program-side write reaches it without this screen
        // reloading. See [CallingHistorySection] for the pattern.
        if (!_isPreview)
          CallingHistorySection(
            repositories: _repos,
            danceId: widget.danceId!,
            performedOnly: _requirePerformedForHistory,
            trackAllCallers: _trackHistoryForAllCallers,
            onOpenProgram: _openProgram,
          ),
      ],
    );
  }

  /// Opens the read-focused [ProgramSummaryScreen] for [programId] — the same
  /// destination tapping a saved program in the programs list reaches, with
  /// Perform first and the builder a tap away behind "Edit program".
  ///
  /// No reload on return, deliberately. The summary can mark slots performed
  /// ("Mark all performed", or adjustments made while performing) and can
  /// delete the program outright, all of which change the calling history —
  /// and all of which are writes to `program_slots` / `programs`, so
  /// [CallingHistorySection] receives them while this route is still on top.
  /// Nothing else on this screen is program-derived (issue #768).
  Future<void> _openProgram(String programId) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProgramSummaryScreen(programId: programId),
    ),
  );
}

class _DialectToggle extends StatelessWidget {
  const _DialectToggle({required this.canonical, required this.onChanged});

  final bool canonical;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.danceShowCanonicalTerms,
      toggled: canonical,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.danceCanonicalToggleLabel),
          Switch(
            key: const ValueKey('dialect-toggle'),
            value: canonical,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final DanceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final (icon, color) = switch (status) {
      DanceStatus.broken => (Icons.error_outline, theme.colorScheme.error),
      DanceStatus.deprecated => (
        Icons.warning_amber_outlined,
        theme.colorScheme.tertiary,
      ),
      DanceStatus.active => (
        Icons.check_circle_outline,
        theme.colorScheme.primary,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            danceStatusLabel(l10n, status),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProvenanceLine extends StatelessWidget {
  const _ProvenanceLine({required this.provenance});

  final Provenance provenance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final license = provenance.license;
    final text = [
      l10n.danceProvenanceVia(_sourceLabel(l10n, provenance.source)),
      if (license != null && license.isNotEmpty) license,
    ].join(' · ');
    return Row(
      children: [
        const Icon(Icons.source_outlined, size: 16),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static String _sourceLabel(AppLocalizations l10n, ProvenanceSource source) =>
      switch (source) {
        ProvenanceSource.callersbox => "The Caller's Box",
        ProvenanceSource.contradb => 'ContraDB',
        ProvenanceSource.callersCompanion => "Caller's Companion",
        ProvenanceSource.manual => l10n.danceProvenanceSourceManual,
        ProvenanceSource.json => l10n.danceProvenanceSourceJson,
      };
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    super.key,
    required this.link,
    this.relatedDanceTitle,
    this.onTap,
  });

  final DanceLink link;

  /// For relatedDance links: the target dance's title, or `"(missing dance)"`
  /// if the target has been deleted/purged.  `null` for non-relatedDance links.
  final String? relatedDanceTitle;

  /// If non-null, the row is tappable and calls this callback.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = link.label?.trim();
    final String display;
    if (label != null && label.isNotEmpty) {
      display = label;
    } else if (link.kind == LinkKind.relatedDance) {
      display = relatedDanceTitle ?? link.targetDanceId ?? '';
    } else {
      display = link.url ?? '';
    }
    final icon = switch (link.kind) {
      LinkKind.source => Icons.article_outlined,
      LinkKind.video => Icons.play_circle_outline,
      LinkKind.relatedDance => Icons.link,
      LinkKind.other => Icons.open_in_new,
    };

    // A URL-bearing kind (source/video/other) is launchable only when it
    // carries a valid http(s) URL. relatedDance keeps its internal-nav [onTap];
    // an invalid/missing external URL falls back to plain, non-interactive text.
    final externalUrl = link.kind == LinkKind.relatedDance
        ? null
        : (tryParseHttpUrl(link.url) != null ? link.url : null);

    if (externalUrl != null) {
      final kindNoun = switch (link.kind) {
        LinkKind.video => l10n.danceLinkKindVideo,
        LinkKind.source => l10n.danceLinkKindSource,
        LinkKind.relatedDance => l10n.danceLinkKindLink,
        LinkKind.other => l10n.danceLinkKindLink,
      };
      // MergeSemantics + Semantics(button:) collapses the row into a single
      // focusable button node whose label conveys that it leaves the app; the
      // icons (kind + open_in_new affordance) are decorative.
      return MergeSemantics(
        child: Semantics(
          button: true,
          label: l10n.danceOpenLinkSemantic(kindNoun, display),
          child: InkWell(
            onTap: () => launchExternalUrl(context, externalUrl),
            child: ExcludeSemantics(
              child: Padding(
                // intentional: 2px optical inset, below the 4px AppSpacing grid
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(icon, size: 16),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: Text(display)),
                    const Icon(Icons.open_in_new, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget content = Padding(
      // intentional: 2px optical inset, below the 4px AppSpacing grid
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(display)),
          if (onTap != null) const Icon(Icons.chevron_right, size: 16),
        ],
      ),
    );
    if (onTap != null) {
      content = InkWell(onTap: onTap, child: content);
    }
    return content;
  }
}

/// One entry in the dance's calling history: a program the dance is included
/// in. A single merged-semantics button exposing the program title, its
/// effective date (the slot's `performedAt` when set, else the program's
/// `eventDate`, else its last-updated time), and the venue if present; tapping
/// opens the program. Mirrors the row-as-button a11y pattern used by [_LinkRow]
/// and the set-list rows in `programs_shell.dart`.
/// A single cited published source: title (+ author/year), the citation's
/// page/number, and the source's URL if present. Read-only display mirroring
/// [_LinkRow]. A [Semantics] label collapses the multi-line content into one
/// screen-reader announcement.
class _SourceCitationRow extends StatelessWidget {
  const _SourceCitationRow({super.key, required this.citation, this.source});

  final SourceCitation citation;

  /// The resolved shared source, or `null` if it has been purged.
  final PublishedSource? source;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final title = source?.title ?? l10n.danceSourceUnknown;

    final bibParts = <String>[
      if (source?.author != null) source!.author!,
      if (source?.year != null) source!.year!.toString(),
    ];
    final bib = bibParts.isEmpty ? null : bibParts.join(', ');

    final locParts = <String>[
      if (citation.page != null) l10n.danceSourcePage(citation.page!),
      if (citation.number != null) l10n.danceSourceNumber(citation.number!),
    ];
    final loc = locParts.isEmpty ? null : locParts.join(', ');
    final url = source?.url;
    final launchableUrl = tryParseHttpUrl(url) != null ? url : null;

    final infoColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          bib == null ? title : '$title — $bib',
          style: theme.textTheme.bodyMedium,
        ),
        if (loc != null) Text(loc, style: theme.textTheme.bodySmall),
        if (url != null)
          launchableUrl != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        url,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                )
              : Text(
                  url,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
      ],
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            // intentional: 2px optical inset, below the 4px AppSpacing grid
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.menu_book_outlined, size: 16),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: infoColumn),
        ],
      ),
    );

    // When the source carries a valid http(s) URL, the whole row becomes a
    // single launchable button node whose label conveys it opens externally.
    // Otherwise it stays a read-only announcement (mirroring the plain-text
    // display for missing/invalid URLs).
    if (launchableUrl != null) {
      return MergeSemantics(
        child: Semantics(
          button: true,
          label: l10n.danceOpenSourceLinkSemantic(title),
          child: InkWell(
            onTap: () => launchExternalUrl(context, launchableUrl),
            child: ExcludeSemantics(child: row),
          ),
        ),
      );
    }

    final semanticLabel = [
      l10n.danceSourceSemanticPrefix(title),
      ?bib,
      ?loc,
      ?url,
    ].join(', ');
    return Semantics(label: semanticLabel, excludeSemantics: true, child: row);
  }
}

/// Renders free text (hook / calling notes) with any mention of another
/// dance's title turned into a tappable cross-reference link that opens that
/// dance. Falls back to a plain [Text] when there is nothing to link, so
/// non-matching text is rendered exactly as before.
class _CrossReferenceText extends StatelessWidget {
  const _CrossReferenceText({
    required this.text,
    required this.style,
    required this.linker,
    required this.onOpenDance,
  });

  final String text;
  final TextStyle? style;
  final DanceTitleLinker linker;
  final void Function(String danceId) onOpenDance;

  @override
  Widget build(BuildContext context) {
    if (!linker.hasTitles) {
      return Text(text, style: style);
    }

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final linkStyle = (style ?? const TextStyle()).copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );

    final spans = linker.spansFor(
      text,
      baseStyle: style,
      buildLink: (matchedText, danceId) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        // One semantics node per link: link role + descriptive label +
        // focusable + tap action (via InkWell); the visible text is decorative.
        child: MergeSemantics(
          child: Semantics(
            link: true,
            label: l10n.danceOpenDanceCrossRefSemantic(matchedText),
            child: InkWell(
              onTap: () => onOpenDance(danceId),
              child: ExcludeSemantics(
                child: Text(matchedText, style: linkStyle),
              ),
            ),
          ),
        ),
      ),
    );

    if (spans.length == 1 && spans.first is TextSpan) {
      // No links were produced (e.g. all matches resolved to unknown ids);
      // render as plain text.
      final only = spans.first as TextSpan;
      if (only.children == null) {
        return Text(only.text ?? text, style: style);
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}
