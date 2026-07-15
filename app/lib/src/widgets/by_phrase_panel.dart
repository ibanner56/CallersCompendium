import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../search/collection_query.dart';
import 'advanced_query_builder.dart' show MoveTypeAheadField;

/// A Caller's Box-style "search by phrase" panel
/// (https://www.ibiblio.org/contradance/thecallersbox/). For each phrase of the
/// dance (the standard four — A1, A2, B1, B2 — via [sectionLabels]) the caller
/// lists figures that MUST occur in that phrase ("figures match") and figures
/// that must NOT ("but do not match").
///
/// It edits the mutable [selections] in place and calls [onChanged] after every
/// edit so the parent recompiles and re-runs the search. The selections compile
/// to the existing section-aware figure query in [buildCollectionFilter]:
/// within a phrase every "match" move must be present (AND) and no "do not
/// match" move may be present (each negated); across phrases all constraints
/// AND together.
class ByPhrasePanel extends StatelessWidget {
  const ByPhrasePanel({
    super.key,
    required this.selections,
    required this.taxonomy,
    required this.sectionLabels,
    required this.onChanged,
  });

  final ByPhraseSelections selections;
  final Taxonomy taxonomy;
  final List<String> sectionLabels;
  final VoidCallback onChanged;

  /// Caller's Box-style caption for the [index]-th phrase, e.g.
  /// "first phrase (usually A1)". Ordinals beyond the fourth fall back to
  /// "phrase N".
  static String captionFor(int index, String label) {
    const ordinals = ['first', 'second', 'third', 'fourth'];
    final ordinal = index < ordinals.length
        ? '${ordinals[index]} phrase'
        : 'phrase ${index + 1}';
    return '$ordinal (usually $label)';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, label) in sectionLabels.indexed)
          _PhraseRow(
            key: ValueKey('by-phrase-$label'),
            label: label,
            caption: captionFor(index, label),
            selections: selections,
            taxonomy: taxonomy,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

class _PhraseRow extends StatelessWidget {
  const _PhraseRow({
    super.key,
    required this.label,
    required this.caption,
    required this.selections,
    required this.taxonomy,
    required this.onChanged,
  });

  final String label;
  final String caption;
  final ByPhraseSelections selections;
  final Taxonomy taxonomy;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Visual grouping header. Excluded from the semantics tree because
          // each field below already carries the phrase in its accessible name,
          // so assistive tech hears the phrase once (on the control it acts on).
          ExcludeSemantics(
            child: Text(caption, style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: 4),
          _MoveMultiField(
            keyPrefix: 'match-$label',
            fieldLabel: '$caption, figures match',
            moves: selections.match.putIfAbsent(label, () => []),
            taxonomy: taxonomy,
            onChanged: onChanged,
          ),
          const SizedBox(height: 4),
          _MoveMultiField(
            keyPrefix: 'exclude-$label',
            fieldLabel: '$caption, but do not match',
            moves: selections.exclude.putIfAbsent(label, () => []),
            taxonomy: taxonomy,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// One "figures match" / "but do not match" input: a labeled row of removable
/// chips (the chosen moves) plus a [MoveTypeAheadField] to add more. Multiple
/// moves accumulate; the compile step ANDs "match" moves and negates each
/// "do not match" move.
class _MoveMultiField extends StatelessWidget {
  const _MoveMultiField({
    required this.keyPrefix,
    required this.fieldLabel,
    required this.moves,
    required this.taxonomy,
    required this.onChanged,
  });

  final String keyPrefix;
  final String fieldLabel;
  final List<String> moves;
  final Taxonomy taxonomy;
  final VoidCallback onChanged;

  String _displayName(String moveId) =>
      taxonomy.resolve(moveId)?.displayName ?? moveId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (moves.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (final moveId in moves)
                  InputChip(
                    key: ValueKey('$keyPrefix-chip-$moveId'),
                    label: Text(_displayName(moveId)),
                    onDeleted: () {
                      moves.remove(moveId);
                      onChanged();
                    },
                    deleteButtonTooltipMessage:
                        'Remove ${_displayName(moveId)} from $fieldLabel',
                  ),
              ],
            ),
          ),
        SizedBox(
          width: 260,
          child: MoveTypeAheadField(
            // Remount (clearing the input) after each pick so the next move can
            // be typed into an empty field. The key also stays stable per moves
            // count for reliable test targeting.
            key: ValueKey('$keyPrefix-input-${moves.length}'),
            taxonomy: taxonomy,
            labelText: fieldLabel,
            onSelected: (m) {
              if (!moves.contains(m.id)) {
                moves.add(m.id);
                onChanged();
              }
            },
          ),
        ),
      ],
    );
  }
}
