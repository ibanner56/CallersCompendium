import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../data/active_dialect_scope.dart';
import '../data/dialect_library_scope.dart';
import '../data/display_defaults.dart';
import '../data/repositories_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../export/dance_pdf.dart';
import '../models/dance_list_entry.dart';
import '../search/facet_labels.dart';
import '../utils/confirm_delete.dart';
import '../utils/launch_external_url.dart';
import '../widgets/add_to_program_sheet.dart';
import '../widgets/dance_export_menu.dart';
import '../widgets/dialect_quick_switch.dart';
import '../widgets/figure_table.dart';
import '../widgets/skeleton.dart';
import 'dance_editor_screen.dart';
import 'perform_dance_screen.dart';
import 'program_editor_screen.dart';

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
  });

  final String danceId;

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
  Future<_DanceDetail?>? _future;

  /// The last-seen value of the "require mark-performed for calling history"
  /// setting (ROADMAP G.2). Tracked so [didChangeDependencies] can reload the
  /// calling history when the setting is toggled while this screen is open.
  bool _requirePerformedForHistory = false;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final requirePerformed = RequirePerformedForHistoryScope.of(context);
    // Only load once, but reload if the calling-history setting changed: this
    // callback also fires for unrelated ancestor changes (Theme/MediaQuery/
    // Localizations), so guard on the setting actually differing.
    if (_future == null) {
      _repos = RepositoriesScope.of(context);
      _requirePerformedForHistory = requirePerformed;
      _future = _load();
    } else if (requirePerformed != _requirePerformedForHistory) {
      _requirePerformedForHistory = requirePerformed;
      _reload();
    }
  }

  Future<_DanceDetail?> _load() async {
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
        // Keep the historical default (active dialect).
      }
    }

    final dance = await _repos.dances.getById(widget.danceId);
    if (dance == null) return null;

    final choreographers = await _repos.choreographers.listAll();
    final tags = await _repos.tags.listAll();
    final fieldDefs = await _repos.customFieldDefs.listAll();
    final choreographerNames = {for (final c in choreographers) c.id: c.name};
    final tagNames = {for (final t in tags) t.id: t.name};
    final defsById = {for (final d in fieldDefs) d.id: d};

    // Resolve titles for relatedDance links in parallel (deduplicated).
    final relatedDanceTitles = <String, String>{};
    final targetIds = dance.links
        .where(
          (l) => l.kind == LinkKind.relatedDance && l.targetDanceId != null,
        )
        .map((l) => l.targetDanceId!)
        .toSet();
    if (targetIds.isNotEmpty) {
      final fetched = await Future.wait(
        targetIds.map((id) => _repos.dances.getById(id)),
      );
      for (final (i, dance) in fetched.indexed) {
        if (dance != null) {
          relatedDanceTitles[targetIds.elementAt(i)] = dance.title;
        }
      }
    }

    // Resolve the cited published sources (deduplicated) for display.
    final sourcesById = <String, PublishedSource>{};
    final citedSourceIds = dance.sourceCitations.map((c) => c.sourceId).toSet();
    if (citedSourceIds.isNotEmpty) {
      final fetched = await Future.wait(
        citedSourceIds.map((id) => _repos.publishedSources.getById(id)),
      );
      for (final source in fetched) {
        if (source != null) sourcesById[source.id] = source;
      }
    }

    // Candidate cross-reference targets: every other non-deleted dance's title.
    // Loaded via the lightweight id+title query (no per-dance hydration).
    final titlePairs = await _repos.dances.listIdsAndTitles();
    final crossRefLinker = _DanceTitleLinker.build(
      titlePairs,
      excludeId: dance.id,
    );

    return _DanceDetail(
      dance: dance,
      authorNames: [
        for (final id in dance.authorIds)
          if (choreographerNames[id] != null) choreographerNames[id]!,
      ],
      tagNames: [
        for (final id in dance.tagIds)
          if (tagNames[id] != null) tagNames[id]!,
      ],
      customFields: [
        for (final value in dance.customFields)
          if (defsById[value.fieldId] case final def?)
            (label: def.label, value: _formatFieldValue(value.value)),
      ],
      relatedDanceTitles: relatedDanceTitles,
      sourcesById: sourcesById,
      callingHistory: await _repos.programs.callingHistoryForDance(
        widget.danceId,
        performedOnly: _requirePerformedForHistory,
      ),
      crossRefLinker: crossRefLinker,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// Human-readable difficulty label for the export card, combining the
  /// ordered [Dance.level] with the [Dance.mixedLevel] flag. Returns `null`
  /// when neither is set so the export omits the Level line.
  static String? _levelLabel(Dance dance) {
    final base = dance.level != null ? danceLevelLabel(dance.level!) : null;
    if (base != null) return dance.mixedLevel ? '$base (mixed)' : base;
    return dance.mixedLevel ? 'Mixed' : null;
  }

  /// Opens the full-screen large-print [PerformDanceScreen] for this dance,
  /// passing the shared [FigureRenderer] and the already-resolved author names.
  Future<void> _perform(_DanceDetail detail) async {
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
        builder: (_) => DanceEditorScreen(danceId: widget.danceId),
      ),
    );
    if (mounted) _reload();
  }

  /// Opens another dance's detail from an auto cross-reference link in the
  /// hook / calling notes. Mirrors the `relatedDance` link navigation so the
  /// two kinds of dance-to-dance links behave identically.
  void _openDance(String danceId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DanceDetailScreen(danceId: danceId),
      ),
    );
  }

  /// Duplicates the dance, appends " (copy)" to the copy's title (since
  /// [Dance.duplicate] preserves the original title verbatim), then navigates
  /// to the new copy's detail screen. In routed mode, uses
  /// [Navigator.pushReplacement]; in embedded split-pane mode, calls
  /// [widget.onNavigateTo] so the parent shell updates the selected id.
  Future<void> _duplicate() async {
    final now = DateTime.now().toUtc();
    final copy = await _repos.dances.duplicate(
      id: widget.danceId,
      newId: uuidV4(),
      now: now,
    );
    // Append " (copy)" so the duplicate is visually distinct in the list.
    await _repos.dances.update(
      copy.copyWith(title: '${copy.title} (copy)', updatedAt: now),
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
    final title = (await _future)?.dance.title ?? 'Dance';
    if (!mounted) return;
    // ROADMAP G.7: optional confirm dialog before the (still-undoable) delete.
    if (!await confirmDeleteIfEnabled(context, itemLabel: title)) return;
    if (!mounted) return;
    final now = DateTime.now().toUtc();
    await _repos.dances.softDelete(widget.danceId, at: now);
    if (!mounted) return;
    // Capture ScaffoldMessengerState before any navigation/callback so we
    // don't read a deactivating context after the widget is removed.
    final messenger = ScaffoldMessenger.of(context);
    // Show the snackbar first so the Scaffold is still in the tree when the
    // messenger enqueues it — then notify the parent (which may unmount this
    // widget) or pop the route.
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('deleted-snackbar'),
        content: Text('"$title" deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await _repos.dances.restore(
              widget.danceId,
              at: DateTime.now().toUtc(),
            );
            widget.onRestored?.call();
          },
        ),
      ),
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
  Future<void> _addToProgram(String danceTitle) => showAddToProgramSheet(
    context,
    repositories: _repos,
    danceId: widget.danceId,
    danceTitle: danceTitle,
  );

  // --- App-bar actions -------------------------------------------------------
  // The dance-detail bar carries seven affordances (dialect switch, Perform,
  // Export, Duplicate, Add-to-program, Delete, plus the Edit FAB). On a phone
  // that full row clips, so below [DanceDetailScreen.compactActionsBreakpoint]
  // we keep the primary one-tap actions (Perform, Add-to-program; Edit stays
  // the FAB) and fold the secondary actions into a single overflow menu. Every
  // action keeps its key, tooltip/label and behaviour in both layouts.

  Widget _performButton(_DanceDetail detail) => IconButton(
    key: const ValueKey('perform-dance'),
    tooltip: 'Perform this dance',
    icon: const Icon(Icons.slideshow),
    onPressed: () => _perform(detail),
  );

  Widget _addToProgramButton(_DanceDetail detail) => IconButton(
    key: const ValueKey('add-dance-to-program'),
    tooltip: 'Add to program',
    icon: const Icon(Icons.playlist_add),
    onPressed: () => _addToProgram(detail.dance.title),
  );

  DanceExportMenu _exportMenu(BuildContext context, _DanceDetail detail) =>
      DanceExportMenu(
        dance: detail.dance,
        dialect: ActiveDialectScope.of(context),
        authorNames: detail.authorNames,
        formationLabel: formationLabel(detail.dance.formation),
        levelLabel: _levelLabel(detail.dance),
        statusLabel: danceStatusLabel(detail.dance.status),
        renderer: _renderer,
      );

  /// Wide layout: the full one-tap action row.
  Widget _fullActions(BuildContext context, _DanceDetail detail) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const DialectQuickSwitch(),
      _performButton(detail),
      _exportMenu(context, detail),
      IconButton(
        key: const ValueKey('duplicate-dance'),
        tooltip: 'Duplicate dance',
        icon: const Icon(Icons.copy_all_outlined),
        onPressed: _duplicate,
      ),
      _addToProgramButton(detail),
      IconButton(
        key: const ValueKey('delete-dance'),
        tooltip: 'Delete dance',
        icon: const Icon(Icons.delete_outline),
        onPressed: _delete,
      ),
    ],
  );

  /// Narrow layout: primary actions stay as icon buttons; the rest collapse
  /// into the overflow menu.
  Widget _compactActions(BuildContext context, _DanceDetail detail) => Row(
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
  Widget _overflowMenu(BuildContext context, _DanceDetail detail) {
    final controller = DialectLibraryScope.maybeOf(context);
    final activeDialectName = controller == null
        ? null
        : (controller.activeName ?? controller.active.name);
    final dialect = ActiveDialectScope.of(context);
    String exportText() => danceToPlainText(
      detail.dance,
      dialect: dialect,
      authorNames: detail.authorNames,
      formationLabel: formationLabel(detail.dance.formation),
      levelLabel: _levelLabel(detail.dance),
      statusLabel: danceStatusLabel(detail.dance.status),
      renderer: _renderer,
    );

    return PopupMenuButton<void>(
      key: const ValueKey('dance-actions-overflow'),
      tooltip: 'More actions',
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
          child: const ListTile(
            leading: Icon(Icons.mail_outline),
            title: Text('Share dance (text)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<void>(
          key: const ValueKey('overflow-copy-dance'),
          onTap: () => _copyDance(exportText()),
          child: const ListTile(
            leading: Icon(Icons.copy_outlined),
            title: Text('Copy dance'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<void>(
          key: const ValueKey('overflow-export-pdf'),
          onTap: () => _exportDancePdf(dialect, detail),
          child: const ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('Export / print PDF'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          key: const ValueKey('duplicate-dance'),
          onTap: _duplicate,
          child: const ListTile(
            leading: Icon(Icons.copy_all_outlined),
            title: Text('Duplicate dance'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<void>(
          key: const ValueKey('delete-dance'),
          onTap: _delete,
          child: const ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete dance'),
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
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    } on Exception catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't share this dance")),
      );
    }
  }

  Future<void> _copyDance(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      const SnackBar(content: Text('Dance copied to clipboard.')),
    );
  }

  Future<void> _exportDancePdf(Dialect dialect, _DanceDetail detail) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Printing.layoutPdf(
        name: detail.dance.title,
        onLayout: (format) => buildDancePdf(
          detail.dance,
          dialect: dialect,
          authorNames: detail.authorNames,
          formationLabel: formationLabel(detail.dance.formation),
          levelLabel: _levelLabel(detail.dance),
          statusLabel: danceStatusLabel(detail.dance.status),
          renderer: _renderer,
        ),
      );
    } on Exception catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't export this dance")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < DanceDetailScreen.compactActionsBreakpoint;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Dance'),
            actions: [
              FutureBuilder<_DanceDetail?>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.data == null) return const SizedBox.shrink();
                  final detail = snapshot.data!;
                  return compact
                      ? _compactActions(context, detail)
                      : _fullActions(context, detail);
                },
              ),
            ],
          ),
          body: FutureBuilder<_DanceDetail?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SkeletonDetailView();
              }
              final detail = snapshot.data;
              if (detail == null) {
                return const Center(child: Text('Dance not found.'));
              }
              return _buildBody(detail);
            },
          ),
          // Edit mirrors the program preview's builder affordance: a bottom-right
          // extended FAB (`docs/design/ux.md` §2/§3) rather than an AppBar action,
          // so opening the editor is consistent across the dance and program views.
          floatingActionButton: FutureBuilder<_DanceDetail?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.data == null) return const SizedBox.shrink();
              return FloatingActionButton.extended(
                key: const ValueKey('edit-dance'),
                heroTag: 'edit-dance',
                onPressed: _openEditor,
                icon: const Icon(Icons.edit_note),
                label: const Text('Edit'),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBody(_DanceDetail detail) {
    final theme = Theme.of(context);
    final dance = detail.dance;
    final activeDialect = ActiveDialectScope.of(context);
    // When the active dialect is already canonical, _canonicalView is a no-op
    // (both sides of the toggle are identical).  In that case hide the toggle.
    final isCanonicalDialect = activeDialect == Dialect.canonical;
    final dialect = _canonicalView ? Dialect.canonical : activeDialect;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: theme.colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dance.title, style: theme.textTheme.headlineMedium),
                if (detail.authorNames.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail.authorNames.join(', '),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(formationIcon, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(formationLabel(dance.formation))),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(progressionIcon, size: 18),
                    const SizedBox(width: 6),
                    Text(progressionLabel(dance.progression)),
                  ],
                ),
                if (dance.status != DanceStatus.active) ...[
                  const SizedBox(height: 12),
                  _StatusBanner(status: dance.status),
                ],
                if (dance.provenance != null) ...[
                  const SizedBox(height: 8),
                  _ProvenanceLine(provenance: dance.provenance!),
                ],
                if (dance.hook.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _CrossReferenceText(
                    text: dance.hook,
                    style: theme.textTheme.bodyLarge,
                    linker: detail.crossRefLinker,
                    onOpenDance: _openDance,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (detail.tagNames.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final tag in detail.tagNames)
                Chip(
                  avatar: const Icon(Icons.label_outline, size: 16),
                  label: Text(tag),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Text('Figures', style: theme.textTheme.titleMedium),
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
          const SizedBox(height: 24),
          Text('Calling notes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          _CrossReferenceText(
            text: _renderer.renderFreeText(dance.callingNotes, dialect),
            style: theme.textTheme.bodyMedium,
            linker: detail.crossRefLinker,
            onOpenDance: _openDance,
          ),
        ],
        if (dance.tunes.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Tunes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(dance.tunes.join(', ')),
        ],
        if (dance.links.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Links', style: theme.textTheme.titleMedium),
          for (final link in dance.links)
            _LinkRow(
              key: ValueKey('link-row-${link.id}'),
              link: link,
              relatedDanceTitle: link.kind == LinkKind.relatedDance
                  ? (detail.relatedDanceTitles[link.targetDanceId ?? ''] ??
                        '(missing dance)')
                  : null,
              onTap:
                  link.kind == LinkKind.relatedDance &&
                      link.targetDanceId != null &&
                      detail.relatedDanceTitles.containsKey(link.targetDanceId)
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            DanceDetailScreen(danceId: link.targetDanceId!),
                      ),
                    )
                  : null,
            ),
        ],
        if (dance.sourceCitations.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Published sources', style: theme.textTheme.titleMedium),
          for (final citation in dance.sourceCitations)
            _SourceCitationRow(
              key: ValueKey('source-citation-${citation.sourceId}'),
              citation: citation,
              source: detail.sourcesById[citation.sourceId],
            ),
        ],
        if (detail.customFields.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Custom fields', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final field in detail.customFields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${field.label}: ${field.value}'),
            ),
        ],
        const SizedBox(height: 24),
        Text('Calling history', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        if (detail.callingHistory.isEmpty)
          Padding(
            key: const ValueKey('calling-history-empty'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              'Not yet included in any program.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final record in detail.callingHistory)
            _CallingHistoryRow(
              key: ValueKey('calling-history-${record.slotId}'),
              record: record,
              onTap: () => _openProgram(record.programId),
            ),
      ],
    );
  }

  /// Opens the full-screen [ProgramEditorScreen] for [programId] (the same
  /// route used from the programs list), then reloads so any change to the
  /// program's performance history is reflected on return.
  Future<void> _openProgram(String programId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProgramEditorScreen(programId: programId),
      ),
    );
    if (mounted) _reload();
  }
}

