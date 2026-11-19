/// Bar counts in English Country Dance lines (ADR-006 W6): ECD notation
/// counts a figure in bars of the tune (`1-4 partners set and turn single`),
/// not in beats. A leading bar range is the line's count, turned into beats by
/// the dance's meter (Hudson, 19 November 2026: "the meter is the rule").
library;

import '../model/phrase_structure.dart';

/// How many beats one bar of [meter] holds, and whether [meter] stated it.
///
/// A simple meter counts its top number (`2/2` is 2, `3/2` and `3/4` are 3,
/// `4/4` is 4); a compound one counts its dotted beats (`6/8` and `6/4` are 2,
/// `9/8` is 3, `12/8` is 4). A meter this cannot read, or none, counts 2 beats a bar,
/// the most common ECD bar, and says so with `stated: false`.
({int beatsPerBar, bool stated}) ecdBeatsPerBar(String? meter) {
  final match = _meter.firstMatch(meter ?? '');
  final top = int.tryParse(match?.group(1) ?? '');
  final bottom = int.tryParse(match?.group(2) ?? '');
  if (top == null || bottom == null || top < 1 || top > 12) {
    return (beatsPerBar: _defaultBeatsPerBar, stated: false);
  }
  if (!_noteValues.contains(bottom)) {
    return (beatsPerBar: _defaultBeatsPerBar, stated: false);
  }
  // 6/8, 9/8 and 12/8, and the 6/4 family a Playford tune is often in.
  final compound = bottom >= 4 && top > 3 && top % 3 == 0;
  return (beatsPerBar: compound ? top ~/ 3 : top, stated: true);
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

/// A line's leading bar range: how many [bars] it spans, and the line's
/// [rest] after it.
typedef EcdBarRange = ({int bars, String rest});

/// The bar range [line] starts with, or null when it starts with none.
///
/// The range is `first-last` (a hyphen or a dash, spaces allowed), alone or in
/// brackets (`(5-8)`), and may follow a section label (`A1 1-4`, `A1&2 1-8`),
/// which is dropped: sections follow from the counts. The range spans
/// `last - first + 1` bars, at most a whole tune; a range running backwards or
/// with nothing after it is not one. A lone number is not taken for a bar,
/// since it may be part of the figure (`2 changes of rights and lefts`).
EcdBarRange? splitEcdBarRange(String line) {
  final match = _barRange.firstMatch(line);
  if (match == null) return null;
  final first = int.parse(match.group(1) ?? match.group(3)!);
  final last = int.parse(match.group(2) ?? match.group(4)!);
  if (first < 1 || last < first || last - first + 1 > _maxBars) return null;
  final rest = match.group(5)!.trim();
  if (rest.isEmpty) return null;
  return (bars: last - first + 1, rest: rest);
}

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

/// [line]'s leading bar range as a count: its bars times the beats in a bar
/// of [meter], and the line's rest. Null when [line] starts with no range, or
/// its count would be over 64 beats.
({int beats, String rest})? ecdBarCount(String line, {String? meter}) {
  final range = splitEcdBarRange(line);
  if (range == null) return null;
  final beats = range.bars * ecdBeatsPerBar(meter).beatsPerBar;
  if (beats > _maxBeats) return null;
  return (beats: beats, rest: range.rest);
}

/// Whether [rest], a line after its bar range, also states a count in beats:
/// bracketed (`(8)`, `[8]`) or with `beats` (`8 beats`). The bars are the
/// count, so such a line is kept whole as text, its words unchanged, with the
/// bars' count (Hudson: "the meter is the rule").
bool ecdRestStatesBeats(String rest) => _statedBeats.hasMatch(rest);

final RegExp _statedBeats = RegExp(
  r'[(\[]\s*\d+\s*(?:beats?\s*)?[)\]]|\b\d+\s*beats?\b',
  caseSensitive: false,
);

/// The figure beats range's top (`ParamKind.beats`).
const int _maxBeats = 64;
