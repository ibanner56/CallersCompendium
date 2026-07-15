import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';
import '../models/dance_list_entry.dart';
import '../search/collection_data.dart';
import '../search/facet_labels.dart';
import '../widgets/program_export_menu.dart';
import '../widgets/program_status_chip.dart';
import 'dance_detail_screen.dart';
import 'perform_program_screen.dart';
import 'program_editor_screen.dart';
import 'programs_list_screen.dart';

/// Responsive Programs shell (`docs/design/ux.md` §4), mirroring
/// [CollectionShell].
///
/// **Breakpoint: 900 logical pixels wide.**
/// - **Narrow (< 900 px):** [ProgramsListScreen] with push-navigation to the
///   full-screen [ProgramEditorScreen] builder route.
/// - **Wide (≥ 900 px):** master-detail [Row] — a fixed 400 px list pane and a
///   lightweight **summary** pane for the selected program. Building/editing
///   opens the **full-screen** builder route (not embedded) so the builder's
///   slots | picker two-pane gets the full content width.
class ProgramsShell extends StatefulWidget {
  const ProgramsShell({super.key});

  static const double splitBreakpoint = 900;
  static const double listPaneWidth = 400;

  @override
  State<ProgramsShell> createState() => _ProgramsShellState();
}

class _ProgramsShellState extends State<ProgramsShell> {
  String? _selectedProgramId;
  final _listRefresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _listRefresh.dispose();
    super.dispose();
  }

  void _onSelectProgram(String id) {
    setState(() => _selectedProgramId = id);
  }

  /// Opens the full-screen builder route and refreshes the browse panes on
  /// return.
  Future<void> _openBuilder(BuildContext context, {String? programId}) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ProgramEditorScreen(programId: programId),
      ),
    );
    if (!mounted) return;
    if (result == 'deleted') {
      _listRefresh.value++;
      setState(() => _selectedProgramId = null);
    } else if (result != null) {
      _listRefresh.value++;
      setState(() => _selectedProgramId = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= ProgramsShell.splitBreakpoint) {
          return _buildSplitPane();
        }
        return const ProgramsListScreen();
      },
    );
  }

  Widget _buildSplitPane() {
    final selectedId = _selectedProgramId;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: ProgramsShell.listPaneWidth,
          child: ScaffoldMessenger(
            child: ProgramsListScreen(
              onSelectProgram: _onSelectProgram,
              onCreateProgram: () => _openBuilder(context),
              selectedProgramId: _selectedProgramId,
              refreshTrigger: _listRefresh,
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: ScaffoldMessenger(
            child: selectedId != null
                ? _ProgramSummaryPane(
                    key: ValueKey('summary-$selectedId'),
                    programId: selectedId,
                    refreshTrigger: _listRefresh,
                    onOpenBuilder: () =>
                        _openBuilder(context, programId: selectedId),
                    onDeleted: () {
                      _listRefresh.value++;
                      setState(() => _selectedProgramId = null);
                    },
                    onNavigateTo: (id) {
                      _listRefresh.value++;
                      setState(() => _selectedProgramId = id);
                    },
                  )
                : const _EmptyEditorPane(),
          ),
        ),
      ],
    );
  }
}

/// Read-only summary of the selected program shown in the wide detail pane. The
/// heavy building work happens in the full-screen [ProgramEditorScreen] route
/// launched by [onOpenBuilder]; this pane keeps quick duplicate/delete actions.
class _ProgramSummaryPane extends StatefulWidget {
  const _ProgramSummaryPane({
    super.key,
    required this.programId,
    required this.refreshTrigger,
    required this.onOpenBuilder,
    required this.onDeleted,
    required this.onNavigateTo,
  });

  final String programId;
  final ValueListenable<int> refreshTrigger;
  final VoidCallback onOpenBuilder;
  final VoidCallback onDeleted;
  final void Function(String id) onNavigateTo;

  @override
  State<_ProgramSummaryPane> createState() => _ProgramSummaryPaneState();
}

class _ProgramSummaryPaneState extends State<_ProgramSummaryPane> {
  late CompendiumRepositories _repos;
  bool _started = false;
  Program? _program;
  Map<String, String> _danceTitles = const {};
  Map<String, Dance> _dances = const {};
  CollectionData? _collectionData;
  bool _loading = true;
  Object? _error;

