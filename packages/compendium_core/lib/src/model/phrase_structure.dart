import 'package:meta/meta.dart';

import '../validation/validation.dart';
import 'figure.dart';

/// Musical phrase structure of a dance.
///
/// Persisted as a compact string on the dance (`""` = the standard
/// 4×16-beat A1 A2 B1 B2; otherwise one or more ordered
/// `phrases*bars*beatsPerBar` components separated by ` + `, e.g. `6*8*2` or
/// `3*8*2 + 1*4*2`). Section labels (A1, B2, …) are **derived** from cumulative
/// figure beats against this structure — never stored — so reordering figures
/// or editing beats stays consistent.
@immutable
class PhraseStructure {
  PhraseStructure._(List<PhraseComponent> components, this.raw)
    : components = List.unmodifiable(components);

  /// The standard contra structure: 4 phrases of 16 beats (A1 A2 B1 B2).
  static final PhraseStructure standard = PhraseStructure._(const [
    PhraseComponent._(4, 8, 2),
  ], '');

  /// Parses a phrase-structure string.
  ///
  /// Accepts `""` (standard), a `phrases*bars*beatsPerBar` component, or
  /// ordered components separated by `+`. Component numbers must be positive
  /// integers; whitespace is allowed around, but not inside, a component.
  /// Throws [FormatException] otherwise.
  factory PhraseStructure.parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return standard;

    final componentStrings = trimmed.split('+');
    if (componentStrings.any((component) => component.trim().isEmpty)) {
      throw FormatException(
        'expected one or more "phrases*bars*beatsPerBar" components, '
        'got "$raw"',
        raw,
      );
    }

    return PhraseStructure._([
      for (final component in componentStrings)
        _parseComponent(component.trim(), raw),
    ], trimmed);
  }

  static PhraseComponent _parseComponent(String component, String raw) {
    final match = RegExp(r'^(\d+)\*(\d+)\*(\d+)$').firstMatch(component);
    if (match == null) {
      throw FormatException(
        'expected "phrases*bars*beatsPerBar" component, got "$raw"',
        raw,
      );
    }

    final numbers = [
      int.tryParse(match.group(1)!),
      int.tryParse(match.group(2)!),
      int.tryParse(match.group(3)!),
    ];
    if (numbers.any((number) => number == null || number <= 0)) {
      throw FormatException(
        'phrase structure parts must be positive integers: "$raw"',
        raw,
      );
    }
    return PhraseComponent._(numbers[0]!, numbers[1]!, numbers[2]!);
  }

  /// Ordered phrase components, retained exactly enough to preserve uneven
  /// source phrasing and derive its beat boundaries.
  final List<PhraseComponent> components;

  /// The total number of phrases across all [components].
  int get phraseCount =>
      components.fold(0, (count, component) => count + component.phraseCount);

  /// Beats in every phrase when [components] are uniform; otherwise `null`.
  ///
  /// Callers that need section derivation must use [labelAtBeat] or
  /// [isPhraseBoundary], which account for each component's own length.
  int? get beatsPerPhrase {
    final first = components.first.beatsPerPhrase;
    return components.every((component) => component.beatsPerPhrase == first)
        ? first
        : null;
  }

  /// The persisted representation (`""` for standard).
  final String raw;

  int get totalBeats =>
      components.fold(0, (total, component) => total + component.totalBeats);

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
    return labels[_phraseIndexAtBeat(beat)];
  }

  /// Whether [beat] falls at the start of a phrase, wrapping at the end of the
  /// structure as [labelAtBeat] does.
  bool isPhraseBoundary(int beat) {
    if (beat < 0) throw ArgumentError.value(beat, 'beat', 'must be >= 0');
    var offset = beat % totalBeats;
    if (offset == 0) return true;

    for (final component in components) {
      if (offset < component.totalBeats) {
        return offset % component.beatsPerPhrase == 0;
      }
      offset -= component.totalBeats;
    }
    throw StateError('could not find phrase boundary for beat $beat');
  }

  int _phraseIndexAtBeat(int beat) {
    var offset = beat % totalBeats;
    var phraseIndex = 0;
    for (final component in components) {
      if (offset < component.totalBeats) {
        return phraseIndex + offset ~/ component.beatsPerPhrase;
      }
      offset -= component.totalBeats;
      phraseIndex += component.phraseCount;
    }
    throw StateError('could not find phrase for beat $beat');
  }

  @override
  bool operator ==(Object other) =>
      other is PhraseStructure &&
      other.components.length == components.length &&
      _sameComponents(other.components, components);

  @override
  int get hashCode => Object.hashAll(components);

  @override
  String toString() => 'PhraseStructure($raw)';
}

bool _sameComponents(List<PhraseComponent> left, List<PhraseComponent> right) {
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// One uniform run within a [PhraseStructure].
@immutable
class PhraseComponent {
  const PhraseComponent._(this.phraseCount, this.bars, this.beatsPerBar);

  /// Number of adjacent phrases in this component.
  final int phraseCount;

  /// Bars in each phrase.
  final int bars;

  /// Beats in each bar.
  final int beatsPerBar;

  /// Beats in each phrase in this component.
  int get beatsPerPhrase => bars * beatsPerBar;

  /// Beats across this complete component.
  int get totalBeats => phraseCount * beatsPerPhrase;

  @override
  bool operator ==(Object other) =>
      other is PhraseComponent &&
      other.phraseCount == phraseCount &&
      other.bars == bars &&
      other.beatsPerBar == beatsPerBar;

  @override
  int get hashCode => Object.hash(phraseCount, bars, beatsPerBar);
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
  if (figureBeats == 0 && beat > 0 && structure.isPhraseBoundary(beat)) {
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
