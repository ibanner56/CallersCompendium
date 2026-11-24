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
/// Only `where: across` with partnered pairs is modelled. A single-file
/// promenade, any other `where`, and a stated `destination` raise
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

  /// Where the pairs travel. Only `across` is modelled.
  final String where;

  /// The wheel's sense. A 180° wheel lands the same either way — as for
  /// [CourtesyTurn] — so it has no positional effect and is carried for
  /// fidelity.
  final SpinDirection direction;

  /// A single-file promenade: dancers one behind another, not in pairs.
  /// Deferred.
  final bool singleFile;

  /// Whom the pairs travel to, when the source says. `null` is the upstream
  /// `unspecified` sentinel. A stated destination is deferred: it names travel
  /// past the hands four, which this landing does not model.
  final WhoSet? destination;

  @override
  String get name => 'promenade';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  OpError? checkPreconditions(Formation formation) {
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
  Result<Formation, OpError> perform(Formation formation) =>
      Ok(_tradeDiagonallyFacingIn(formation));

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
