part of '../operation.dart';

/// `promenade` across — each `who` pair, side by side on one side of the
/// hands four, walks across together, passes the other pair by the left
/// shoulder, and wheels as a couple to face back in (`docs/taxonomy.md`).
///
/// **The landing is a right and left through's** (user-ruled 2026-11-22). The
/// wheel is a half turn about the couple's own centre, so the dancer who
/// crossed on the top row lands on the bottom one, and every dancer ends
/// diagonally across the hands four, facing in. Positions and facings are
/// [_tradeDiagonallyFacingIn], shared with [RightLeftThrough].
///
/// `where: across` with partnered pairs is modelled, and so is a single-file
/// promenade `along` the set to the next neighbours (user-ruled 2026-11-24;
/// its `destination` says how far it travels, user-ruled 2026-11-25): every
/// dancer walks one place around the outside of the whole set, which lands
/// exactly as a
/// [SlideAlongSet] does, clockwise as a slide left and counterclockwise as a
/// slide right, and like the slide is its own progression. It ends with every
/// dancer facing across, toward the next neighbours, as the ruling says; the
/// slide alone would keep their facing. Any other single file or `where`,
/// an along-the-set promenade to anyone but the next neighbours or to no one
/// stated, and any other stated `destination`, raise
/// [ErrorKind.unsupportedParam]. A Caller's Box promenade that states no
/// `where` (a whole-set or around-a-dancer promenade there) is stopped before
/// it reaches this operation and reported as `unstructured`, an import
/// problem, by `runCoreDance` (`io/callersbox_source.dart`).
final class Promenade extends Operation {
  const Promenade({
    this.who = WhoSet.partners,
    this.where = 'across',
    this.direction = SpinDirection.counterclockwise,
    this.singleFile = false,
    this.destination,
  });

  /// The pairs that promenade together. Each must stand side by side in one
  /// side column of its hands four.
  final WhoSet who;

  /// Where the pairs travel: `across`, or `along` for a single-file
  /// promenade. Nothing else is modelled.
  final String where;

  /// The wheel's sense. A 180° wheel lands the same either way — as for
  /// [CourtesyTurn] — so it has no positional effect and is carried for
  /// fidelity.
  final SpinDirection direction;

  /// A single-file promenade: dancers one behind another, not in pairs.
  /// Modelled only `along` the set.
  final bool singleFile;

  /// Whom the pairs travel to, when the source says. `null` is the upstream
  /// `unspecified` sentinel. On a single-file promenade along the set it says
  /// how far the dancers travel *(user-ruled 2026-11-25)*: `nextNeighbors` is
  /// one place. Any other destination is deferred, and so is a promenade
  /// along the set that names none, whose distance is unknown. Elsewhere a
  /// stated destination names travel past the hands four, which this landing
  /// does not model, and is deferred.
  final WhoSet? destination;

  @override
  String get name => 'promenade';

  @override
  Iterable<WhoSet?> get dancerSets => _aroundTheSet ? const [] : [who];

  /// A single-file promenade along the set: every dancer walks one place
  /// around the outside of the whole set.
  bool get _aroundTheSet => singleFile && where == 'along';

  SlideAlongSet get _asSlide => SlideAlongSet(
    slide: direction == SpinDirection.counterclockwise
        ? SlideDirection.right
        : SlideDirection.left,
  );

  @override
  int get hands4Contribution => _aroundTheSet ? 1 : 0;

  @override
  bool get progressionEligible => _aroundTheSet;

  @override
  bool get isItsOwnProgression => _aroundTheSet;

  @override
  OpError? checkPreconditions(Formation formation) {
    if (_aroundTheSet) {
      // "Single file promenade … around the major set to N2": the
      // destination says how far the dancers travel (user-ruled 2026-11-25),
      // and the next neighbours are one place. Another destination ("two
      // places", "to partner", N3) is deferred, and so is a promenade that
      // names none, which may go all the way round or out and back (agent's
      // call).
      if (destination == null) {
        return const OpError(
          ErrorKind.unsupportedParam,
          'a single-file promenade along the set with no destination is '
          'deferred: how far it travels is unknown',
        );
      }
      if (destination != WhoSet.nextNeighbors) {
        return OpError(
          ErrorKind.unsupportedParam,
          'a promenade to ${destination!.key} is deferred',
        );
      }
      return _asSlide.checkPreconditions(formation);
    }
    if (singleFile) {
      return const OpError(
        ErrorKind.unsupportedParam,
        'a single-file promenade is deferred',
      );
    }
    if (where != 'across') {
      return OpError(
        ErrorKind.unsupportedParam,
        'promenade supports where:across only; where:$where is deferred',
      );
    }
    if (destination != null) {
      return OpError(
        ErrorKind.unsupportedParam,
        'a promenade to ${destination!.key} is deferred',
      );
    }
    for (final band in handsFourBands(formation)) {
      // Each side column must hold a pair [who] names, side by side. Read
      // column by column rather than from [resolveWhoPairs], whose first-match
      // pairing can take a dancer into a pair across the set first.
      final paired = [
        for (final col in const [0, kColumnCount - 1])
          if (formation.dancerAt(Position(band.topRow, col)) case final a?)
            if (formation.dancerAt(Position(band.bottomRow, col)) case final b?)
              if (whoMatches(formation, a, b, who)) col,
      ];
      if (paired.length != 2) {
        return OpError(
          ErrorKind.whoMismatch,
          'promenade across needs each side of the hands four (rows '
          '${band.topRow}-${band.bottomRow}) to hold one ${who.key} pair side '
          'by side',
        );
      }
    }
    return null;
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    if (!_aroundTheSet) return Ok(_tradeDiagonallyFacingIn(formation));
    return switch (_asSlide.perform(formation)) {
      Ok(:final value) => Ok(_facingAcross(value)),
      final Err<Formation, OpError> err => err,
    };
  }

  /// [formation] with every side-column dancer facing across the set: the
  /// promenade around the set ends facing the next neighbours (user-ruled
  /// 2026-11-24), which the slide alone would leave as it found them.
  static Formation _facingAcross(Formation formation) => formation.withUpdates({
    for (final MapEntry(:key, :value) in formation.dancers.entries)
      if (value.position.col == 0)
        key: value.copyWith(facing: Facing.acrossEast)
      else if (value.position.col == kColumnCount - 1)
        key: value.copyWith(facing: Facing.acrossWest),
  });

  @override
  bool operator ==(Object other) =>
      other is Promenade &&
      other.who == who &&
      other.where == where &&
      other.direction == direction &&
      other.singleFile == singleFile &&
      other.destination == destination;

  @override
  int get hashCode =>
      Object.hash(name, who, where, direction, singleFile, destination);

  @override
  String toString() =>
      'promenade(${who.key}, $where, ${direction.key}'
      '${singleFile ? ', singleFile' : ''}'
      '${destination == null ? '' : ', to ${destination!.key}'})';
}
