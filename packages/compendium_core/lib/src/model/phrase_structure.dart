import 'package:meta/meta.dart';

import '../validation/validation.dart';
import 'figure.dart';

/// Musical phrase structure of a dance.
///
/// Persisted as a compact string on the dance (`""` = the standard
/// 4×16-beat A1 A2 B1 B2; otherwise The Caller's Box `phrases*bars*beatsPerBar`
/// convention, e.g. `6*8*2` for a 48-bar dance). Section labels (A1, B2, …)
/// are **derived** from cumulative figure beats against this structure — never
/// stored — so reordering figures or editing beats stays consistent.
@immutable
class PhraseStructure {
  const PhraseStructure._(this.phraseCount, this.beatsPerPhrase, this.raw);

  /// The standard contra structure: 4 phrases of 16 beats (A1 A2 B1 B2).
  static const PhraseStructure standard = PhraseStructure._(4, 16, '');

  /// Parses a phrase-structure string.
  ///
  /// Accepts `""` (standard) or `phrases*bars*beatsPerBar` with positive
  /// integers. Throws [FormatException] otherwise.
  factory PhraseStructure.parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return standard;
    final parts = trimmed.split('*');
    if (parts.length != 3) {
      throw FormatException(
        'expected "phrases*bars*beatsPerBar", got "$raw"',
        raw,
      );
    }
    final numbers = parts.map(int.tryParse).toList();
    if (numbers.any((n) => n == null || n <= 0)) {
      throw FormatException(
        'phrase structure parts must be positive integers: "$raw"',
        raw,
      );
    }
    return PhraseStructure._(numbers[0]!, numbers[1]! * numbers[2]!, trimmed);
  }

  final int phraseCount;
  final int beatsPerPhrase;

  /// The persisted representation (`""` for standard).
  final String raw;

  int get totalBeats => phraseCount * beatsPerPhrase;

  /// Phrase labels: paired letters (A1 A2 B1 B2 C1 C2 …), the convention for
  /// contra/ECD music. An odd phrase count leaves the last pair incomplete,
  /// e.g. 3 phrases label as `A1 A2 B1` (the trailing phrase gets the next
  /// letter's `1`, not a full pair).
  List<String> get labels => List.generate(phraseCount, (i) {
    final letter = String.fromCharCode('A'.codeUnitAt(0) + i ~/ 2);
    return '$letter${i % 2 + 1}';
  });

  /// Label of the phrase containing [beat] (0-based). Beats past the end of
  /// the structure wrap (dances are repeated to the tune).
  String labelAtBeat(int beat) {
    if (beat < 0) throw ArgumentError.value(beat, 'beat', 'must be >= 0');
    return labels[(beat % totalBeats) ~/ beatsPerPhrase];
  }

  @override
  bool operator ==(Object other) =>
      other is PhraseStructure &&
      other.phraseCount == phraseCount &&
      other.beatsPerPhrase == beatsPerPhrase;

  @override
  int get hashCode => Object.hash(phraseCount, beatsPerPhrase);

  @override
  String toString() => 'PhraseStructure($phraseCount x $beatsPerPhrase beats)';
}

/// Returns the phrase label for a figure starting at [beat] with [figureBeats]
/// beats, using [structure] to map beats to labels.
///
/// For non-zero-length figures the start beat determines the label — the
/// calling convention is "the phrase it starts in". For **zero-length** figures
/// the tie is resolved backward: the figure belongs to the phrase that just
/// ended, not the one that follows. Exception: beat 0 has no preceding phrase,
/// so a zero-beat figure there stays in the first phrase.
String labelForFigure(int beat, int figureBeats, PhraseStructure structure) {
  if (figureBeats == 0 &&
      beat > 0 &&
      beat % structure.beatsPerPhrase == 0) {
    return structure.labelAtBeat(beat - 1);
  }
  return structure.labelAtBeat(beat);
}

/// A figure's derived position within the phrase structure.
@immutable
class SectionedFigure {
  const SectionedFigure({
    required this.index,
    required this.figure,
    required this.startBeat,
    required this.label,
  });

  /// Index of [figure] within the dance's figure list.
  final int index;
  final Figure figure;

  /// Cumulative beat offset at which this figure starts (0-based).
  final int startBeat;

  /// Label of the phrase in which this figure *starts* (e.g. `A2`). Figures
  /// may span phrase boundaries; the start phrase is the calling convention.
  /// Zero-beat figures at a phrase boundary (beat > 0) are attributed to the
  /// preceding phrase — they sit between two phrases and musically belong with
  /// the one that just ended.
  final String label;
}

/// Derives phrase sections for [figures] and flags beat-total mismatches.
///
/// Returns the sectioned figures; any mismatch between total figure beats and
/// the structure's total is appended to [issues] as a **warning**, never an
/// error — real dances bend phrasing, and choreography validation proper is a
/// later milestone.
///
/// A `meanwhile` container figure (#590) is a single flat list element, so it
/// contributes its **shared** beats (`params['beats']`, read via [Figure.beats])
/// exactly **once** — the loop never recurses into its concurrent sides, so a
/// side's display-only beats can never leak into the cumulative total.
List<SectionedFigure> deriveSections(
  List<Figure> figures,
  PhraseStructure structure, {
  List<ValidationIssue>? issues,
}) {
  final result = <SectionedFigure>[];
  var beat = 0;
  for (var i = 0; i < figures.length; i++) {
    result.add(
      SectionedFigure(
        index: i,
        figure: figures[i],
        startBeat: beat,
        label: labelForFigure(beat, figures[i].beats, structure),
      ),
    );
    // One list element → one beat advance. For a meanwhile container this is
    // the shared count, counted once (no double-count from its nested sides).
    beat += figures[i].beats;
  }
  if (issues != null && figures.isNotEmpty && beat != structure.totalBeats) {
    issues.add(
      ValidationIssue(
        severity: ValidationSeverity.warning,
        code: beat > structure.totalBeats
            ? 'phrase_overflow'
            : 'phrase_underflow',
        message:
            'figures total $beat beats; '
            'structure expects ${structure.totalBeats}',
        data: {'actual': beat, 'expected': structure.totalBeats},
      ),
    );
  }
  return result;
}
