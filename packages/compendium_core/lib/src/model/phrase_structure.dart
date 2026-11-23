import 'package:meta/meta.dart';

import '../validation/validation.dart';
import 'figure.dart';

/// Musical phrase structure of a dance.
///
/// Persisted as a compact string on the dance (`""` = the standard
/// 4×16-beat A1 A2 B1 B2; otherwise one or more ordered
/// `phrases*bars*beatsPerBar` components separated by ` + `, e.g. `6*8*2` or
/// `3*8*2 + 1*4*2`), bounded by [PhraseStructure.maxComponentNumber] and its
/// sibling limits. Section labels (A1, B2, …) are **derived** from cumulative
/// figure beats against this structure — never stored — so reordering figures
/// or editing beats stays consistent.
///
/// **Named phrases** (English dances; Hudson, 20 November 2026): each
/// component may instead start with the caller's own phrase name, `A:`, `B:`
/// or `C:`, as in `A:2*4*2 + B:1*8*2` (an A of 4 bars played twice, then a B
/// of 8 bars once). Then every component is named, each name is used once,
/// and each phrase plays once or twice, its repeat straight after it. A
/// phrase played once is labeled by its name alone (`B`); one played twice
/// is labeled `A1` and `A2`. A structure with no names keeps the paired
/// labels above.
@immutable
class PhraseStructure {
  const PhraseStructure._(this.components, this.raw);

  /// The standard contra structure: 4 phrases of 16 beats (A1 A2 B1 B2).
  static const PhraseStructure standard = PhraseStructure._([
    PhraseComponent._(4, 8, 2),
  ], '');

  /// Largest accepted value for any one of `phrases`, `bars` or `beatsPerBar`.
  static const int maxComponentNumber = 1000;

  /// Most `+`-separated components a structure may have.
  static const int maxComponents = 64;

  /// Most phrases accepted across all components.
  static const int maxPhraseCount = 1000;

  /// Most beats accepted across all components. Together with
  /// [maxComponentNumber] this keeps every product inside 53 bits (web ints).
  static const int maxTotalBeats = 1000000;

  /// The names a caller may give a phrase, in the order they are offered.
  static const List<String> phraseNames = ['A', 'B', 'C'];

  /// Most times a named phrase plays: once, or twice with its repeat.
  static const int maxNamedPlays = 2;

  /// Parses a phrase-structure string, falling back to [standard] when [raw]
  /// is not a valid, in-bounds structure.
  ///
  /// For reading values that are already stored: a value written before the
  /// bounds existed must not stop its dance from loading.
  static PhraseStructure parseOrStandard(String raw) {
    try {
      return PhraseStructure.parse(raw);
    } on FormatException {
      // diagnostics: silent — the documented fallback for a stored value that
      // is unreadable or was written before the bounds existed.
      return standard;
    }
  }

  /// Parses a phrase-structure string.
  ///
  /// Accepts `""` (standard), a `phrases*bars*beatsPerBar` component, or
  /// ordered components separated by `+`. A component may be named by an
  /// `A:`, `B:` or `C:` prefix (`A:2*4*2 + B:1*8*2`): then every component is
  /// named, each name is used once, and each named phrase plays at most
  /// [maxNamedPlays] times. Component numbers must be positive integers no
  /// larger than [maxComponentNumber]; there may be at most [maxComponents]
  /// components, [maxPhraseCount] phrases and [maxTotalBeats] beats in all.
  /// Whitespace is allowed around a component and around a name's colon,
  /// but not inside `phrases*bars*beatsPerBar`; [raw] keeps the trimmed
  /// text as given, spaces included. Throws [FormatException] otherwise.
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

    if (componentStrings.length > maxComponents) {
      throw FormatException(
        'phrase structure has more than $maxComponents components: "$raw"',
        raw,
      );
    }

