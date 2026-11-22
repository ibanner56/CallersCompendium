/// Bar counts in English Country Dance lines (ADR-006 W6): ECD notation
/// counts a figure in bars of the tune (`1-4 partners set and turn single`),
/// not in beats. A leading bar range is the line's count, turned into beats by
/// the dance's meter (Hudson, 19 November 2026: "the meter is the rule").
library;

import '../model/bar_timing.dart';
import '../model/phrase_structure.dart';

/// How many beats one bar of [meter] holds, and whether [meter] stated it.
///
/// A simple meter counts its top number (`2/2` is 2, `3/2` and `3/4` are 3,
/// `4/4` is 4); a compound one counts its dotted beats (`6/8` and `6/4` are 2,
/// `9/8` is 3, `12/8` is 4). A meter this cannot read, none, or meters of
/// different bars in one text count 2 beats a bar,
/// the most common ECD bar, and says so with `stated: false`.
({int beatsPerBar, bool stated}) ecdBeatsPerBar(String? meter) {
  // A text naming meters of different bars (`2/4 and 3/4`) states none: one
  // count of bars would mean different lengths in different parts.
  final counts = {
    for (final match in _meter.allMatches(meter ?? ''))
      ?_beatsPerBar(match.group(1)!, match.group(2)!),
  };
  return counts.length == 1
      ? (beatsPerBar: counts.single, stated: true)
      : (beatsPerBar: _defaultBeatsPerBar, stated: false);
}

/// The beats in a bar of `top/bottom`, or null when it is no meter.
int? _beatsPerBar(String topText, String bottomText) {
  final top = int.parse(topText);
  final bottom = int.parse(bottomText);
  if (top < 1 || top > 12 || !_noteValues.contains(bottom)) return null;
  // 6/8, 9/8 and 12/8, and the 6/4 family a Playford tune is often in.
  final compound = bottom >= 4 && top > 3 && top % 3 == 0;
  return compound ? top ~/ 3 : top;
}

/// The meter an English dance's bars are counted by: [meter] when it states
/// one ([ecdBeatsPerBar]), else the beats per bar of [structure] when its parts
/// all agree (a `4*8*3` tune is read as `3/4`), else [meter] as it is.
///
/// The meter is the rule (Hudson, 19 November 2026); the phrase structure is
/// the fallback, so the editor's bar timing and a typed or re-checked bar range
/// count a bar the same way.
String ecdMeterForBars(String? meter, PhraseStructure structure) {
  if (ecdBeatsPerBar(meter).stated) return meter!;
  final perBar = {for (final c in structure.components) c.beatsPerBar};
  // A bar of more than 12 beats has no meter to name it; the parser counts 2.
  if (perBar.length != 1 || perBar.single > 12) return meter ?? '';
  final beats = perBar.single;
  // Over a half note, 6, 9 and 12 stay simple: `6/4` would count 2 dotted
  // beats, where the structure says 6.
  return beats > 3 && beats % 3 == 0 ? '$beats/2' : '$beats/4';
}

/// The first `top/bottom` in a meter text (`3/2`, `Meter: 6/8`).
final RegExp _meter = RegExp(r'(?<![\d/])(\d{1,2})\s*/\s*(\d{1,2})(?![\d/])');

const Set<int> _noteValues = {1, 2, 4, 8, 16};

const int _defaultBeatsPerBar = 2;

/// Most bars one line's range may span: a whole 32-bar tune.
const int _maxBars = 32;

/// A line's bar ranges: how many [bars] they span, how many [firstBars] the
/// first one spans, the line's [rest] after the first one, and whether the
/// line gives [several] ranges.
typedef EcdBarRange = ({int bars, int firstBars, String rest, bool several});

