import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

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
                label:
                    'Programming matrix: '
                    '${matrix.rows.length} dances by '
                    '$moveCount moves',
                child: content,
              ),
            ),
            if (widget.omittedFreeTextCount > 0)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _omittedCaption(widget.omittedFreeTextCount),
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
              child: SingleChildScrollView(
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

/// Caption noting free-text slots that don't appear in the matrix (the matrix
/// is dances-only), so the omission is always explicit.
String _omittedCaption(int n) =>
    '$n free-text ${n == 1 ? 'slot' : 'slots'} '
    '(breaks, notes) omitted — the matrix shows dances only.';

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
    return Semantics(
      header: true,
      label: 'Move: $label',
      excludeSemantics: true,
      child: Tooltip(
        message: label,
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
    final halfLong = half == null ? '' : ', ${_halfLongLabel(half!)}';
    return Semantics(
      header: true,
      label: isAlt
          ? 'Alternate dance: $title$halfLong'
          : 'Dance: $title$halfLong',
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
              Text('ALT', style: theme.textTheme.labelSmall),
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

/// Short/long labels for a program [ProgramHalf], used by the matrix half
/// badge (short) and its screen-reader semantics (long).
String _halfShortLabel(ProgramHalf half) =>
    half == ProgramHalf.first ? '1st' : '2nd';

String _halfLongLabel(ProgramHalf half) =>
    half == ProgramHalf.first ? 'first half' : 'second half';

/// A "1st"/"2nd" program-half badge. Conveys the half with **icon + text**,
/// never colour alone (WCAG 1.4.1); the surrounding [_RowHeader]/[_DanceChip]
/// owns the screen-reader phrasing, so this badge excludes its own semantics.
class _HalfBadge extends StatelessWidget {
  const _HalfBadge({required this.half});

  final ProgramHalf half;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              _halfShortLabel(half),
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
  });

  final String danceTitle;
  final String moveLabel;
  final bool present;
  final bool first;
  final bool programDebut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _cellStateLabel(
      present: present,
      first: first,
      programDebut: programDebut,
    );

    Widget? mark;
    if (programDebut) {
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
      label: '$danceTitle, $moveLabel: $state',
      excludeSemantics: true,
      child: Container(
        width: ProgramMatrixTable.columnWidth,
        height: ProgramMatrixTable.rowHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: programDebut
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

/// Semantics phrasing shared by the grid and compact views. A cell that is both
/// a program debut and its dance's opening figure announces both, distinctly.
String _cellStateLabel({
  required bool present,
  required bool first,
  required bool programDebut,
}) {
  if (!present && !first && !programDebut) return 'not present';
  final parts = <String>['present'];
  if (programDebut) parts.add('introduced here');
  if (first) parts.add("dance's first figure");
  return parts.join(', ');
}

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
            'None of these dances have structured figures yet, so there are '
            'no moves to compare.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else {
      if (repeated.isNotEmpty) {
        children.add(_SectionHeader(label: 'Repeated moves'));
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              'Moves shared across two or more dances, most-repeated first.',
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
              'No moves repeat across these dances — every move below is used '
              'by a single dance.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }

      if (singles.isNotEmpty) {
        children.add(_SectionHeader(label: 'Used once'));
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
    required this.isAlt,
    this.half,
  });

  final String title;
  final bool first;
  final bool programDebut;
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
    final n = summary.dances.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            label: 'Move: ${summary.label}, used in $n of $total dances',
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
                  '$n of $total',
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
    required this.isAlt,
    this.half,
  });

  final String danceTitle;
  final String moveLabel;
  final bool first;
  final bool programDebut;
  final bool isAlt;
  final ProgramHalf? half;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _cellStateLabel(
      present: true,
      first: first,
      programDebut: programDebut,
    );
    // Preserve the grid's ALT and half distinctions, which otherwise live only
    // in the wide row header, so they aren't lost on phones.
    final qualifiers = [
      if (isAlt) 'alternate dance',
      if (half != null) _halfLongLabel(half!),
    ];
    final who = qualifiers.isEmpty
        ? danceTitle
        : '$danceTitle (${qualifiers.join(', ')})';
    final IconData markIcon;
    final Color markColor;
    if (programDebut) {
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
      label: '$who, $moveLabel: $state',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: programDebut
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _LegendItem(
            icon: Icons.star,
            color: theme.colorScheme.primary,
            label: 'Introduced here',
          ),
          _LegendItem(
            icon: Icons.flag_outlined,
            color: theme.colorScheme.secondary,
            label: "Dance's first figure",
          ),
          _LegendItem(
            icon: Icons.check,
            color: theme.colorScheme.onSurface,
            label: 'Present',
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
        Text(label, style: theme.textTheme.labelMedium),
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
              'No structured figures yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'The matrix fills in automatically as the program’s dances '
              'gain structured figures.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (omittedFreeTextCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                _omittedCaption(omittedFreeTextCount),
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
