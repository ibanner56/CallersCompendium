import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

/// Read-only **programming matrix** (moves × dances) for the Program builder's
/// Matrix tab (`docs/design/ux.md` §4).
///
/// Columns are the moves actually present across the program's dances (derived
/// by [buildProgramMatrix] — no manual checklist, CC's failure mode). Each cell
/// shows whether a dance uses that move; each dance's FIRST figure is
/// highlighted. Presence and the first-figure highlight are conveyed with an
/// **icon + text/semantics, never colour alone** (WCAG 1.4.1).
///
/// Layout: a four-quadrant grid (corner / pinned column headers / pinned row
/// headers / scrolling body) with the row- and column-header scroll positions
/// mirrored to the body via linked [ScrollController]s, so both headers stay
/// pinned while the body scrolls in both directions. The grid is exposed as a
/// semantic table: header cells are flagged headers and every data cell
/// announces `<dance>, <move>: present/not present[, first figure]`.
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

    final table = Column(
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
                '${matrix.rows.length} dances by ${matrix.columns.length} moves',
            child: table,
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
  }
}

/// Caption noting free-text slots that don't appear in the matrix (the matrix
/// is dances-only), so the omission is always explicit.
String _omittedCaption(int n) =>
    '$n free-text ${n == 1 ? 'slot' : 'slots'} '
    '(breaks, notes) omitted — the matrix shows dances only.';

class _Corner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: ProgramMatrixTable.rowHeaderWidth,
    height: ProgramMatrixTable.columnHeaderHeight,
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
  const _RowHeader({required this.title, required this.isAlt});

  final String title;
  final bool isAlt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      label: isAlt ? 'Alternate dance: $title' : 'Dance: $title',
      excludeSemantics: true,
      child: Container(
        width: ProgramMatrixTable.rowHeaderWidth,
        height: ProgramMatrixTable.rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
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

class _Cell extends StatelessWidget {
  const _Cell({
    required this.danceTitle,
    required this.moveLabel,
    required this.present,
    required this.first,
  });

  final String danceTitle;
  final String moveLabel;
  final bool present;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = first
        ? 'first figure'
        : present
        ? 'present'
        : 'not present';

    Widget? mark;
    if (first) {
      // Distinct SHAPE (star) + text, not colour alone.
      mark = Icon(Icons.star, size: 20, color: theme.colorScheme.primary);
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
          color: first
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
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
            label: 'First figure',
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