/// The bar range [line] starts with, or null when it starts with none.
///
/// The range is `first-last` (a hyphen or a dash, spaces allowed), alone or in
/// brackets (`(5-8)`), and may follow a section label (`A1 1-4`, `A1&2 1-8`),
/// which is dropped: sections follow from the counts. The range spans
/// `last - first + 1` bars, at most a whole tune; a range running backwards or
/// with nothing after it is not one. A lone number is not taken for a bar,
/// since it may be part of the figure (`2 changes of rights and lefts`).
///
/// A line that goes on to further ranges, each starting the bar after the
/// one before ends (`(5-8) X (9-12) Y`), spans all of them, so its count is
/// from the first range's start to the last range's end, and [EcdBarRange.several]
/// is true. A later range that does not follow on is part of the words.
EcdBarRange? splitEcdBarRange(String line) {
  final match = _barRange.firstMatch(line);
  if (match == null) return null;
  final first = int.parse(match.group(1) ?? match.group(3)!);
  var last = int.parse(match.group(2) ?? match.group(4)!);
  if (first < 1 || last < first || last - first + 1 > _maxBars) return null;
  final rest = match.group(5)!.trim();
  if (rest.isEmpty) return null;
  final firstBars = last - first + 1;
  var several = false;
  for (final later in _laterBarRange.allMatches(rest)) {
    final from = int.parse(later.group(1) ?? later.group(3)!);
    final to = int.parse(later.group(2) ?? later.group(4)!);
    if (from != last + 1 || to < from || to - first + 1 > _maxBars) break;
    last = to;
    several = true;
  }
  return (
    bars: last - first + 1,
    firstBars: firstBars,
    rest: rest,
    several: several,
  );
}

/// A bar range later in a line, alone or in brackets, not part of a longer
/// number, a meter or a word.
final RegExp _laterBarRange = RegExp(
  r'\(\s*(\d{1,3})\s*[-–—]\s*(\d{1,3})\s*\)'
  r'|(?<![\w/.-])(\d{1,3})\s*[-–—]\s*(\d{1,3})(?![\w/]|[.-]\d)',
);

final RegExp _barRange = RegExp(
  // A section label (`A1`, `a1`, `A1&2`, `A1&A2`, `A1:`), dropped.
  r'^\s*(?:(?:[ABCD][1-4]?|[abcd][1-4])'
  r'(?:\s*&\s*[ABCDabcd]?[1-4])?\s*:?\s+)?'
  // The range, alone or in a matched pair of brackets.
  r'(?:\(\s*(\d{1,3})\s*[-–—]\s*(\d{1,3})\s*\)|(\d{1,3})\s*[-–—]\s*(\d{1,3}))'
  r'(?:\s*[:.,]\s*|\s+)'
  r'(\S.*)$',
  dotAll: true,
);

/// [line]'s bar ranges as a count: their bars times the beats in a bar of
/// [meter], the line's rest after the first range, and whether it gave
/// [several] ranges ([splitEcdBarRange]). Null when [line] starts with no
/// range, or its count would be over 64 beats.
///
/// A line of several ranges names several figures, so the parsers keep it
/// whole as text, with the count of all its ranges; when that would be over
/// 64 beats, with its first range's count, as a line of one range would be.
({int beats, String rest, bool several})? ecdBarCount(
  String line, {
  String? meter,
  BarTiming? timing,
  int startBeat = 0,
}) {
  final range = splitEcdBarRange(line);
  if (range == null) return null;
  final perBar = ecdBeatsPerBar(meter).beatsPerBar;
  var beats = range.bars * perBar;
  // Ranges that run past the beats range keep the first one's count.
  if (beats > _maxBeats) beats = range.firstBars * perBar;
  if (beats > _maxBeats) return null;
  return (beats: beats, rest: range.rest, several: range.several);
}

/// Whether [rest], a line after its bar range, also states a count in beats:
/// bracketed (`(8)`, `[8]`, a compound `(4,4)` or `(4+4)`) or with `beats`
/// (`8 beats`). The bars are the
/// count, so such a line is kept whole as text, its words unchanged, with the
/// bars' count (Hudson: "the meter is the rule").
bool ecdRestStatesBeats(String rest) => _statedBeats.hasMatch(rest);

final RegExp _statedBeats = RegExp(
  r'[(\[]\s*\d+(?:\s*[,+]\s*\d+)*\s*(?:beats?\s*)?[)\]]|\b\d+\s*beats?\b',
  caseSensitive: false,
);

/// The figure beats range's top (`ParamKind.beats`).
const int _maxBeats = 64;

/// The beats every count [line] states adds up to: each bracketed count in
/// beats (`(8)`, a compound `(4,4)`), and each bar range (`1-4`, `(5-8)`) at
/// [beatsPerBar] beats a bar. Used to tell whether a section's figures count
/// all of its lines' counts ([EcdSectionBeats.counted]).
int ecdStatedBeats(String line, int beatsPerBar) {
  var beats = 0;
  for (final match in _statedCount.allMatches(line)) {
    final range = match.group(2);
    if (range != null) {
      final first = int.parse(range);
      final last = int.parse(match.group(3)!);
      if (last >= first) beats += (last - first + 1) * beatsPerBar;
    } else {
      for (final part in match.group(1)!.split(RegExp(r'[,+]'))) {
        beats += int.parse(part.trim());
      }
    }
  }
  return beats;
}

