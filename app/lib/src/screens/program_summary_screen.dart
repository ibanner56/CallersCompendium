import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../data/date_format_scope.dart';
import '../data/regional_formats.dart';
import '../data/repositories_scope.dart';
import '../data/app_theme_scope.dart';
import '../data/set_list_color_coding_scope.dart';
import '../models/dance_list_entry.dart';
import '../search/collection_data.dart';
import '../search/facet_labels.dart';
import '../theme/set_list_accents.dart';
import '../utils/confirm_delete.dart';
import '../widgets/program_export_menu.dart';
import '../widgets/program_status_chip.dart';
import 'dance_detail_screen.dart';
import 'perform_program_screen.dart';
import 'program_editor_screen.dart';

/// Full-screen, read-focused summary of a saved program, pushed on **narrow**
/// (phone / tablet-portrait) layouts when the user taps a program in the
/// programs list.
///
/// Mirrors the dance side's [DanceDetailScreen]: tapping a saved item opens a
/// **read view** — a Perform-first summary with a prominent "Perform this
/// program" action and an "Edit program" action — instead of dropping the
/// caller straight into the full-screen builder. Reuses the exact same
/// [ProgramSummaryPane] content the wide split-pane detail renders, so the two
/// layouts stay consistent.
///
/// The programs list reloads unconditionally when this route pops, so the
/// screen only self-manages what it must: **Edit** opens the builder (reloading
/// in place, or popping if the builder deleted the program), **Delete** pops
/// back to the list, and **Duplicate** re-targets this screen at the new copy.
class ProgramSummaryScreen extends StatefulWidget {
  const ProgramSummaryScreen({super.key, required this.programId});

  final String programId;

  @override
  State<ProgramSummaryScreen> createState() => _ProgramSummaryScreenState();
}

class _ProgramSummaryScreenState extends State<ProgramSummaryScreen> {
  /// Reloads the reused [ProgramSummaryPane] in place after an edit that keeps
  /// the same program id. A duplicate instead re-targets [_programId], which
  /// re-keys and rebuilds the pane, so it reloads without a tick.
  final _refresh = ValueNotifier<int>(0);
  late String _programId = widget.programId;

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _openBuilder() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ProgramEditorScreen(programId: _programId),
      ),
    );
    if (!mounted) return;
    if (result == 'deleted') {
      // The builder deleted the program; leave the summary and return to the
      // list (which reloads and drops the stale row).
      Navigator.of(context).pop();
    } else if (result != null) {
      // The builder saved edits under the same id; reload the summary in place.
      _refresh.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProgramSummaryPane(
      // Keyed on the program id so the pane fully resets (fresh load) when a
      // duplicate re-targets this screen.
      key: ValueKey('summary-screen-$_programId'),
      programId: _programId,
      refreshTrigger: _refresh,
      showAppBar: true,
      prominentPerform: true,
      onOpenBuilder: _openBuilder,
      onDeleted: () => Navigator.of(context).pop(),
      onNavigateTo: (id) => setState(() => _programId = id),
    );
  }
}

/// Read-only summary of the selected program shown in the wide detail pane. The
/// heavy building work happens in the full-screen [ProgramEditorScreen] route
/// launched by [onOpenBuilder]; this pane keeps quick duplicate/delete actions.
class ProgramSummaryPane extends StatefulWidget {
  const ProgramSummaryPane({
    super.key,
    required this.programId,
    required this.refreshTrigger,
    required this.onOpenBuilder,
    required this.onDeleted,
    required this.onNavigateTo,
    this.onProgramMutated,
    this.showAppBar = false,
    this.prominentPerform = false,
  });

  final String programId;
  final ValueListenable<int> refreshTrigger;
  final VoidCallback onOpenBuilder;
  final VoidCallback onDeleted;
  final void Function(String id) onNavigateTo;

