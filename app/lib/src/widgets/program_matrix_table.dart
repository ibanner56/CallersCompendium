import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Read-only **programming matrix** (moves × dances) for the Program builder's
/// Matrix tab (`docs/design/ux.md` §4).
///
/// Columns are the moves actually present across the program's dances (derived
/// by [buildProgramMatrix] — no manual checklist, CC's failure mode). Each cell
/// shows whether a dance uses that move. Two highlights are overlaid: the
/// **program debut** (★ — the first dance, in program order, to use a move) and
/// the **dance's first figure** (flag — the move each dance opens with). Both,
/// and presence, are conveyed with an **icon + text/semantics, never colour
/// alone** (WCAG 1.4.1).
///
/// Layout: a four-quadrant grid (corner / pinned column headers / pinned row
/// headers / scrolling body) with the row- and column-header scroll positions
/// mirrored to the body via linked [ScrollController]s, so both headers stay
/// pinned while the body scrolls in both directions. The grid is exposed as a
/// semantic table: header cells are flagged headers and every data cell
/// announces `<dance>, <move>: present/not present[, introduced here]`
/// `[, dance's first figure]`.
class ProgramMatrixTable extends StatefulWidget {
  const ProgramMatrixTable({
    super.key,
    required this.matrix,
    required this.taxonomy,
    required this.dialect,
    this.omittedFreeTextCount = 0,
    this.altDanceIds = const {},
  });

  final ProgramMatrix matrix;
  final Taxonomy taxonomy;
  final Dialect dialect;

  /// Number of free-text slots omitted from the matrix (shown as a caption so
  /// the omission is explicit).
  final int omittedFreeTextCount;

  /// Dance ids whose row is an alternate slot (badged "ALT").
  final Set<String> altDanceIds;

  static const double columnWidth = 64;
  static const double rowHeight = 48;
  static const double rowHeaderWidth = 168;
  static const double columnHeaderHeight = 72;

  /// Width (logical pixels) below which the wide scrolling grid is replaced by
  /// the [_CompactMatrix] fallback. 600 mirrors Material 3's compact
  /// window-size-class cutoff (matching `DanceDetailScreen.compactActionsBreakpoint`),
  /// so phones get the condensed view while tablets/desktop keep the full grid.
  ///
  /// At a 360dp phone width the grid reserves [rowHeaderWidth] (168) for the
  /// pinned dance column, leaving room for only ~3 [columnWidth] move columns —
  /// too few to read the core insight (which moves repeat across the set)
  /// without horizontally scrolling the whole grid. The compact view surfaces
  /// that insight directly, grouped by move.
  static const double compactBreakpoint = 600;

  @override
  State<ProgramMatrixTable> createState() => _ProgramMatrixTableState();
}

class _ProgramMatrixTableState extends State<ProgramMatrixTable> {
  final _bodyH = ScrollController();
  final _bodyV = ScrollController();
  final _headerH = ScrollController();
  final _headerV = ScrollController();

  @override
  void initState() {
    super.initState();
    _bodyH.addListener(_syncH);
    _bodyV.addListener(_syncV);
    // The scroll-edge cues (#662) read `_bodyH`'s metrics to decide whether
    // more columns are off-screen, but `_bodyH` only attaches to its
    // `Scrollable` partway through the very first build — too late for that
    // same build's `AnimatedBuilder`s to see it. Force one extra rebuild
    // right after the first frame so the cues pick up accurate metrics as
    // soon as they're available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _syncH() {
    if (_headerH.hasClients && _headerH.offset != _bodyH.offset) {
      _headerH.jumpTo(_bodyH.offset);
    }
  }

  void _syncV() {
    if (_headerV.hasClients && _headerV.offset != _bodyV.offset) {
      _headerV.jumpTo(_bodyV.offset);
    }
  }

