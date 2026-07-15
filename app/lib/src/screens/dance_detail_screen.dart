import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../models/dance_list_entry.dart';
import '../search/facet_labels.dart';
import '../utils/launch_external_url.dart';
import '../widgets/dance_export_menu.dart';
import '../widgets/figure_table.dart';
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
  bool _canonicalView = false;

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

  /// Opens a modal bottom sheet listing existing (non-deleted) programs so the
  /// user can append this dance as a new slot at the end of one of them
  /// (`docs/design/ux.md` §2 add-to-program). Programs are ordered
  /// most-recently-updated first. When there are no programs yet, a teaching
  /// empty state offers to create a new program seeded with this dance.
  Future<void> _addToProgram(String danceTitle) async {
    final programs = await _repos.programs.listAll();
    if (!mounted) return;
    programs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 16),
                    Text(
                      'Add to program',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('add-to-program-close'),
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                Expanded(
                  child: programs.isEmpty
                      ? _buildEmptyPrograms(
                          sheetContext,
                          danceTitle,
                          scrollController,
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: programs.length,
                          itemBuilder: (context, index) => _buildProgramPickRow(
                            sheetContext,
                            programs[index],
                            danceTitle,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// One selectable program row: a single merged-semantics button exposing the
  /// program's title, event date (if any), and slot count. Mirrors the
  /// row-as-button pattern in `collection_picker.dart`.
  Widget _buildProgramPickRow(
    BuildContext sheetContext,
    Program program,
    String danceTitle,
  ) {
    final slotCount = program.slots.length;
    final dateLabel = program.eventDate == null
        ? null
        : MaterialLocalizations.of(
            context,
          ).formatMediumDate(program.eventDate!);
    final countLabel = '$slotCount ${slotCount == 1 ? 'dance' : 'dances'}';
    final subtitleParts = [?dateLabel, countLabel];
    return MergeSemantics(
      child: Semantics(
        button: true,
        label:
            'Add "$danceTitle" to ${program.title}, '
            '${subtitleParts.join(', ')}',
        child: ListTile(
          key: ValueKey('program-pick-${program.id}'),
          title: ExcludeSemantics(child: Text(program.title)),
          subtitle: ExcludeSemantics(child: Text(subtitleParts.join(' · '))),
          onTap: () => _selectProgram(sheetContext, program, danceTitle),
        ),
      ),
    );
  }

  /// Teaching empty state shown when no programs exist yet, with an affordance
  /// to create a brand-new program seeded with this dance.
  Widget _buildEmptyPrograms(
    BuildContext sheetContext,
    String danceTitle,
    ScrollController controller,
  ) {
    final theme = Theme.of(context);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        Text(
          'No programs yet',
          key: const ValueKey('add-to-program-empty'),
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Create a program to start building a set list.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            key: const ValueKey('add-to-program-create'),
            onPressed: () => _createProgramWith(sheetContext, danceTitle),
            icon: const Icon(Icons.add),
            label: const Text('Create a new program with this dance'),
          ),
        ),
      ],
    );
  }

  /// Appends this dance as a new slot at the end of [program], persists it,
  /// closes the sheet, and confirms with an Undo snackbar that restores the
  /// program's previous slot list (soft/undoable per project convention).
  Future<void> _selectProgram(
    BuildContext sheetContext,
    Program program,
    String danceTitle,
  ) async {
    // Re-load fresh so we append onto the latest persisted slot list.
    final fresh = await _repos.programs.getById(program.id);
    if (fresh == null) {
      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      return;
    }
    final previousSlots = fresh.slots.toList();
    final now = DateTime.now().toUtc();
    final newSlot = ProgramSlot(
      id: uuidV4(),
      position: fresh.slots.length,
      danceId: widget.danceId,
    );
    await _repos.programs.update(
      fresh.copyWith(slots: [...fresh.slots, newSlot], updatedAt: now),
    );
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('added-to-program-snackbar'),
        content: Text('Added "$danceTitle" to ${fresh.title}.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final current = await _repos.programs.getById(fresh.id);
            if (current == null) return;
            await _repos.programs.update(
              current.copyWith(
                slots: previousSlots,
                updatedAt: DateTime.now().toUtc(),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Creates a new draft program seeded with this dance as its only slot, then
  /// closes the sheet and confirms with a snackbar. (No Undo: the new program
  /// is itself the artifact and can be deleted from the programs list.)
  Future<void> _createProgramWith(
    BuildContext sheetContext,
    String danceTitle,
  ) async {
    final now = DateTime.now().toUtc();
    final program = Program(
      id: uuidV4(),
      title: 'New program',
      slots: [ProgramSlot(id: uuidV4(), position: 0, danceId: widget.danceId)],
      createdAt: now,
      updatedAt: now,
    );
    await _repos.programs.create(program);
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('created-program-snackbar'),
        content: Text('Created "${program.title}" with "$danceTitle".'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dance'),
        actions: [
          FutureBuilder<_DanceDetail?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.data == null) return const SizedBox.shrink();
              final detail = snapshot.data!;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('perform-dance'),
                    tooltip: 'Perform this dance',
                    icon: const Icon(Icons.slideshow),
                    onPressed: () => _perform(detail),
                  ),
                  DanceExportMenu(
                    dance: detail.dance,
                    dialect: ActiveDialectScope.of(context),
                    authorNames: detail.authorNames,
                    formationLabel: formationLabel(detail.dance.formation),
                    levelLabel: _levelLabel(detail.dance),
                    statusLabel: danceStatusLabel(detail.dance.status),
                    renderer: _renderer,
                  ),
                  IconButton(
                    key: const ValueKey('duplicate-dance'),
                    tooltip: 'Duplicate dance',
                    icon: const Icon(Icons.copy_all_outlined),
                    onPressed: _duplicate,
                  ),
                  IconButton(
                    key: const ValueKey('add-dance-to-program'),
                    tooltip: 'Add to program',
                    icon: const Icon(Icons.playlist_add),
                    onPressed: () => _addToProgram(detail.dance.title),
                  ),
                  TextButton.icon(
                    key: const ValueKey('edit-dance'),
                    onPressed: _openEditor,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  IconButton(
                    key: const ValueKey('delete-dance'),
                    tooltip: 'Delete dance',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _delete,
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<_DanceDetail?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final detail = snapshot.data;
          if (detail == null) {
            return const Center(child: Text('Dance not found.'));
          }
          return _buildBody(detail);
        },
      ),
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
                    const Icon(Icons.grid_view, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(formationLabel(dance.formation))),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.repeat, size: 18),
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
                onChanged: (value) => setState(() => _canonicalView = value),
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