  /// Called after an **in-place** mutation that keeps this pane on the same
  /// program — "Mark all performed" and in-event Perform adjustments (which can
  /// change slot count, mark slots performed, and bump `updatedAt`). The wide
  /// split-pane wires this to bump its shared list refresh so the coexisting
  /// program list reflects the change without a manual reload. The narrow
  /// [ProgramSummaryScreen] leaves it unset: its list reloads unconditionally
  /// when the summary route pops, so there is nothing to signal. Duplicate and
  /// delete are handled separately via [onNavigateTo] / [onDeleted].
  final VoidCallback? onProgramMutated;

  /// Wraps the pane in a [Scaffold] [AppBar] (back button + generic title) when
  /// pushed as a full-screen route on narrow layouts. The wide detail pane
  /// leaves this `false` — its title lives in the body, not an app bar.
  final bool showAppBar;

  /// Renders a prominent full-width "Perform this program" button (Perform-first)
  /// in place of the compact perform icon button, for the narrow read view.
  final bool prominentPerform;

  @override
  State<ProgramSummaryPane> createState() => _ProgramSummaryPaneState();
}

class _ProgramSummaryPaneState extends State<ProgramSummaryPane> {
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
      final titles = <String, String>{};
      final dances = <String, Dance>{};
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
    // ROADMAP G.7: optional confirm dialog before the (still-undoable) delete.
    if (!await confirmDeleteIfEnabled(context, itemLabel: source.title)) return;
    if (!mounted) return;
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
          // This is the real in-event path: the program is saved, so in-event
          // adjustments (`docs/design/ux.md` §5) persist immediately via the
          // repository (bumping `updatedAt`, and possibly the slot count) and
          // the summary reloads to reflect them. On the wide split-pane
          // [onProgramMutated] also refreshes the coexisting program list so
          // its slot count / ordering do not go stale.
          onProgramChanged: (updated) async {
            await _repos.programs.update(updated);
            if (!mounted) return;
            _load();
            widget.onProgramMutated?.call();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('Program')) : null,
      body: _buildBody(),
      floatingActionButton: (_program != null)
          ? FloatingActionButton.extended(
              key: const ValueKey('open-builder'),
              heroTag: 'open-builder',
              onPressed: widget.onOpenBuilder,
              icon: const Icon(Icons.edit_note),
              label: const Text('Edit program'),
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
        : formatEventDate(
            program.eventDate!,
            DateFormatScope.of(context),
            MaterialLocalizations.of(context),
          );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(program.title, style: theme.textTheme.headlineSmall),
            ),
            if (!widget.prominentPerform) _buildPerformAction(program),
            ProgramExportMenu(
              program: program,
              titleFor: (id) => _danceTitles[id],
              danceFor: (id) => _dances[id],
            ),
            if (program.slots.any((s) => s.danceId != null))
              IconButton(
                key: const ValueKey('mark-all-performed'),
                tooltip: 'Mark all performed',
                icon: const Icon(Icons.done_all),
                onPressed: _markAllPerformed,
              ),
            IconButton(
              key: const ValueKey('summary-duplicate'),
              tooltip: 'Duplicate',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _duplicate,
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
        if (widget.prominentPerform) ...[
          const SizedBox(height: 16),
          _buildProminentPerform(program),
        ],
        const SizedBox(height: 16),
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

  /// "Perform this program" action shown in the summary's top action Row,
  /// mirroring the program builder's `perform-program` AppBar action. Disabled
  /// (with an explanatory tooltip) when the program has no slots or the
  /// reference data has not loaded yet, mirroring the editor's `_slots.isEmpty`
  /// guard — never a dead button. The disabled state is exposed to assistive
  /// technology via the button's own disabled semantics, not colour alone.
  Widget _buildPerformAction(Program program) {
    final canPerform = program.slots.isNotEmpty && _collectionData != null;
    return IconButton(
      key: const ValueKey('summary-perform'),
      tooltip: canPerform
          ? 'Perform this program'
          : 'Add at least one slot to perform this program',
      icon: const Icon(Icons.slideshow),
      onPressed: canPerform ? _performProgram : null,
    );
  }

  /// Prominent, full-width "Perform this program" button for the narrow
  /// read-focused summary — the Perform-first primary action a caller reaches
  /// for at a gig. Shares the [ValueKey]`('summary-perform')` and disabled-state
  /// semantics of [_buildPerformAction] (only one is ever in the tree at a
  /// time), so the same dead-button guard and tooltip apply: disabled (never
  /// absent-and-tappable) with an explanatory tooltip when the program has no
  /// slots or the reference data has not loaded yet.
  Widget _buildProminentPerform(Program program) {
    final canPerform = program.slots.isNotEmpty && _collectionData != null;
    return Tooltip(
      message: canPerform
          ? 'Perform this program'
          : 'Add at least one slot to perform this program',
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('summary-perform'),
          onPressed: canPerform ? _performProgram : null,
          icon: const Icon(Icons.slideshow),
          label: const Text('Perform this program'),
        ),
      ),
    );
  }

  /// Marks every slot with a dance as performed (now), persists the change, and
  /// reloads the summary. Mirrors [ProgramEditorScreen]'s `_markAllPerformed`
  /// (no confirm dialog), but writes through the repository immediately because
  /// the summary shows a saved program — there is no draft to fold into a later
  /// save. Only reachable when at least one slot has a dance, matching the
  /// builder's guard.
  Future<void> _markAllPerformed() async {
    final program = _program;
    if (program == null) return;
    final now = DateTime.now().toUtc();
    final updated = program.copyWith(
      slots: [
        for (final s in program.slots)
          s.danceId != null && s.performedAt == null
              ? s.copyWith(performedAt: now)
              : s,
      ],
      updatedAt: now,
    );
    await _repos.programs.update(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked all dances performed.')),
    );
    _load();
    // On the wide split-pane, refresh the coexisting list too (this bumps
    // `updatedAt`, affecting the "recently updated" sort order).
    widget.onProgramMutated?.call();
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
    for (final group in program.outputGrouped) {
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
    // Colour-code accent (issue #270): a *redundant* cue paired with the
    // formation text below. Suppressed when the user disables it. High contrast
    // is either the app's high-contrast theme or the OS setting, in which case
    // we use the brighter high-contrast palette.
    final colorCodingEnabled = SetListColorCodingScope.of(context);
    final highContrast =
        (AppThemeScope.maybeOf(context)?.isHighContrast ?? false) ||
        MediaQuery.highContrastOf(context);

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

      // Resolve the redundant formation accent (issue #270). Only when a dance
      // resolves, color-coding is on, and the family has a themed accent.
      final accent = (dance != null && colorCodingEnabled)
          ? setListAccentForShape(
              dance.formation.shape,
              highContrast: highContrast,
            )
          : null;
      // Expose the formation as text to AT so the row is fully readable without
      // colour (ux.md §4): the accent is never the sole carrier of type/form.
      final semanticsLabel = [
        slot.isAlt ? 'Alternate: $title' : title,
        if (dance != null) formationLabel(dance.formation),
      ].join('. ');

      return Padding(
        padding: EdgeInsets.only(left: indented ? 32 : 0, top: 2, bottom: 2),
        child: MergeSemantics(
          child: Semantics(
            button: true,
            label: semanticsLabel,
            child: InkWell(
              key: ValueKey('summary-slot-${slot.id}'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DanceDetailScreen(danceId: danceId),
                ),
              ),
              child: ExcludeSemantics(
                child: Container(
                  key: accent != null
                      ? ValueKey('summary-slot-${slot.id}-accent')
                      : null,
                  decoration: accent != null
                      ? BoxDecoration(
                          border: Border(
                            left: BorderSide(color: accent, width: 4),
                          ),
                        )
                      : null,
                  padding: EdgeInsets.only(
                    left: accent != null ? 8 : 0,
                    top: 8,
                    bottom: 8,
                  ),
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
