/// Bar counts in English Country Dance lines (ADR-006 W6): ECD notation
/// counts a figure in bars of the tune (`1-4 partners set and turn single`),
/// not in beats. A leading bar range is the line's count, turned into beats by
/// the dance's meter (Hudson, 19 November 2026: "the meter is the rule").
library;

import '../model/phrase_structure.dart';

/// How many beats one bar of [meter] holds, and whether [meter] stated it.
///
/// A simple meter counts its top number (`2/2` is 2, `3/2` and `3/4` are 3,
/// `4/4` is 4); a compound one counts its dotted beats (`6/8` is 2, `9/8` is
/// 3, `12/8` is 4). A meter this cannot read, or none, counts 2 beats a bar,
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
  final compound = bottom >= 8 && top > 3 && top % 3 == 0;
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
  return perBar.length == 1 ? '${perBar.single}/4' : (meter ?? '');
}

/// The first `top/bottom` in a meter text (`3/2`, `Meter: 6/8`).
final RegExp _meter = RegExp(r'(?<!\d)(\d{1,2})\s*/\s*(\d{1,2})(?!\d)');

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
  final first = int.parse(match.group(1)!);
  final last = int.parse(match.group(2)!);
  if (first < 1 || last < first || last - first + 1 > _maxBars) return null;
  final rest = match.group(3)!.trim();
  if (rest.isEmpty) return null;
  return (bars: last - first + 1, rest: rest);
}

final RegExp _barRange = RegExp(
  r'^\s*(?:[ABCD][1-4]?(?:\s*&\s*[1-4])?\s+)?'
  r'\(?\s*(\d{1,3})\s*[-–—]\s*(\d{1,3})\s*\)?'
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

/// The figure beats range's top (`ParamKind.beats`).
const int _maxBeats = 64;