  @override
  void dispose() {
    _bodyH.dispose();
    _bodyV.dispose();
    _headerH.dispose();
    _headerV.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final matrix = widget.matrix;

    if (matrix.isEmpty) {
      return _EmptyState(omittedFreeTextCount: widget.omittedFreeTextCount);
    }

    final labels = [
      for (final c in matrix.columns)
        matrixColumnLabel(c, widget.taxonomy, widget.dialect),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < ProgramMatrixTable.compactBreakpoint;
        // The compact view drops columns no dance actually uses (e.g. the
        // always-emitted swing baseline), so its announced move count is the
        // number of columns actually shown — keeping the semantics label
        // accurate for assistive tech.
        final moveCount = compact
            ? _presentColumnCount(matrix)
            : matrix.columns.length;
        final content = compact
            ? _CompactMatrix(
                matrix: matrix,
                labels: labels,
                altDanceIds: widget.altDanceIds,
              )
            : _wideTable(labels);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Legend(),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: Semantics(
                container: true,
                label: l10n.programsMatrixSemanticLabel(
                  matrix.rows.length,
                  moveCount,
                ),
                child: content,
              ),
            ),
            if (widget.omittedFreeTextCount > 0)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  l10n.programsMatrixOmittedCaption(
                    widget.omittedFreeTextCount,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The full four-quadrant scrolling grid (corner / pinned column headers /
  /// pinned row headers / two-axis scrolling body) used at tablet and desktop
  /// widths. Below [ProgramMatrixTable.compactBreakpoint] it is replaced by
  /// [_CompactMatrix].
  Widget _wideTable(List<String> labels) {
    final matrix = widget.matrix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top strip: corner + horizontally-scrolling column headers.
        Row(
          children: [
            _Corner(),
            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: _headerH,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(
                      children: [
                        for (var c = 0; c < matrix.columns.length; c++)
                          _ColumnHeader(label: labels[c]),
                      ],
                    ),
                  ),
                  // Decorative edge cues so callers can tell there are more
                  // columns off-screen (#662) — the pinned header strip has
                  // no scrollbar of its own (it's `NeverScrollableScrollPhysics`,
                  // mirrored from the body via `_syncH`), unlike the body,
                  // which already shows a native `Scrollbar`. Purely visual:
                  // the semantic table structure (row/column `Semantics`
                  // headers) already conveys the full column set to
                  // assistive tech, so these are `ExcludeSemantics`.
                  _HeaderScrollCue(
                    controller: _bodyH,
                    alignment: Alignment.centerLeft,
                    cueKey: const ValueKey('program-matrix-header-scroll-left'),
                  ),
                  _HeaderScrollCue(
                    controller: _bodyH,
                    alignment: Alignment.centerRight,
                    cueKey: const ValueKey(
                      'program-matrix-header-scroll-right',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 1, thickness: 1),
        // Body strip: pinned row headers + two-axis scrolling cells.
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                controller: _headerV,
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  children: [
                    for (var r = 0; r < matrix.rows.length; r++)
                      _RowHeader(
                        title: matrix.rows[r].title,
                        isAlt: widget.altDanceIds.contains(
                          matrix.rows[r].danceId,
                        ),
                        half: matrix.rows[r].half,
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: Scrollbar(
                  controller: _bodyV,
                  child: SingleChildScrollView(
                    controller: _bodyV,
                    child: Scrollbar(
                      controller: _bodyH,
                      child: SingleChildScrollView(
                        key: const ValueKey('program-matrix-body-h-scroll'),
                        controller: _bodyH,
                        scrollDirection: Axis.horizontal,
                        child: Column(
                          children: [
                            for (var r = 0; r < matrix.rows.length; r++)
                              Row(
                                children: [
                                  for (
                                    var c = 0;
                                    c < matrix.columns.length;
                                    c++
                                  )
                                    _Cell(
                                      danceTitle: matrix.rows[r].title,
                                      moveLabel: labels[c],
                                      present: matrix.isPresent(r, c),
                                      first: matrix.isFirst(r, c),
                                      programDebut: matrix.isProgramDebut(r, c),
                                      collision: matrix.isPhraseCollision(r, c),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Decorative edge cue shown over the pinned column-header strip when there
/// are more columns off-screen in [alignment]'s direction (#662): a gradient
/// fade paired with a chevron, so the cue never relies on colour/opacity
/// alone (WCAG 1.4.1).
///
/// The header strip itself is `NeverScrollableScrollPhysics` — it only
/// mirrors the body's scroll offset (`_syncH`) — so [controller] is always
/// the *body*'s horizontal `ScrollController`, the single source of truth
/// for how much content is off to either side.
class _HeaderScrollCue extends StatelessWidget {
  const _HeaderScrollCue({
    required this.controller,
    required this.alignment,
    required this.cueKey,
  });

  final ScrollController controller;

  /// [Alignment.centerLeft] or [Alignment.centerRight].
  final Alignment alignment;

  /// Applied only to the visible (overflowing) subtree, so tests can assert
  /// on presence/absence directly instead of on this wrapper widget (which
  /// always exists, whether or not the cue is currently showing).
  final Key cueKey;

  static const double _width = 28;

  bool get _isLeft => alignment == Alignment.centerLeft;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final visible =
            controller.hasClients &&
            (_isLeft
                ? controller.position.extentBefore > 0.5
                : controller.position.extentAfter > 0.5);
        if (!visible) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final base = theme.colorScheme.surfaceContainerHighest;
        return Positioned(
          left: _isLeft ? 0 : null,
          right: _isLeft ? null : 0,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Container(
                key: cueKey,
                width: _width,
                alignment: alignment,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: _isLeft
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    end: _isLeft ? Alignment.centerRight : Alignment.centerLeft,
                    colors: [base, base.withValues(alpha: 0)],
                  ),
                ),
                child: Icon(
                  _isLeft ? Icons.chevron_left : Icons.chevron_right,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Corner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: ProgramMatrixTable.rowHeaderWidth,
    height: ProgramMatrixTable.columnHeaderHeight,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
  );
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      header: true,
      label: l10n.programsMatrixMoveHeaderSemantic(label),
      excludeSemantics: true,
      child: Container(
        width: ProgramMatrixTable.columnWidth,
        height: ProgramMatrixTable.columnHeaderHeight,
        alignment: Alignment.bottomCenter,
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _RowHeader extends StatelessWidget {
  const _RowHeader({required this.title, required this.isAlt, this.half});

  final String title;
  final bool isAlt;
  final ProgramHalf? half;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final halfSelect = half == null
        ? 'none'
        : (half == ProgramHalf.first ? 'first' : 'second');
    return Semantics(
      header: true,
      label: l10n.programsMatrixRowHeaderSemantic(
        title,
        isAlt ? 'yes' : 'no',
        halfSelect,
      ),
      excludeSemantics: true,
      child: Container(
        width: ProgramMatrixTable.rowHeaderWidth,
        height: ProgramMatrixTable.rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            if (isAlt) ...[
              Icon(
                Icons.alt_route,
                size: 16,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 4),
              Text(l10n.programsAltOrdinal, style: theme.textTheme.labelSmall),
              const SizedBox(width: 6),
            ],
            if (half != null) ...[
              _HalfBadge(half: half!),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A "1st"/"2nd" program-half badge. Conveys the half with **icon + text**,
/// never colour alone (WCAG 1.4.1); the surrounding [_RowHeader]/[_DanceChip]
/// owns the screen-reader phrasing, so this badge excludes its own semantics.
class _HalfBadge extends StatelessWidget {
  const _HalfBadge({required this.half});

  final ProgramHalf half;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              half == ProgramHalf.first
                  ? Icons.looks_one_outlined
                  : Icons.looks_two_outlined,
              size: 13,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 2),
            Text(
              l10n.programsMatrixHalfShort(
                half == ProgramHalf.first ? 'first' : 'second',
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.danceTitle,
    required this.moveLabel,
    required this.present,
    required this.first,
    required this.programDebut,
    required this.collision,
  });

  final String danceTitle;
  final String moveLabel;
  final bool present;
  final bool first;
  final bool programDebut;
  final bool collision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    Widget? mark;
    if (collision) {
      // Same-figure-same-phrase collision with a strictly-adjacent dance: a
      // shape-distinct alert (never colour alone) that takes precedence over
      // the debut/first highlights — it's the signal a caller must notice.
      mark = Icon(Icons.report, size: 20, color: theme.colorScheme.error);
    } else if (programDebut) {
      // Program debut: distinct SHAPE (star) + text, not colour alone.
      mark = Icon(Icons.star, size: 20, color: theme.colorScheme.primary);
    } else if (first) {
      // Dance's opening figure: a shape-distinct flag (not the star) + text.
      mark = Icon(
        Icons.flag_outlined,
        size: 18,
        color: theme.colorScheme.secondary,
      );
    } else if (present) {
      mark = Icon(Icons.check, size: 18, color: theme.colorScheme.onSurface);
    }

    return Semantics(
      label: l10n.programsMatrixCellSemantic(
        danceTitle,
        moveLabel,
        present ? 'yes' : 'no',
        collision ? 'yes' : 'no',
        programDebut ? 'yes' : 'no',
        first ? 'yes' : 'no',
      ),
      excludeSemantics: true,
      child: Container(
        width: ProgramMatrixTable.columnWidth,
        height: ProgramMatrixTable.rowHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: collision
              ? theme.colorScheme.errorContainer.withValues(alpha: 0.4)
              : programDebut
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : first
              ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.3)
              : null,
          border: Border(
            right: BorderSide(color: theme.dividerColor, width: 0.5),
            bottom: BorderSide(color: theme.dividerColor, width: 0.5),
          ),
        ),
        child: mark,
      ),
    );
  }
}

/// Semantics phrasing shared by the grid and compact views is modelled directly
/// in the `matrixCellSemantic` ICU message (a single message with select
/// branches for present / introduced-here / dance's-first-figure), so no
/// fragment concatenation happens in Dart.

class _CompactMatrix extends StatelessWidget {
  const _CompactMatrix({
    required this.matrix,
    required this.labels,
    required this.altDanceIds,
  });

  final ProgramMatrix matrix;
  final List<String> labels;
  final Set<String> altDanceIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final total = matrix.rows.length;

    // Group present moves into those shared across dances (the core insight)
    // and those used just once. Columns with zero present dances (e.g. the
    // always-emitted partner/neighbor swing baseline when no dance swings that
    // role) are dropped — an unused move isn't part of "the set's moves".
    final repeated = <_MoveSummary>[];
    final singles = <_MoveSummary>[];
    for (var c = 0; c < matrix.columns.length; c++) {
      final dances = <_DanceUse>[];
      for (var r = 0; r < matrix.rows.length; r++) {
        if (matrix.isPresent(r, c)) {
          dances.add(
            _DanceUse(
              title: matrix.rows[r].title,
              first: matrix.isFirst(r, c),
              programDebut: matrix.isProgramDebut(r, c),
              collision: matrix.isPhraseCollision(r, c),
              isAlt: altDanceIds.contains(matrix.rows[r].danceId),
              half: matrix.rows[r].half,
            ),
          );
        }
      }
      if (dances.isEmpty) continue;
      final summary = _MoveSummary(label: labels[c], order: c, dances: dances);
      (dances.length >= 2 ? repeated : singles).add(summary);
    }
    // Most-repeated first; ties keep taxonomy column order (deterministic).
    repeated.sort((a, b) {
      final byCount = b.dances.length.compareTo(a.dances.length);
      return byCount != 0 ? byCount : a.order.compareTo(b.order);
    });

    final children = <Widget>[];
    if (repeated.isEmpty && singles.isEmpty) {
      // Dances exist but carry no comparable moves (e.g. only figure-less
      // dances, whose sole columns are the unused swing baseline). Say so
      // plainly rather than implying a move list that isn't there.
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.programsMatrixNoComparableMoves,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else {
      if (repeated.isNotEmpty) {
        children.add(
          _SectionHeader(label: l10n.programsMatrixRepeatedMovesHeader),
        );
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              l10n.programsMatrixRepeatedMovesSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
        for (final m in repeated) {
          children.add(_MoveCard(summary: m, total: total));
        }
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.programsMatrixNoRepeatsNote,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }

      if (singles.isNotEmpty) {
        children.add(_SectionHeader(label: l10n.programsMatrixUsedOnceHeader));
        for (final m in singles) {
          children.add(_MoveCard(summary: m, total: total));
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// Number of matrix columns present in at least one dance — the move count the
/// compact view actually renders (it drops columns no dance uses).
int _presentColumnCount(ProgramMatrix matrix) {
  var count = 0;
  for (var c = 0; c < matrix.columns.length; c++) {
    for (var r = 0; r < matrix.rows.length; r++) {
      if (matrix.isPresent(r, c)) {
        count++;
        break;
      }
    }
  }
  return count;
}

/// Per-move roll-up for the compact view: the move's label, its stable column
/// [order] (for deterministic tie-breaking), and the dances that use it.
class _MoveSummary {
  _MoveSummary({
    required this.label,
    required this.order,
    required this.dances,
  });

  final String label;
  final int order;
  final List<_DanceUse> dances;
}

/// A single dance's use of a move: its title, whether the move is that dance's
/// FIRST figure, whether this is the move's program debut (mirrors the grid's
/// two highlights), and whether the dance is an alternate slot (mirrors the
/// grid's ALT row badge).
class _DanceUse {
  _DanceUse({
    required this.title,
    required this.first,
    required this.programDebut,
    required this.collision,
    required this.isAlt,
    this.half,
  });

  final String title;
  final bool first;
  final bool programDebut;
  final bool collision;
  final bool isAlt;
  final ProgramHalf? half;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One move in the compact view: a header row (move label + "N of M dances"
/// count) over a wrap of the dances that use it. Preserves the grid's table
/// semantics — the header is flagged a semantic header ("Move: label, used in
/// N of M dances") and each dance chip announces "dance, move: present" (plus
/// "introduced here" / "dance's first figure"), matching [_Cell].
class _MoveCard extends StatelessWidget {
  const _MoveCard({required this.summary, required this.total});

  final _MoveSummary summary;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final n = summary.dances.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            label: l10n.programsMatrixMoveUsedInSemantic(
              summary.label,
              n,
              total,
            ),
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    summary.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.programsMatrixNOfTotal(n, total),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in summary.dances)
                _DanceChip(
                  danceTitle: d.title,
                  moveLabel: summary.label,
                  first: d.first,
                  programDebut: d.programDebut,
                  collision: d.collision,
                  isAlt: d.isAlt,
                  half: d.half,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DanceChip extends StatelessWidget {
  const _DanceChip({
    required this.danceTitle,
    required this.moveLabel,
    required this.first,
    required this.programDebut,
    required this.collision,
    required this.isAlt,
    this.half,
  });

  final String danceTitle;
  final String moveLabel;
  final bool first;
  final bool programDebut;
  final bool collision;
  final bool isAlt;
  final ProgramHalf? half;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Preserve the grid's ALT and half distinctions, which otherwise live only
    // in the wide row header, so they aren't lost on phones. The qualifier
    // phrasing is modelled as one ICU message (no fragment concatenation).
    final halfSelect = half == null
        ? 'none'
        : (half == ProgramHalf.first ? 'first' : 'second');
    final who = l10n.programsMatrixChipQualifiedTitle(
      danceTitle,
      isAlt ? 'yes' : 'no',
      halfSelect,
    );
    final IconData markIcon;
    final Color markColor;
    if (collision) {
      // Same-phrase repeat with a strictly-adjacent dance: top-precedence
      // alert (shape + semantics, never colour alone).
      markIcon = Icons.report;
      markColor = theme.colorScheme.error;
    } else if (programDebut) {
      markIcon = Icons.star;
      markColor = theme.colorScheme.primary;
    } else if (first) {
      markIcon = Icons.flag_outlined;
      markColor = theme.colorScheme.secondary;
    } else {
      markIcon = Icons.check;
      markColor = theme.colorScheme.onSurface;
    }
    return Semantics(
      label: l10n.programsMatrixCellSemantic(
        who,
        moveLabel,
        'yes',
        collision ? 'yes' : 'no',
        programDebut ? 'yes' : 'no',
        first ? 'yes' : 'no',
      ),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: collision
              ? theme.colorScheme.errorContainer.withValues(alpha: 0.4)
              : programDebut
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : first
              ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.3)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(markIcon, size: 14, color: markColor),
            if (isAlt) ...[
              const SizedBox(width: 3),
              Icon(
                Icons.alt_route,
                size: 14,
                color: theme.colorScheme.secondary,
              ),
            ],
            const SizedBox(width: 4),
            Text(danceTitle, style: theme.textTheme.labelMedium),
            if (half != null) ...[
              const SizedBox(width: 4),
              _HalfBadge(half: half!),
            ],
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _LegendItem(
            icon: Icons.report,
            color: theme.colorScheme.error,
            label: l10n.programsMatrixLegendCollision,
          ),
          _LegendItem(
            icon: Icons.star,
            color: theme.colorScheme.primary,
            label: l10n.programsMatrixLegendIntroduced,
          ),
          _LegendItem(
            icon: Icons.flag_outlined,
            color: theme.colorScheme.secondary,
            label: l10n.programsMatrixLegendFirstFigure,
          ),
          _LegendItem(
            icon: Icons.check,
            color: theme.colorScheme.onSurface,
            label: l10n.programsMatrixLegendPresent,
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: theme.textTheme.labelMedium)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.omittedFreeTextCount});

  final int omittedFreeTextCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.grid_on_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.programsMatrixEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.programsMatrixEmptyBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (omittedFreeTextCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                l10n.programsMatrixOmittedCaption(omittedFreeTextCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