/// A bracketed count in beats, or a bar range alone or in brackets, not part
/// of a longer number, a meter or a word.
final RegExp _statedCount = RegExp(
  r'\(\s*(\d{1,3}(?:\s*[,+]\s*\d{1,3})*)\s*\)'
  r'|(?<![\w/.-])\(?\s*(\d{1,3})\s*[-–—]\s*(\d{1,3})\s*\)?(?![\w/]|[.-]\d)',
);

/// One section of an English dance as its source lays it out: its [label]
/// (`A1`, `B`, or null), the beats its figures count, and whether they are
/// [counted]: they add up to every count its lines state ([ecdStatedBeats]),
/// so none was lost in a line kept as text.
typedef EcdSectionBeats = ({String? label, int beats, bool counted});

/// The phrase structure an imported English dance takes (Hudson, 20 November
/// 2026): its named phrases when its [sections] give them, else one that
/// counts [beatsPerBar] beats a bar when its meter is [meterStated] and that
/// is not 2, else the standard structure (`''`).
///
/// [sections] give named phrases when every one is labeled `A`, `B` or `C`,
/// alone or numbered `1` then `2` (`A1 A2 B1`, `A B C`), each letter's
/// sections together and in order, each played at most twice; and each
/// section's figures are all counted, to a whole number of bars at
/// [beatsPerBar]. A letter played twice counts the same bars both times. A
/// section that counts no bars (only a line such as "repeat to places") names
/// no phrases, because the figures after it would be labeled a phrase too
/// early. So
/// `A1 A2 B1` of 8, 8 and 16 bars is `A:2*8*2 + B:1*16*2` in 2/2. Named
/// phrases that are just A and B of 8 bars, each played twice, are the
/// unnamed structure instead.
String ecdPhraseStructureFor(
  List<EcdSectionBeats> sections, {
  required int beatsPerBar,
  required bool meterStated,
}) {
  final unnamed = meterStated && beatsPerBar != 2 ? '4*8*$beatsPerBar' : '';
  final named = _namedPhrasesFor(sections, beatsPerBar);
  // A1 A2 B1 B2 of 8 bars each is the structure the meter gives anyway, so
  // it stays unnamed: older builds read it, and cards don't print it.
  if (named != null && !_isStandardShape(named)) {
    try {
      return PhraseStructure.named(named).raw;
    } on FormatException {
      // diagnostics: silent — phrases past the structure's bounds fall back
      // to the meter's structure below.
    }
  }
  return unnamed;
}

List<NamedPhrase>? _namedPhrasesFor(
  List<EcdSectionBeats> sections,
  int beatsPerBar,
) {
  if (sections.isEmpty) return null;
  final phrases = <NamedPhrase>[];
  for (final section in sections) {
    final match = _sectionLabel.firstMatch(section.label?.trim() ?? '');
    if (match == null) return null;
    final name = match.group(1)!;
    final number = match.group(2);
    if (section.beats % beatsPerBar != 0) return null;
    final bars = section.beats ~/ beatsPerBar;
    // A section of bars it can't fully count gives no phrase length, and one
    // of no bars would shift every later figure's label.
    if (bars == 0 || !section.counted) return null;
    final last = phrases.isEmpty ? null : phrases.last;
    if (last != null && last.name == name) {
      // The repeat: `A2` after `A1`, of the same bars.
      if (number != '2' || last.plays != 1) return null;
      if (bars != last.bars) return null;
      phrases[phrases.length - 1] = NamedPhrase(
        name: name,
        plays: 2,
        bars: last.bars,
        beatsPerBar: beatsPerBar,
      );
      continue;
    }
    if (number == '2') return null;
    if (phrases.any((p) => p.name == name)) return null;
    phrases.add(
      NamedPhrase(name: name, plays: 1, bars: bars, beatsPerBar: beatsPerBar),
    );
  }
  return phrases;
}

/// Whether [phrases] are A and B, each of 8 bars played twice: the labels
/// and lengths of the standard structure at their beats per bar.
bool _isStandardShape(List<NamedPhrase> phrases) =>
    phrases.length == 2 &&
    phrases[0].name == 'A' &&
    phrases[1].name == 'B' &&
    phrases.every((p) => p.plays == 2 && p.bars == 8);

/// A section label naming a phrase: `A`, `B` or `C`, alone or numbered.
final RegExp _sectionLabel = RegExp(r'^([ABC])([12])?$');
