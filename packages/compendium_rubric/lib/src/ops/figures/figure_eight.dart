part of '../operation.dart';

/// Which way a `figure_8` traces its first loop.
///
/// Path and styling only: the loop is symmetric, so the order the two lobes are
/// danced in does not change where anyone lands. `across` is deferred.
enum FigureEightDir {
  none('none'),
  above('above'),
  below('below'),
  across('across');

  const FigureEightDir(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static FigureEightDir? fromKey(String key) {
    for (final value in FigureEightDir.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// `figure_8` — the `who` couple weaves a figure-eight path around the other,
/// stationary couple.
///
/// The weave is a *path*, and the compiler models landings, so almost every
/// parameter here is inert. What survives is the fraction: a full eight is a
/// closed loop and therefore literally a no-op, while a half leaves the two
/// actives swapped **within their own row**. The inactive couple never moves at
/// either fraction.
///
/// No progression is baked in. A half eight returns the actives to their own
/// row rather than moving them to new neighbors, so any progression must come
/// from the dance's explicit flag.
final class FigureEight extends Operation {
  const FigureEight({
    this.who = WhoSet.ones,
    this.dir = FigureEightDir.none,
    this.lead,
    this.half = TurnFraction.half,
  });

  /// The active couple that weaves.
  final WhoSet who;

  /// Which lobe is traced first. Path only; no net effect.
  final FigureEightDir dir;

  /// The single dancer who leads the weave. Purely descriptive, and outside our
  /// `who` vocabulary (`onesRole1` and friends name one dancer, not a set), so
  /// it is carried verbatim.
  final String? lead;

  /// How far around. Only `half` and `full` are implemented.
  final TurnFraction half;

  @override
  String get name => 'figure_8';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  /// Whether this is the half — the only fraction that moves anyone.
  bool get _isHalf => half == TurnFraction.half;

  @override
  OpError? checkPreconditions(Formation formation) {
    if (dir == FigureEightDir.across) {
      return const OpError(
        ErrorKind.unsupportedParam,
        'figure_8 dir:across is deferred as degenerate',
      );
    }
    if (half != TurnFraction.half && half != TurnFraction.full) {
      return OpError(
        ErrorKind.unsupportedParam,
        'figure_8 is defined at a half or a full weave; half:${half.key} is '
        'neither',
      );
    }

    final pairs = whoPairsInSet(formation, who);
    for (final pair in pairs) {
      final band = handsFourBandContaining(
        formation,
        formation.stateOf(pair.a).row,
      );
      // The actives weave *around* the other couple, so that couple has to be
      // there: an incomplete hands four has no still centre to weave about.
      if (band != null && bandIsComplete(formation, band)) continue;
      return OpError(
        ErrorKind.unresolvableDancerSet,
        'figure_8 needs a completed hands four to weave around, but the band '
        'holding ${pair.a} and ${pair.b} is not full',
      );
    }
    return null;
  }

  @override
  Result<Formation, OpError> perform(Formation formation) => Ok(
    _isHalf ? swapPairs(formation, whoPairsInSet(formation, who)) : formation,
  );

  @override
  bool operator ==(Object other) =>
      other is FigureEight &&
      other.who == who &&
      other.dir == dir &&
      other.lead == lead &&
      other.half == half;

  @override
  int get hashCode => Object.hash(name, who, dir, lead, half);

  @override
  String toString() => 'figure_8(${who.key}, half: ${half.key})';
}
