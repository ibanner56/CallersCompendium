import 'package:meta/meta.dart';

import 'phrase_structure.dart';

/// How an English dance's bars are counted when its phrases differ in beats
/// per bar (ADR-006 §5.5; #2303): each bar is as long as the phrase it starts
/// in, and a figure's bars are counted from where the figure starts.
@immutable
class BarTiming {
  /// One bar length everywhere.
  const BarTiming.fixed(int beatsPerBar)
    : _fixed = beatsPerBar,
      _structure = null;

  /// Each bar as long as the phrase of [structure] it starts in.
  const BarTiming.byPhrase(PhraseStructure structure)
    : _structure = structure,
      _fixed = null;

  final int? _fixed;
  final PhraseStructure? _structure;

  /// Beats in the bar that starts at [beat].
  int beatsPerBarAt(int beat) =>
      _fixed ?? _structure!.componentAtBeat(beat).beatsPerBar;

  /// Beats in [halfBars] half bars counted from [start], or null where the
  /// half bar is not a whole number of beats.
  ///
  /// Each whole bar is as long as the phrase it starts in, so a count that
  /// runs across a change of meter is the sum of its own bars. A trailing half
  /// bar is taken only where that bar has an even number of beats (ADR-006
  /// Q16). Bars are counted from [start] itself, which need not be on a bar
  /// line: a dance in one meter counts the same from anywhere. [start] past the
  /// end of the structure wraps, as phrase labels do.
  int? beatsForHalfBars(int start, int halfBars) {
    if (start < 0) throw ArgumentError.value(start, 'start', 'must be >= 0');
    if (halfBars < 0) {
      throw ArgumentError.value(halfBars, 'halfBars', 'must be >= 0');
    }
    var position = start;
    for (var bar = 0; bar < halfBars ~/ 2; bar++) {
      position += beatsPerBarAt(position);
    }
    if (halfBars.isOdd) {
      final perBar = beatsPerBarAt(position);
      if (perBar.isOdd) return null;
      position += perBar ~/ 2;
    }
    return position - start;
  }

  /// [beats] counted from [start] as bars: the count as written (`4`, `1½`,
  /// `½`) and the same count in half bars, which picks a plural. Null where
  /// the beats are not a whole number of half bars, which then read as beats.
  ///
  /// The inverse of [beatsForHalfBars]; with one bar length it is the count
  /// `barsText` gives.
  ({String text, int halfBars})? barsTextAt(int start, int beats) {
    if (start < 0) throw ArgumentError.value(start, 'start', 'must be >= 0');
    if (beats < 0) throw ArgumentError.value(beats, 'beats', 'must be >= 0');
    final end = start + beats;
    var position = start;
    var whole = 0;
    while (position + beatsPerBarAt(position) <= end) {
      position += beatsPerBarAt(position);
      whole++;
    }
    final rest = end - position;
    if (rest == 0) return (text: '$whole', halfBars: whole * 2);
    final perBar = beatsPerBarAt(position);
    if (perBar.isOdd || rest * 2 != perBar) return null;
    return (text: whole == 0 ? '½' : '$whole½', halfBars: whole * 2 + 1);
  }

  @override
  bool operator ==(Object other) =>
      other is BarTiming &&
      other._fixed == _fixed &&
      other._structure == _structure;

  @override
  int get hashCode => Object.hash(_fixed, _structure);
}
