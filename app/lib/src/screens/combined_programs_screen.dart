import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/canonical_discouraged_terms_scope.dart';
import '../data/date_format_scope.dart';
import '../data/matrix_collision_mode_scope.dart';
import '../data/matrix_column_dialect.dart';
import '../data/program_matrix_column_config_scope.dart';
import '../data/regional_formats.dart';
import '../data/repositories_scope.dart';
import '../data/user_figures_scope.dart';
import '../diagnostics/error_log.dart';
import '../export/export_labels_l10n.dart';
import '../export/program_matrix_pdf.dart';
import '../search/facet_labels.dart' show formationDisplayLabel;
import '../theme/app_spacing.dart';
import '../utils/safe_name.dart';
import '../utils/slot_dance_title.dart';
import '../widgets/empty_state.dart';
import '../widgets/export_guard.dart';
import '../widgets/load_error_view.dart';
import '../widgets/program_export_menu.dart' show PdfLayouter;
import '../widgets/program_matrix_table.dart';

/// The combined view of several programs (#2349, Settings ▸ Experimental ▸
/// Weekends and series): one matrix over every dance of [programIds], each
/// program a labelled block, and the dances repeated across them.
///
/// Nothing here is stored. The view is worked out from the programs as they
/// are when it opens, and again whenever one of them changes; leaving it
/// forgets it. A program deleted while it is open drops out of the view.
class CombinedProgramsScreen extends StatefulWidget {
  const CombinedProgramsScreen({
    super.key,
    required this.programIds,
    this.pdfLayouter,
  });

  /// The programs to combine. Their order does not matter: the view orders
  /// them by event date ([orderProgramsForSeries]).
  final Set<String> programIds;

  /// Print/share seam for the matrix PDF; defaults to [Printing.layoutPdf].
  final PdfLayouter? pdfLayouter;

  @override
  State<CombinedProgramsScreen> createState() => _CombinedProgramsScreenState();
}

/// Renders formation labels only (the matrix's formation column, on screen
/// and in the PDF); the matrix never shows a dance's figure lines.
final FigureRenderer _formationRenderer = FigureRenderer(
  shippedTaxonomies.anyForm,
);

typedef _Snapshot = ({
  List<Program> programs,
  Map<String, Dance> dancesById,
  Map<String, String> authorNames,
});

class _CombinedProgramsScreenState extends State<CombinedProgramsScreen> {
  StreamSubscription<_Snapshot>? _sub;
  _Snapshot? _snapshot;
  Object? _loadError;