  /// Shared renderer for the large-print Perform view (mirrors
  /// [ProgramEditorScreen]'s `_performRenderer`).
  static final FigureRenderer _performRenderer = FigureRenderer(contraTaxonomy);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      widget.refreshTrigger.addListener(_onRefresh);
      _load();
    }
  }

  void _onRefresh() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    widget.refreshTrigger.removeListener(_onRefresh);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final program = await _repos.programs.getById(widget.programId);
      if (program == null) {
        if (!mounted) return;
        setState(() {
          _program = null;
          _danceTitles = const {};
          _dances = const {};
          _collectionData = null;
          _loading = false;
          _error = null;
        });
        return;
      }
      final data = await CollectionData.load(_repos);
      final dances = <String, Dance>{};
      if (program != null) {
        final ids = {
          for (final s in program.slots)
            if (s.danceId != null) s.danceId!,
        };
        final loaded = await Future.wait(ids.map(_repos.dances.getById));
        for (final dance in loaded) {
          if (dance != null) {
            titles[dance.id] = dance.title;
            dances[dance.id] = dance;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _program = program;
        _danceTitles = titles;
        _dances = dances;
        _collectionData = data;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _duplicate() async {
    final source = _program;
    if (source == null) return;
    final now = DateTime.now().toUtc();
    final copy = await _repos.programs.duplicate(
      id: source.id,
      newId: uuidV4(),
      newSlotId: uuidV4,
      now: now,
      newTitle: '${source.title} (copy)',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Duplicated as "${copy.title}".')));
    widget.onNavigateTo(copy.id);
  }

  Future<void> _delete() async {
    final source = _program;
    if (source == null) return;
    await _repos.programs.softDelete(source.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${source.title}" deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              _repos.programs.restore(source.id, at: DateTime.now().toUtc()),
        ),
      ),
    );
    widget.onDeleted();
  }

  /// Launches the large-print Perform view for the current saved program,
  /// mirroring [ProgramEditorScreen]'s perform launch. No-op when there is
  /// nothing to perform or the reference data has not finished loading.
  void _performProgram() {
    final program = _program;
    final data = _collectionData;
    if (program == null || data == null || program.slots.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PerformProgramScreen(
          program: program,
          data: data,
          renderer: _performRenderer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
      floatingActionButton: (_program != null)
          ? FloatingActionButton.extended(
              key: const ValueKey('open-builder'),
              heroTag: 'open-builder',
              onPressed: widget.onOpenBuilder,
              icon: const Icon(Icons.edit_note),
              label: const Text('Open builder'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading program'),
      );
    }
    final program = _program;
    if (_error != null || program == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('This program is no longer available.'),
        ),
      );
    }

    final theme = Theme.of(context);
    final slotCount = program.slots.length;
    final dateLabel = program.eventDate == null
        ? null
        : MaterialLocalizations.of(
            context,
          ).formatMediumDate(program.eventDate!);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(program.title, style: theme.textTheme.headlineSmall),
            ),
            IconButton(
              key: const ValueKey('summary-duplicate'),
              tooltip: 'Duplicate',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _duplicate,
            ),
            ProgramExportMenu(
              program: program,
              titleFor: (id) => _danceTitles[id],
            ),
            IconButton(
              key: const ValueKey('summary-delete'),
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ProgramStatusChip(status: program.status),
        const SizedBox(height: 16),
        _buildPerformAction(program),
        const SizedBox(height: 8),
        if (dateLabel != null) _summaryRow(Icons.event_outlined, dateLabel),
        if (program.venue != null)
          _summaryRow(Icons.place_outlined, program.venue!),
        if (program.band != null)
          _summaryRow(Icons.music_note_outlined, 'Band: ${program.band}'),
        if (program.caller != null)
          _summaryRow(Icons.campaign_outlined, 'Caller: ${program.caller}'),
        if (program.dancerLevel != null)
          _summaryRow(Icons.groups_outlined, 'Level: ${program.dancerLevel}'),
        if (program.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Notes', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(program.notes),
        ],
        const SizedBox(height: 24),
        Text('Set list ($slotCount)', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        ..._buildSetList(program),
        const SizedBox(height: 80),
      ],
    );
  }

  /// Prominent "Perform this program" action shown at the top of the summary.
  /// Disabled (with an explanatory tooltip) when the program has no slots or the
  /// reference data has not loaded yet, mirroring the editor's `_slots.isEmpty`
  /// guard — never a dead button. The disabled state is exposed to assistive
  /// technology via the button's own disabled semantics, not colour alone.
  Widget _buildPerformAction(Program program) {
    final canPerform = program.slots.isNotEmpty && _collectionData != null;
    final button = FilledButton.icon(
      key: const ValueKey('summary-perform'),
      onPressed: canPerform ? _performProgram : null,
      icon: const Icon(Icons.slideshow),
      label: const Text('Perform this program'),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: canPerform
          ? button
          : Tooltip(
              message: 'Add at least one slot to perform this program',
              child: button,
            ),
    );
  }

  /// Builds the read-only, ordered set list. Primaries are numbered 1..n and
  /// ALT alternates render indented beneath their primary with an icon + text
  /// label (never colour alone), per `docs/design/ux.md` §4. Dance rows are
  /// tappable and open [DanceDetailScreen]; free-text slots are plain,
  /// non-interactive text. Editing/reordering stays behind the builder FAB.
  List<Widget> _buildSetList(Program program) {
    if (program.slots.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'No slots yet — open the builder to add dances.',
            key: const ValueKey('summary-set-list-empty'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }

    final rows = <Widget>[];
    var ordinal = 0;
    for (final group in program.grouped) {
      ordinal++;
      rows.add(_slotRow(group.primary, ordinalLabel: '$ordinal'));
      for (final alt in group.alternates) {
        rows.add(_slotRow(alt, ordinalLabel: null, indented: true));
      }
    }
    return rows;
  }

  Widget _slotRow(
    ProgramSlot slot, {
    required String? ordinalLabel,
    bool indented = false,
  }) {
    final theme = Theme.of(context);
    final danceId = slot.danceId;

    Widget leading = SizedBox(
      width: 28,
      child: Text(
        ordinalLabel ?? '',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    // Secondary metadata line (guest caller / planned minutes), shared by all
    // slot types when present. Trimmed for display, matching the builder UI.
    final extras = <String>[
      if (slot.guestCaller != null && slot.guestCaller!.trim().isNotEmpty)
        'Guest: ${slot.guestCaller!.trim()}',
      if (slot.plannedMinutes != null) '${slot.plannedMinutes} min',
    ];

    final altBadge = slot.isAlt
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.subdirectory_arrow_right,
                size: 16,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 2),
              Text(
                'Alt',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
            ],
          )
        : null;

    if (danceId != null) {
      final dance = _dances[danceId];
      final title = dance?.title ?? _danceTitles[danceId];
      if (title == null) {
        // The dance no longer resolves (deleted/tombstoned). Render a graceful,
        // non-interactive fallback rather than a broken tappable row.
        return Padding(
          padding: EdgeInsets.only(left: indented ? 32 : 0, top: 4, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              Icon(
                Icons.report_gmailerrorred_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ?altBadge,
                    Text(
                      'Dance unavailable',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      final secondaryParts = <String>[
        if (dance != null) formationLabel(dance.formation),
        if (dance?.level != null) danceLevelLabel(dance!.level!),
        // A dance slot may also carry a per-slot caller note (per ProgramSlot
        // docs); surface it like the builder UI does.
        if (slot.text != null && slot.text!.trim().isNotEmpty)
          'Note: ${slot.text!.trim()}',
        ...extras,
      ];
      final secondary = secondaryParts.join(' · ');

      return Padding(
        padding: EdgeInsets.only(left: indented ? 32 : 0, top: 2, bottom: 2),
        child: MergeSemantics(
          child: Semantics(
            button: true,
            label: slot.isAlt ? 'Alternate: $title' : title,
            child: InkWell(
              key: ValueKey('summary-slot-${slot.id}'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DanceDetailScreen(danceId: danceId),
                ),
              ),
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      leading,
                      Icon(
                        Icons.music_note_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ?altBadge,
                            Text(title, style: theme.textTheme.bodyLarge),
                            if (secondary.isNotEmpty)
                              Text(
                                secondary,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Free-text slot (break / waltz / announcement): non-interactive text.
    final text = (slot.text ?? '').trim();
    return Padding(
      padding: EdgeInsets.only(left: indented ? 32 : 0, top: 6, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          Icon(
            Icons.notes_outlined,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?altBadge,
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (extras.isNotEmpty)
                  Text(
                    extras.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _EmptyEditorPane extends StatelessWidget {
  const _EmptyEditorPane();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Select a program',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a program from the list, or create a new one.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