    final components = List<PhraseComponent>.unmodifiable([
      for (final component in componentStrings)
        _parseComponent(component.trim(), raw),
    ]);
    _checkNames(components, raw);
    // Each number is already <= maxComponentNumber, so these sums and products
    // cannot overflow before they are checked.
    final phrases = components.fold(0, (sum, c) => sum + c.phraseCount);
    final beats = components.fold(0, (sum, c) => sum + c.totalBeats);
    if (phrases > maxPhraseCount || beats > maxTotalBeats) {
      throw FormatException(
        'phrase structure is larger than $maxPhraseCount phrases or '
        '$maxTotalBeats beats: "$raw"',
        raw,
      );
    }
    return PhraseStructure._(components, trimmed);
  }

  /// Named phrases: all or none named, each name once, each played once or
  /// twice.
  static void _checkNames(List<PhraseComponent> components, String raw) {
    final named = components.where((c) => c.name != null).length;
    if (named == 0) return;
    if (named != components.length) {
      throw FormatException(
        'either every phrase is named or none is: "$raw"',
        raw,
      );
    }
    final names = {for (final c in components) c.name};
    if (names.length != components.length) {
      throw FormatException('each phrase name is used once: "$raw"', raw);
    }
    if (components.any((c) => c.phraseCount > maxNamedPlays)) {
      throw FormatException(
        'a named phrase plays at most $maxNamedPlays times: "$raw"',
        raw,
      );
    }
  }

  static final RegExp _component = RegExp(
    r'^(?:([ABC])\s*:\s*)?(\d+)\*(\d+)\*(\d+)$',
  );

  static PhraseComponent _parseComponent(String component, String raw) {
    final match = _component.firstMatch(component);
    if (match == null) {
      throw FormatException(
        'expected "phrases*bars*beatsPerBar" component, got "$raw"',
        raw,
      );
    }

    final numbers = [
      int.tryParse(match.group(2)!),
      int.tryParse(match.group(3)!),
      int.tryParse(match.group(4)!),
    ];
    if (numbers.any((number) => number == null || number <= 0)) {
      throw FormatException(
        'phrase structure parts must be positive integers: "$raw"',
        raw,
      );
    }
    if (numbers.any((number) => number! > maxComponentNumber)) {
      throw FormatException(
        'phrase structure parts must be at most $maxComponentNumber: "$raw"',
        raw,
      );
    }
    return PhraseComponent._(
      numbers[0]!,
      numbers[1]!,
      numbers[2]!,
      match.group(1),
    );
  }

  /// A structure of named phrases, written as it is stored: each part's
  /// [NamedPhrase.name], how many times it plays, its bars and beats per bar,
  /// in order. Throws [FormatException] as [PhraseStructure.parse] does when
  /// [phrases] break its rules or bounds; an empty list is the standard
  /// structure.
  factory PhraseStructure.named(List<NamedPhrase> phrases) =>
      PhraseStructure.parse(
        phrases
            .map((p) => '${p.name}:${p.plays}*${p.bars}*${p.beatsPerBar}')
            .join(' + '),
      );

  /// Whether the caller named the phrases ([phraseNames]).
  bool get isNamed => components.first.name != null;

  /// The named phrases, in order, or null when [isNamed] is false.
  List<NamedPhrase>? get namedPhrases => isNamed
      ? [
          for (final c in components)
            NamedPhrase(
              name: c.name!,
              plays: c.phraseCount,
              bars: c.bars,
              beatsPerBar: c.beatsPerBar,
            ),
        ]
      : null;

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

  /// Whether the components differ in beats per bar, so that one count of
  /// bars would mean different lengths in different parts of the tune.
  bool get hasMixedMeter {
    final first = components.first.beatsPerBar;
    return components.any((component) => component.beatsPerBar != first);
  }

  /// Beats in the longest phrase: [beatsPerPhrase] when the phrases are
  /// uniform, and the largest component's phrase length when they are not.
  ///
  /// This is the "one phrase" a `sequence` container must fit in
  /// ([sequenceExceedsPhrase]). An uneven structure takes its longest phrase
  /// rather than its shortest, so a sequence that fits the phrase it is danced
  /// in is never flagged; the cost is that one overrunning a shorter phrase is
  /// not flagged either.
  int get longestPhraseBeats => components.fold(
    0,
    (longest, component) =>
        component.beatsPerPhrase > longest ? component.beatsPerPhrase : longest,
  );

  /// The beat at which the longest phrase ([longestPhraseBeats]) starts, so
  /// that its length reads in the bars of its own part of the tune; null where
  /// phrases tied for longest differ in bars, which no one bar length reads.
  int? get longestPhraseStart {
    final longest = longestPhraseBeats;
    int? start;
    int? bars;
    var offset = 0;
    for (final component in components) {
      if (component.beatsPerPhrase == longest) {
        if (bars != null && bars != component.bars) return null;
        start ??= offset;
        bars = component.bars;
      }
      offset += component.totalBeats;
    }
    return start;
  }

  /// The persisted representation (`""` for standard).
  final String raw;

  int get totalBeats =>
      components.fold(0, (total, component) => total + component.totalBeats);

  /// Phrase labels: paired letters (A1 A2 B1 B2 C1 C2 …), the convention for
  /// contra/ECD music. An odd phrase count leaves the last pair incomplete,
  /// e.g. 3 phrases label as `A1 A2 B1` (the trailing phrase gets the next
  /// letter's `1`, not a full pair). Named phrases ([isNamed]) are labeled
  /// by their names instead: `A` for a phrase played once, `A1` and `A2` for
  /// one played twice.
  List<String> get labels =>
      List.generate(phraseCount, _labelForPhrase, growable: false);

  String _labelForPhrase(int i) {
    if (isNamed) {
      var index = i;
      for (final component in components) {
        if (index < component.phraseCount) {
          return component.phraseCount == 1
              ? component.name!
              : '${component.name}${index + 1}';
        }
        index -= component.phraseCount;
      }
      throw StateError('no phrase $i');
    }
    final letter = String.fromCharCode('A'.codeUnitAt(0) + i ~/ 2);
    return '$letter${i % 2 + 1}';
  }

  /// Label of the phrase containing [beat] (0-based). Beats past the end of
  /// the structure wrap (dances are repeated to the tune).
  String labelAtBeat(int beat) {
    if (beat < 0) throw ArgumentError.value(beat, 'beat', 'must be >= 0');
    return _labelForPhrase(_phraseIndexAtBeat(beat));
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

  /// The component that plays at [beat] (0-based), wrapping at the end of the
  /// structure as [labelAtBeat] does.
  PhraseComponent componentAtBeat(int beat) {
    if (beat < 0) throw ArgumentError.value(beat, 'beat', 'must be >= 0');
    var offset = beat % totalBeats;
    for (final component in components) {
      if (offset < component.totalBeats) return component;
      offset -= component.totalBeats;
    }
    throw StateError('could not find component for beat $beat');
  }

  /// Beats in the phrase that plays at [beat], wrapping past the end as
  /// [componentAtBeat] does: the most a `sequence` that starts at [beat] may
  /// hold ([sequenceExceedsPhrase]).
  int phraseBeatsAt(int beat) => componentAtBeat(beat).beatsPerPhrase;

  /// The beat at which the phrase that plays at [beat] starts: [beat] less
  /// how far into that phrase it falls. Wraps past the end as
  /// [componentAtBeat] does, so the result is never after [beat].
  int phraseStartAt(int beat) {
    if (beat < 0) throw ArgumentError.value(beat, 'beat', 'must be >= 0');
    var offset = beat % totalBeats;
    for (final component in components) {
      if (offset < component.totalBeats) {
        return beat - offset % component.beatsPerPhrase;
      }
      offset -= component.totalBeats;
    }
    throw StateError('could not find phrase for beat $beat');
  }

  /// Beats in [halfBars] half bars of the component that plays at [atBeat],
  /// or `null` when that is not a whole number of beats.
  ///
  /// This is the half-bar rule (ADR-006 Q16): timing entered in bars may use
  /// half a bar only where half a bar is a whole number of beats, so an odd
  /// count of half bars is refused in triple time. Beats are stored as whole
  /// numbers, so finer timing goes in a note instead. Whole bars are always
  /// accepted. Only the meter at [atBeat] is read: a span that starts in one
  /// part of the tune and runs into a part in another meter is judged by the
  /// part it starts in. ([BarTiming.beatsForHalfBars] counts each of a span's
  /// bars by the part it starts in; this reads only the first.)
  int? beatsForHalfBars(int halfBars, {int atBeat = 0}) {
    if (halfBars < 0) {
      throw ArgumentError.value(halfBars, 'halfBars', 'must be >= 0');
    }
    final beatsPerBar = componentAtBeat(atBeat).beatsPerBar;
    final doubled = halfBars * beatsPerBar;
    return doubled.isEven ? doubled ~/ 2 : null;
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
  const PhraseComponent._(
    this.phraseCount,
    this.bars,
    this.beatsPerBar, [
    this.name,
  ]);

  /// The caller's name for this phrase (`A`, `B` or `C`), or null when the
  /// structure's phrases are not named ([PhraseStructure.isNamed]).
  final String? name;

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

  /// Whether half a bar of this component is a whole number of beats, so
  /// timing may be given in half bars (ADR-006 Q16). False in triple time.
  bool get allowsHalfBars => beatsPerBar.isEven;

  @override
  bool operator ==(Object other) =>
      other is PhraseComponent &&
      other.phraseCount == phraseCount &&
      other.bars == bars &&
      other.beatsPerBar == beatsPerBar &&
      other.name == name;

  @override
  int get hashCode => Object.hash(phraseCount, bars, beatsPerBar, name);
}

/// One named phrase of an English dance's tune ([PhraseStructure.named]).
@immutable
class NamedPhrase {
  const NamedPhrase({
    required this.name,
    required this.plays,
    required this.bars,
    required this.beatsPerBar,
  });

  /// `A`, `B` or `C` ([PhraseStructure.phraseNames]).
  final String name;

  /// How many times it plays: 1, or 2 with its repeat straight after.
  final int plays;

  /// Bars in the phrase.
  final int bars;

  /// Beats in each bar.
  final int beatsPerBar;

  @override
  bool operator ==(Object other) =>
      other is NamedPhrase &&
      other.name == name &&
      other.plays == plays &&
      other.bars == bars &&
      other.beatsPerBar == beatsPerBar;

  @override
  int get hashCode => Object.hash(name, plays, bars, beatsPerBar);

  @override
  String toString() => 'NamedPhrase($name: $plays×$bars bars of $beatsPerBar)';
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
/// A structural container figure (#590) is a single flat list element, so it
/// contributes its **shared** beats (`params['beats']`, read via [Figure.beats])
/// exactly **once** — the loop never recurses into its children, so a child's
/// own beats can never leak into the cumulative total.
///
/// Each `sequence` container, top-level or nested, whose count is longer than
/// one phrase ([sequenceExceedsPhrase]) also adds a `sequence_exceeds_phrase`
/// warning. The editor will not add a step or form a sequence past a phrase,
/// but it does not block editing a step's move or beats, or the phrase
/// structure, so this is what flags a sequence left too long.
///
/// With [checkPhraseFill], each top-level figure that runs past the end of a
/// phrase also adds a [figureCrossesPhraseCode] warning: the calls of that
/// phrase do not fill it exactly. Traditional squares are phrased call by
/// call, so ADR-007 §5.3 asks for this check on square dances; contra and
/// English dances leave it off, because a figure across a phrase line is
/// ordinary there (a balance and swing that starts mid-phrase).
List<SectionedFigure> deriveSections(
  List<Figure> figures,
  PhraseStructure structure, {
  List<ValidationIssue>? issues,
  bool checkPhraseFill = false,
}) {
  final result = <SectionedFigure>[];
  var beat = 0;
  for (var i = 0; i < figures.length; i++) {
    final startBeat = beat;
    result.add(
      SectionedFigure(
        index: i,
        figure: figures[i],
        startBeat: beat,
        label: labelForFigure(beat, figures[i].beats, structure),
      ),
    );
    if (issues != null && checkPhraseFill) {
      _flagPhraseCrossing(figures[i], i, beat, structure, issues);
    }
    // One list element → one beat advance. For a container this is the
    // shared count, counted once (no double-count from its children).
    beat += figures[i].beats;
    if (issues != null) {
      _flagLongSequences(figures[i], i, startBeat, structure, issues);
    }
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

/// The beats at which each child of [container] starts, [containerStart] being
/// the container's own start: a sequence's steps one after another, and a
/// meanwhile's sides and a modifier's parts all with the container.
List<int> childStartBeats(Figure container, int containerStart) {
  var start = containerStart;
  return [
    for (final child in container.subFigures)
      () {
        final childStart = start;
        if (container.isSequence) start += child.beats;
        return childStart;
      }(),
  ];
}

/// The [ValidationIssue.code] of a figure that runs past the end of a phrase,
/// so that phrase's calls do not fill it ([deriveSections] with
/// `checkPhraseFill`). Its data holds the figure's 1-based `position` and the
/// `label` of the phrase it runs past.
const String figureCrossesPhraseCode = 'figure_crosses_phrase';

/// Adds a [figureCrossesPhraseCode] warning when [figure], starting at
/// [start], runs past the end of a phrase: one per figure, for the first
/// phrase it crosses. A figure that ends exactly on a phrase line fills it,
/// and so does one that starts and ends on phrase lines, however many phrases
/// it takes (a 32-beat promenade from the top of A1 fills A1 and A2).
void _flagPhraseCrossing(
  Figure figure,
  int index,
  int start,
  PhraseStructure structure,
  List<ValidationIssue> issues,
) {
  final end = start + figure.beats;
  if (structure.isPhraseBoundary(start) && structure.isPhraseBoundary(end)) {
    return;
  }
  for (var b = start + 1; b < end; b++) {
    if (!structure.isPhraseBoundary(b)) continue;
    final label = structure.labelAtBeat(b - 1);
    issues.add(
      ValidationIssue(
        severity: ValidationSeverity.warning,
        code: figureCrossesPhraseCode,
        message: 'figure ${index + 1} runs past the end of $label',
        data: {'position': index + 1, 'label': label},
      ),
    );
    return;
  }
}

/// Whether [sequence], a `sequence` container, is counted longer than one
/// phrase of [structure] ([PhraseStructure.longestPhraseBeats]). False for any
/// other figure.
bool sequenceExceedsPhrase(
  Figure sequence,
  PhraseStructure structure, {
  required int startBeat,
}) => sequence.isSequence && sequence.beats > structure.longestPhraseBeats;

void _flagLongSequences(
  Figure figure,
  int index,
  int startBeat,
  PhraseStructure structure,
  List<ValidationIssue> issues,
) {
  if (sequenceExceedsPhrase(figure, structure, startBeat: startBeat)) {
    issues.add(
      ValidationIssue(
        severity: ValidationSeverity.warning,
        code: 'sequence_exceeds_phrase',
        message:
            'a sequence in figure ${index + 1} is ${figure.beats} beats; '
            'one phrase is ${structure.longestPhraseBeats}',
        data: {
          'position': index + 1,
          'actual': figure.beats,
          'limit': structure.longestPhraseBeats,
          // Where the sequence starts, and where the phrase that is the limit
          // does, so each reads in the bars of its own part of the tune. The
          // phrase's start is absent where phrases tied for longest differ in
          // bars.
          'startBeat': startBeat,
          'limitStart': ?structure.longestPhraseStart,
        },
      ),
    );
  }
  if (!figure.isContainer) return;
  final starts = childStartBeats(figure, startBeat);
  final children = figure.subFigures;
  for (var i = 0; i < children.length; i++) {
    _flagLongSequences(children[i], index, starts[i], structure, issues);
  }
}
