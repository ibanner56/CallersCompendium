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
  int? beatsForHalfBars(int start, int halfBars) {
    // Red-run stub: one bar length for the whole count.
    final doubled = halfBars * beatsPerBarAt(0);
    return doubled.isEven ? doubled ~/ 2 : null;
  }

  /// [beats] counted from [start] as bars, or null where they are not a whole
  /// number of half bars.
  ({String text, int halfBars})? barsTextAt(int start, int beats) => null;

  @override
  bool operator ==(Object other) =>
      other is BarTiming &&
      other._fixed == _fixed &&
      other._structure == _structure;

  @override
  int get hashCode => Object.hash(_fixed, _structure);
}
