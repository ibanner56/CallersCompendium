import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/verbose_figure_rendering_scope.dart';
import '../search/facet_labels.dart';

/// Read-only figure table grouped by derived phrase section (`docs/design/ux.md`
/// §2). Each section (A1, A2, …) heads a group; rows show the rendered figure
/// text (under [dialect]), a progression marker, and the beat count.
///
/// Structured editing of these rows lands with roadmap 3.3b; here the table is
/// display-only, shared by the dance detail view and the (read-only) figure
/// section of the editor.
class FigureTable extends StatelessWidget {
  const FigureTable({
    super.key,
    required this.figures,
    required this.phraseStructure,
    required this.renderer,
    required this.dialect,
  });

  final List<Figure> figures;
  final PhraseStructure phraseStructure;
  final FigureRenderer renderer;
  final Dialect dialect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (figures.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('No figures yet.', style: theme.textTheme.bodyMedium),
      );
    }

    final sectioned = deriveSections(figures, phraseStructure);
    // ROADMAP G.7: when "always verbose" is on, the visible row text uses the
    // spoken-style verbose rendering instead of the terse notation.
    final verbose = VerboseFigureRenderingScope.of(context);
    final rows = <Widget>[];
    String? lastLabel;
    var isFirstRowInSection = true;
    for (final sf in sectioned) {
      if (sf.label != lastLabel) {
        rows.add(_SectionHeader(label: sf.label));
        lastLabel = sf.label;
        isFirstRowInSection = true;
      }
      if (!isFirstRowInSection) {
        rows.add(const Divider(height: 1));
      }
      rows.add(
        _FigureRow(
          text: renderer.renderSummary(sf.figure, dialect),
          verboseText: renderer.renderSummary(
            sf.figure,
            dialect,
            verbose: true,
          ),
          showVerbose: verbose,
          beats: sf.figure.beats,
          progression: sf.figure.progression,
          note: sf.figure.note,
        ),
      );
      isFirstRowInSection = false;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _FigureRow extends StatelessWidget {
  const _FigureRow({
    required this.text,
    required this.verboseText,
    required this.showVerbose,
    required this.beats,
    required this.progression,
    required this.note,
  });

  /// Terse, dialect-applied text shown on screen (unless [showVerbose]).
  final String text;

  /// Verbose, spoken-friendly rendering announced to assistive tech in place of
  /// the terse [text] (figure-taxonomy.md §5.4 / accessibility baseline). When
  /// [showVerbose] is true it is also used as the visible text (ROADMAP G.7).
  final String verboseText;

  /// When true, the visible row text is [verboseText] rather than [text]
  /// ("always show verbose figure text" — ROADMAP G.7).
  final bool showVerbose;
  final int beats;
  final bool progression;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beatsLabel = '$beats ${beats == 1 ? 'beat' : 'beats'}';
    final semanticsLabel = [
      verboseText,
      if (progression) 'progression',
      beatsLabel,
      if (note != null && note!.trim().isNotEmpty) 'note: ${note!.trim()}',
    ].join(', ');
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: progression
                  ? Tooltip(
                      message: 'Progression',
                      child: Icon(
                        progressionIcon,
                        size: MediaQuery.textScalerOf(context)
                            .scale(theme.textTheme.bodyLarge?.fontSize ?? 16)
                            .clamp(16.0, 24.0),
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showVerbose ? verboseText : text,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (note != null && note!.trim().isNotEmpty)
                    Text(
                      note!.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              beatsLabel,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