  /// The view settings a program's own Matrix tab has, kept for this view
  /// only: hidden columns, alternates shown, phrase labels shown.
  final Set<String> _hiddenColumns = {};
  bool _showAlternates = true;
  bool _showPhrases = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub == null && _loadError == null) _subscribe();
  }

  void _subscribe() {
    final repos = RepositoriesScope.of(context);
    _sub = repos.programs
        .watchAll()
        .map(
          (all) => [
            for (final p in all)
              if (widget.programIds.contains(p.id)) p,
          ],
        )
        // A write to a program that is not selected changes nothing here.
        .distinct(_samePrograms)
        .asyncMap((programs) => _load(repos, programs))
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              _snapshot = snapshot;
              _loadError = null;
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            logCaughtError(
              error,
              stackTrace,
              source: 'combined_programs_screen._subscribe',
            );
            if (!mounted) return;
            setState(() => _loadError = error);
          },
        );
  }

  /// Whether two emits hold the same selected programs, unchanged
  /// ([Program]'s value equality, its slots included).
  static bool _samePrograms(List<Program> a, List<Program> b) =>
      listEquals(a, b);

  Future<_Snapshot> _load(
    CompendiumRepositories repos,
    List<Program> programs,
  ) async {
    final danceIds = {
      for (final p in programs)
        for (final slot in p.slots) ?slot.danceId,
    };
    // A dance in Recently deleted keeps its row, marked as deleted, as on a
    // program's own matrix.
    final dances = await repos.dances.getByIds(danceIds, includeDeleted: true);
    final authorIds = {for (final d in dances) ...d.authorIds};
    final authors = await Future.wait(
      authorIds.map(repos.choreographers.getById),
    );
    return (
      programs: programs,
      dancesById: {for (final d in dances) d.id: d},
      authorNames: {
        for (final c in authors)
          if (c != null) c.id: c.name,
      },
    );
  }

  void _retry() {
    unawaited(_sub?.cancel());
    setState(() {
      _sub = null;
      _loadError = null;
      _snapshot = null;
    });
    _subscribe();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.programsCombinedView),
          bottom: TabBar(
            tabs: [
              Tab(
                key: const ValueKey('combined-tab-matrix'),
                text: l10n.programsMatrixTab,
              ),
              Tab(
                key: const ValueKey('combined-tab-repeats'),
                text: l10n.programsCombinedRepeatsTab,
              ),
            ],
          ),
        ),
        body: _buildBody(l10n),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loadError != null) {
      return LoadErrorView(
        icon: LoadErrorView.errorGlyph(context),
        message: l10n.programsCombinedLoadError,
        onRetry: _retry,
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return Center(
        child: CircularProgressIndicator(semanticsLabel: l10n.programsLoading),
      );
    }
    if (snapshot.programs.isEmpty) {
      return EmptyState(
        key: const ValueKey('combined-programs-gone'),
        icon: EmptyState.glyph(context, Icons.event_busy_outlined),
        title: l10n.programsCombinedGoneTitle,
        body: l10n.programsCombinedGoneBody,
      );
    }
    final input = combineProgramsForMatrix(
      snapshot.programs,
      resolveDance: (id) => _rowDance(l10n, snapshot, id),
    );
    final blockLabels = [
      for (final p in input.programs) _programLabel(l10n, p),
    ];
    return TabBarView(
      children: [
        _buildMatrixTab(l10n, snapshot, input, blockLabels),
        _buildRepeatsTab(l10n, snapshot, input, blockLabels),
      ],
    );
  }

  /// The dance a row shows: the dance, marked as deleted when it is in
  /// Recently deleted, or a stand-in when it is gone, as a program's own
  /// matrix shows them.
  Dance _rowDance(AppLocalizations l10n, _Snapshot snapshot, String id) {
    final dance = snapshot.dancesById[id];
    if (dance == null) {
      final now = DateTime.now();
      return Dance(
        id: id,
        title: l10n.programsDeletedDanceFallback,
        createdAt: now,
        updatedAt: now,
      );
    }
    return dance.isDeleted
        ? dance.copyWith(title: slotDanceTitle(l10n, dance, markDeleted: true))
        : dance;
  }

  /// A program's block heading: its title and, when it has one, its date.
  String _programLabel(AppLocalizations l10n, Program program) {
    final title = program.title.trim().isEmpty
        ? l10n.exportMatrixDefaultTitle
        : program.title.trim();
    final date = program.eventDate;
    if (date == null) return title;
    return l10n.programsCombinedBlockLabel(
      title,
      formatEventDate(
        date,
        DateFormatScope.of(context),
        MaterialLocalizations.of(context),
        l10n,
      ),
    );
  }

  ProgramMatrix _matrix(CombinedProgramMatrixInput input) => buildProgramMatrix(
    input.dances,
    taxonomy: shippedTaxonomies.anyForm,
    sections: input.sections,
    alternateGroups: input.alternateGroups,
    collisionMode: MatrixCollisionModeScope.of(context)
        ? MatrixCollisionMode.exactBeats
        : MatrixCollisionMode.phrase,
    config: ProgramMatrixColumnConfigScope.of(context),
    userFigures: UserFiguresScope.shownCatalogOf(context),
  );

  /// Each column's dialect and each row's, as a program's own Matrix tab
  /// works them out, over every dance of the set.
  ({Map<String, Dialect> columns, Map<String, Dialect> rows}) _dialects(
    ProgramMatrix matrix,
    _Snapshot snapshot,
  ) {
    final dialects = _activeDialects();
    final fallback = dialects.forForm(DanceForm.contra);
    final userFigures = UserFiguresScope.shownCatalogOf(context);
    DanceForm? formOf(String id) => snapshot.dancesById[id]?.form;
    return (
      columns: {
        for (final column in matrix.columns)
          column.moveId: matrixColumnDialect(
            column,
            dialects: dialects,
            fallback: fallback,
            userFigure: (id) => userFigures[id],
            usedBy: () => {
              for (final row in matrix.rows)
                if (row.contains(column)) formOf(row.danceId),
            },
            program: () => {for (final row in matrix.rows) formOf(row.danceId)},
          ),
      },
      rows: {
        for (final row in matrix.rows)
          row.danceId: switch (snapshot.dancesById[row.danceId]) {
            final dance? => dialectForDance(
              dialects.forDance(dance),
              title: dance.title,
              authorNames: [
                for (final id in dance.authorIds) ?snapshot.authorNames[id],
              ],
            ),
            null => fallback,
          },
      },
    );
  }

  Widget _buildMatrixTab(
    AppLocalizations l10n,
    _Snapshot snapshot,
    CombinedProgramMatrixInput input,
    List<String> blockLabels,
  ) {
    final matrix = _matrix(input);
    final dialects = _dialects(matrix, snapshot);
    final fallback = _activeDialects().forForm(DanceForm.contra);
    final canonicalize = CanonicalDiscouragedTermsScope.of(context);
    String formationOf(MatrixRow row) => formationDisplayLabel(
      l10n,
      row.formation,
      _formationRenderer,
      dialects.rows[row.danceId] ?? fallback,
      canonicalizeDiscouragedTerms: canonicalize,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.xs,
            0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                key: const ValueKey('combined-matrix-toggle-alternates'),
                isSelected: _showAlternates,
                icon: const Icon(Icons.straight),
                selectedIcon: const Icon(Icons.alt_route),
                tooltip: _showAlternates
                    ? l10n.programsMatrixHideAlternatesSemantic
                    : l10n.programsMatrixShowAlternatesSemantic,
                onPressed: () =>
                    setState(() => _showAlternates = !_showAlternates),
              ),
              IconButton(
                key: const ValueKey('combined-matrix-toggle-phrases'),
                isSelected: _showPhrases,
                icon: const Icon(Icons.category_outlined),
                selectedIcon: const Icon(Icons.text_fields),
                tooltip: _showPhrases
                    ? l10n.programsMatrixHidePhrasesSemantic
                    : l10n.programsMatrixShowPhrasesSemantic,
                onPressed: () => setState(() => _showPhrases = !_showPhrases),
              ),
              IconButton(
                key: const ValueKey('combined-matrix-reset-hidden-columns'),
                icon: const Icon(Icons.visibility),
                tooltip: l10n.programsMatrixShowAllColumnsSemantic,
                onPressed:
                    matrix.columns.any((c) => _hiddenColumns.contains(c.moveId))
                    ? () => setState(_hiddenColumns.clear)
                    : null,
              ),
              IconButton(
                key: const ValueKey('combined-matrix-export-pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: l10n.exportMatrixPdfTooltip,
                onPressed: matrix.isEmpty
                    ? null
                    : () => _exportPdf(
                        matrix,
                        input,
                        blockLabels,
                        dialects,
                        fallback,
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ProgramMatrixTable(
            key: const ValueKey('combined-matrix-table'),
            matrix: matrix,
            taxonomy: shippedTaxonomies.anyForm,
            dialect: fallback,
            config: ProgramMatrixColumnConfigScope.of(context),
            omittedFreeTextCount: input.omittedFreeTextCount,
            altRowIndices: input.altRowIndices,
            showAlternates: _showAlternates,
            showPhrases: _showPhrases,
            hiddenColumns: _hiddenColumns,
            onHideColumn: (id) => setState(() => _hiddenColumns.add(id)),
            dialectForColumn: (column) =>
                dialects.columns[column.moveId] ?? fallback,
            formationLabelBuilder: formationOf,
            rowBlocks: input.programIndexByRow,
            blockLabels: blockLabels,
          ),
        ),
      ],
    );
  }

  /// The dialect of each dance form, or the defaults with no
  /// [ActiveDialectScope] (narrow tests).
  DialectsByForm _activeDialects() {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ActiveDialectScope>();
    return scope == null
        ? DialectsByForm.defaults
        : ActiveDialectScope.of(context);
  }

  /// Prints the combined matrix with its program blocks. As on a program's
  /// own matrix, every column prints, hidden on screen or not, and so does
  /// every alternate.
  Future<void> _exportPdf(
    ProgramMatrix matrix,
    CombinedProgramMatrixInput input,
    List<String> blockLabels,
    ({Map<String, Dialect> columns, Map<String, Dialect> rows}) dialects,
    Dialect fallback,
  ) async {
    // Resolve every context-dependent value before the layouter runs: its
    // callback can run after further awaits, or more than once.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final canonicalize = CanonicalDiscouragedTermsScope.of(context);
    final config = ProgramMatrixColumnConfigScope.of(context);
    final title = l10n.programsCombinedPdfTitle;
    final layoutPdf = widget.pdfLayouter ?? Printing.layoutPdf;
    await guardExport(
      messenger,
      l10n.exportSetListError,
      () => layoutPdf(
        name: programPdfJobName(title, fallback: l10n.exportMatrixPdfFilename),
        onLayout: (format) => buildProgramMatrixPdf(
          matrix,
          taxonomy: shippedTaxonomies.anyForm,
          dialect: fallback,
          programTitle: title,
          omittedFreeTextCount: input.omittedFreeTextCount,
          labels: programMatrixExportLabels(l10n),
          dialectForColumn: (column) =>
              dialects.columns[column.moveId] ?? fallback,
          formatFormation: (row) => formationDisplayLabel(
            l10n,
            row.formation,
            _formationRenderer,
            dialects.rows[row.danceId] ?? fallback,
            canonicalizeDiscouragedTerms: canonicalize,
          ),
          config: config,
          pageFormat: format,
          rowBlocks: input.programIndexByRow,
          blockLabels: blockLabels,
        ),
      ),
      source: 'combined_programs_screen._exportPdf',
    );
  }

  Widget _buildRepeatsTab(
    AppLocalizations l10n,
    _Snapshot snapshot,
    CombinedProgramMatrixInput input,
    List<String> blockLabels,
  ) {
    final repeats = findRepeatedDances(input.programs);
    if (repeats.isEmpty) {
      return EmptyState(
        key: const ValueKey('combined-repeats-empty'),
        icon: EmptyState.glyph(context, Icons.check_circle_outline),
        title: l10n.programsCombinedRepeatsEmptyTitle,
        body: l10n.programsCombinedRepeatsEmptyBody,
      );
    }
    final theme = Theme.of(context);
    return ListView.separated(
      key: const ValueKey('combined-repeats-list'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: repeats.length + 1,
      separatorBuilder: (_, i) =>
          i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.programsCombinedRepeatsCount(repeats.length),
                style: theme.textTheme.bodySmall,
              ),
            ),
          );
        }
        final repeat = repeats[i - 1];
        final title = _rowDance(l10n, snapshot, repeat.danceId).title;
        return ListTile(
          key: ValueKey('combined-repeat-${repeat.danceId}'),
          title: Text(title, style: theme.textTheme.titleMedium),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n.programsCombinedRepeatProgramCount(
                      repeat.programCount,
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (repeat.isAlternateSomewhere)
                    Chip(
                      key: ValueKey(
                        'combined-repeat-alternate-${repeat.danceId}',
                      ),
                      avatar: const Icon(Icons.alt_route, size: 16),
                      label: Text(
                        repeat.isOnlyAlternate
                            ? l10n.programsCombinedRepeatAlternateEverywhereChip
                            : l10n.programsCombinedRepeatAlternateChip,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              for (final use in repeat.uses)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        use.isAlternate
                            ? Icons.alt_route
                            : Icons.event_note_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          l10n.programsCombinedRepeatUse(
                            blockLabels[use.programIndex],
                            _positionLabel(l10n, use),
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          isThreeLine: true,
        );
      },
    );
  }

  String _positionLabel(AppLocalizations l10n, RepeatedDanceUse use) {
    final number = use.danceNumber;
    if (!use.isAlternate) {
      return l10n.programsCombinedPositionDance(number ?? 0);
    }
    return number == null
        ? l10n.programsCombinedPositionAlternate
        : l10n.programsCombinedPositionAlternateFor(number);
  }
}