String _formatFieldValue(Object value) {
  if (value is bool) return value ? 'Yes' : 'No';
  return value.toString();
}

class _DialectToggle extends StatelessWidget {
  const _DialectToggle({required this.canonical, required this.onChanged});

  final bool canonical;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Show canonical terms',
      toggled: canonical,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Canonical'),
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
    final (icon, color) = switch (status) {
      DanceStatus.broken => (Icons.error_outline, theme.colorScheme.error),
      DanceStatus.deprecated => (
        Icons.warning_amber,
        theme.colorScheme.tertiary,
      ),
      DanceStatus.active => (
        Icons.check_circle_outline,
        theme.colorScheme.primary,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            danceStatusLabel(status),
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
    final theme = Theme.of(context);
    final license = provenance.license;
    final text = [
      'via ${_sourceLabel(provenance.source)}',
      if (license != null && license.isNotEmpty) license,
    ].join(' · ');
    return Row(
      children: [
        const Icon(Icons.source_outlined, size: 16),
        const SizedBox(width: 6),
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

  static String _sourceLabel(ProvenanceSource source) => switch (source) {
    ProvenanceSource.callersbox => "The Caller's Box",
    ProvenanceSource.contradb => 'ContraDB',
    ProvenanceSource.callersCompanion => "Caller's Companion",
    ProvenanceSource.manual => 'manual entry',
    ProvenanceSource.json => 'JSON import',
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
        LinkKind.video => 'video',
        LinkKind.source => 'source link',
        LinkKind.relatedDance => 'link',
        LinkKind.other => 'link',
      };
      // MergeSemantics + Semantics(button:) collapses the row into a single
      // focusable button node whose label conveys that it leaves the app; the
      // icons (kind + open_in_new affordance) are decorative.
      return MergeSemantics(
        child: Semantics(
          button: true,
          label: 'Open $kindNoun: $display',
          child: InkWell(
            onTap: () => launchExternalUrl(context, externalUrl),
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(icon, size: 16),
                    const SizedBox(width: 6),
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
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
class _CallingHistoryRow extends StatelessWidget {
  const _CallingHistoryRow({super.key, required this.record, this.onTap});

  final DanceCallingRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    // Programs appear as soon as they include the dance, so `performedAt` is
    // often null; `effectiveDate` falls back to the program's event date, then
    // its last-updated time, so a date always shows. These are stored UTC
    // values rendered directly (matching the other date labels on this screen).
    final date = localizations.formatMediumDate(record.effectiveDate);
    final venue = record.venue?.trim();
    final subtitleParts = <String>[
      date,
      if (venue != null && venue.isNotEmpty) venue,
    ];
    final subtitle = subtitleParts.join(' · ');

    return MergeSemantics(
      child: Semantics(
        button: true,
        label:
            'Open program: ${record.programTitle}, ${subtitleParts.join(', ')}',
        child: InkWell(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.event_note_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.programTitle,
                          style: theme.textTheme.bodyLarge,
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    final theme = Theme.of(context);
    final title = source?.title ?? '(unknown source)';

    final bibParts = <String>[
      if (source?.author != null) source!.author!,
      if (source?.year != null) source!.year!.toString(),
    ];
    final bib = bibParts.isEmpty ? null : bibParts.join(', ');

    final locParts = <String>[
      if (citation.page != null) 'p. ${citation.page}',
      if (citation.number != null) 'no. ${citation.number}',
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
                    const SizedBox(width: 4),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.menu_book_outlined, size: 16),
          ),
          const SizedBox(width: 6),
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
          label: 'Open source link: $title',
          child: InkWell(
            onTap: () => launchExternalUrl(context, launchableUrl),
            child: ExcludeSemantics(child: row),
          ),
        ),
      );
    }

    final semanticLabel = ['Source: $title', ?bib, ?loc, ?url].join(', ');
    return Semantics(label: semanticLabel, excludeSemantics: true, child: row);
  }
}

typedef _CustomFieldDisplay = ({String label, String value});

/// Compiles the collection's dance titles into a single matcher used to find
/// dance-title mentions inside another dance's free text (hook / calling
/// notes) so they can be rendered as tappable cross-reference links.
///
/// Matching is case-insensitive, on word boundaries (a title inside a larger
/// word is not matched), and longest-title-wins when several candidate titles
/// could match at the same position. Titles are treated as literal text
/// (regex-special characters are escaped).
class _DanceTitleLinker {
  _DanceTitleLinker._(this._pattern, this._idByNormalizedTitle);

  /// `null` when there are no candidate titles to match.
  final RegExp? _pattern;

  /// Maps a lower-cased title to the id of the dance it refers to. When two
  /// dances share a title the first (title-sorted) one wins — the input is
  /// pre-sorted by title so this is deterministic.
  final Map<String, String> _idByNormalizedTitle;

  /// Builds a linker from `(id, title)` pairs, excluding [excludeId] (never
  /// self-link) and skipping empty / whitespace-only titles.
  factory _DanceTitleLinker.build(
    List<({String id, String title})> pairs, {
    required String excludeId,
  }) {
    final idByNormalized = <String, String>{};
    final titles = <String>[];
    for (final pair in pairs) {
      if (pair.id == excludeId) continue;
      final trimmed = pair.title.trim();
      if (trimmed.isEmpty) continue;
      final normalized = trimmed.toLowerCase();
      // First occurrence wins (input is title-sorted → deterministic).
      if (idByNormalized.containsKey(normalized)) continue;
      idByNormalized[normalized] = pair.id;
      titles.add(trimmed);
    }

    if (titles.isEmpty) {
      return _DanceTitleLinker._(null, idByNormalized);
    }

    // Longest-first so the alternation prefers the longest match at a given
    // position (Dart's RegExp is leftmost / first-alternative-wins, not POSIX
    // longest). Escape each title so punctuation / regex metacharacters are
    // treated literally.
    titles.sort((a, b) => b.length.compareTo(a.length));
    final alternation = titles.map(RegExp.escape).join('|');
    // Alphanumeric look-arounds give word-boundary behavior that is robust to
    // titles that themselves begin or end with punctuation (plain `\b` is not).
    final pattern = RegExp(
      r'(?<![\p{L}\p{N}])(?:'
      '$alternation'
      r')(?![\p{L}\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    return _DanceTitleLinker._(pattern, idByNormalized);
  }

  /// Splits [text] into inline spans, wrapping each matched dance title in a
  /// tappable link span (via [buildLink]) and leaving all other text plain
  /// (styled with [baseStyle]). Returns a single plain span when nothing
  /// matches so callers can keep rendering unchanged text as-is.
  List<InlineSpan> spansFor(
    String text, {
    required TextStyle? baseStyle,
    required InlineSpan Function(String matchedText, String danceId) buildLink,
  }) {
    final pattern = _pattern;
    if (pattern == null || text.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      final id = _idByNormalizedTitle[match[0]!.toLowerCase()];
      if (id == null) continue;
      if (match.start > index) {
        spans.add(
          TextSpan(text: text.substring(index, match.start), style: baseStyle),
        );
      }
      spans.add(buildLink(match[0]!, id));
      index = match.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index), style: baseStyle));
    }
    return spans;
  }

  /// Whether any candidate titles exist (used to short-circuit rendering).
  bool get hasTitles => _pattern != null;
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
  final _DanceTitleLinker linker;
  final void Function(String danceId) onOpenDance;

  @override
  Widget build(BuildContext context) {
    if (!linker.hasTitles) {
      return Text(text, style: style);
    }

    final theme = Theme.of(context);
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
            label: 'Open dance: $matchedText',
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

class _DanceDetail {
  _DanceDetail({
    required this.dance,
    required this.authorNames,
    required this.tagNames,
    required this.customFields,
    required this.relatedDanceTitles,
    required this.sourcesById,
    required this.callingHistory,
    required this.crossRefLinker,
  });

  final Dance dance;
  final List<String> authorNames;
  final List<String> tagNames;
  final List<_CustomFieldDisplay> customFields;

  /// Maps targetDanceId → title for relatedDance links whose target exists.
  /// Missing entries indicate the target dance has been deleted/purged.
  final Map<String, String> relatedDanceTitles;

  /// Maps sourceId → the cited [PublishedSource] for each of the dance's
  /// [SourceCitation]s (missing entries indicate a purged source).
  final Map<String, PublishedSource> sourcesById;

  /// Programs that include this dance (derived query over program slots),
  /// most-recent first. Populated as soon as a program contains the dance;
  /// `performedAt` may be null until the separate "mark performed" path lands.
  final List<DanceCallingRecord> callingHistory;

  /// Matches other dances' titles inside this dance's free text (hook /
  /// calling notes) so they can render as tappable cross-reference links.
  final _DanceTitleLinker crossRefLinker;
}
