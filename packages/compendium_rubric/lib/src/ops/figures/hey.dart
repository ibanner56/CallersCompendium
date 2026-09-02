part of '../operation.dart';

/// How much of the weave a `hey` dances.
///
/// The two partial lengths are represented but not implemented: they stop the
/// weave mid-pass, with two dancers standing in the middle of the set rather
/// than in the corners the matrix is defined over (`docs/fundamentals.md` §8).
/// Representing them is what lets the refusal say "valid but out of scope"
/// rather than "malformed", the same stance [Direction] takes.
enum HeyLength {
  lessThanHalf('lessThanHalf'),
  half('half'),
  betweenHalfAndFull('betweenHalfAndFull'),
  full('full');

  const HeyLength(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  /// How many times each pair meets in the centre over this length.
  ///
  /// A half hey is four passes: the centres meet, everyone passes at the ends,
  /// the *other* pair meets in the centre, and everyone passes at the ends
  /// again. So each pair meets once. A full hey is that twice over, hence two
  /// meetings each. Only consulted for the supported lengths — the partial ones
  /// are refused before this is read.
  int get centerMeetingsPerPair => this == HeyLength.full ? 2 : 1;

  static HeyLength? fromKey(String key) {
    for (final value in HeyLength.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// One hands four read as the line of four a hey weaves along.
typedef _HeyLine = ({DancerPair centers, DancerPair ends});

/// `hey` — a reel of four, in which the dancers weave past each other without
/// taking hands (`docs/taxonomy.md`).
///
/// ## The permutation, derived
///
/// A hey for four is a **reel of four**, and a reel is not a sequence of pair
/// exchanges — composing four literal pair swaps gives the identity, which is
/// plainly wrong for a half hey. Each pass instead *advances* a dancer one
/// place along the line. Numbering the line `[end, centre, centre, end]` as
/// `[a, b, c, d]` and walking the four passes of a half hey:
///
/// 1. the centres `b, c` meet and pass    → `a c b d`
/// 2. each pair at the ends passes        → `c a d b`
/// 3. `a, d` — now the centres — pass     → `c d a b`
/// 4. each pair at the ends passes        → `d c b a`
///
/// The line ends **reversed**. Reversal maps position 1 ↔ 4 and 2 ↔ 3, so an
/// end lands on the other end and a centre on the other centre: **each pair
/// exchanges places within its own slot**, and nobody moves between the centre
/// and the ends. A full hey is that twice, which is the identity.
///
/// Mapped onto the matrix, an across-the-set line of four runs
/// `west-outer, west-inner | east-inner, east-outer`. The two dancers standing
/// *inner* are whichever pair [pass1] names — that is the whole content of the
/// parameter — so they must be one in each side column. The remaining two are
/// the ends by construction, which is why [pass2] can only ever corroborate.
///
/// This is deliberately **state-dependent** rather than a fixed permutation.
/// From a Duple Improper start with `pass1: role2s` the Robins are diagonally
/// opposite, so the figure reads as the familiar same-role diagonal swap; had
/// the named pair been standing across a rank instead, the identical rule
/// yields a within-rank exchange. Hard-coding the Duple Improper answer would
/// have been wrong everywhere else in the set.
///
/// ## Ricochets
///
/// A ricochet is a *suppressed* centre meeting: the pair approach, bump, and
/// return the way they came instead of passing through. Re-walking the reel
/// with pass 1 suppressed gives `a b c d` → `d b c a` — the ends traded and the
/// centres did not — so suppressing a meeting is exactly "that pair does not
/// exchange". The flags are numbered by centre meeting, and *who* meets in the
/// centre alternates: [rico1] and [rico3] are the [pass1] pair's two meetings,
/// [rico2] and [rico4] the end pair's.
///
/// Because an exchange is an involution, two unsuppressed meetings cancel. Each
/// pair therefore ends swapped exactly when it met an **odd** number of times,
/// which is why a plain full hey is the identity and why [rico3] and [rico4]
/// have nothing to refer to below a full hey — a half has only one meeting per
/// pair — and are refused rather than ignored.
final class HeyForFour extends Operation {
  const HeyForFour({
    this.pass1 = WhoSet.role2s,
    this.length = HeyLength.half,
    this.pass2,
    this.meetTarget,
    this.shoulder = Hand.right,
    this.dir = Direction.across,
    this.rico1 = false,
    this.rico2 = false,
    this.rico3 = false,
    this.rico4 = false,
  });

  /// The pair who begin in the centre, and so take the first centre meeting.
  final WhoSet pass1;

  /// How much of the weave is danced.
  final HeyLength length;

  /// The pair who begin at the ends.
  ///
  /// An **anchor**, on the [FormLongWaves] precedent: once [pass1] is resolved
  /// the ends are simply whoever is left, so a stated [pass2] cannot select
  /// anybody. It is checked against the pair the figure derived and reported
  /// through [WarningKind.anchorMismatch] when the two disagree.
  final WhoSet? pass2;

  /// Who the [pass1] pair are to meet when the weave stops part way.
  ///
  /// Meaningful only for the partial lengths, which are deferred, so this is
  /// carried for record fidelity and has no end-state effect.
  final WhoSet? meetTarget;

  /// Which shoulder passes. Styling; no positional effect, as for [PassBy].
  final Hand shoulder;

  /// The axis the line of four lies along. Only `across` is implemented.
  final Direction dir;

  /// The [pass1] pair ricochet at their first centre meeting.
  final bool rico1;

  /// The end pair ricochet at their first centre meeting.
  final bool rico2;

  /// The [pass1] pair ricochet at their second centre meeting (full hey only).
  final bool rico3;

  /// The end pair ricochet at their second centre meeting (full hey only).
  final bool rico4;

  @override
  String get name => 'hey';

  @override
  Iterable<WhoSet?> get dancerSets => [pass1];

  @override
  bool get progressionEligible => true;

  @override
  OpError? checkPreconditions(Formation formation) {
    if (dir != Direction.across) {
      return OpError(
        ErrorKind.unsupportedParam,
        'hey supports dir:across only; ${dir.key} lays the line of four across '
        'more than one hands four, and is deferred behind the diagonal '
        'right_left_through it would have to agree with',
      );
    }
    if (length == HeyLength.lessThanHalf ||
        length == HeyLength.betweenHalfAndFull) {
      return OpError(
        ErrorKind.unsupportedParam,
        'hey length:${length.key} stops the weave mid-pass, with dancers '
        'standing in the middle of the set rather than in the corners the '
        'matrix is defined over',
      );
    }
    if ((rico3 || rico4) && length != HeyLength.full) {
      return OpError(
        ErrorKind.unsupportedParam,
        'hey length:${length.key} gives each pair one centre meeting, so '
        '${rico3 ? 'rico3' : 'rico4'} names a meeting that never happens; only '
        'a full hey has a second one',
      );
    }
    return _lines(formation).errorOrNull;
  }

  /// Reads each hands four as a line of four, or explains why it cannot be.
  Result<List<_HeyLine>, OpError> _lines(Formation formation) {
    final lines = <_HeyLine>[];
    for (final band in handsFourBands(formation)) {
      final where = 'the hands four at rows ${band.topRow}-${band.bottomRow}';
      final centers = resolveWhoPairs(
        formation,
        pass1,
        topRow: band.topRow,
        bottomRow: band.bottomRow,
      );
      if (centers.length != 1) {
        return Err<List<_HeyLine>, OpError>(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'hey needs pass1 to name the one pair standing in the centre, but '
            '${pass1.key} names ${centers.length} pairs in $where',
          ),
        );
      }
      final middle = centers.single;
      if (formation.stateOf(middle.a).position.col ==
          formation.stateOf(middle.b).position.col) {
        return Err<List<_HeyLine>, OpError>(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'hey needs the ${pass1.key} pair one on each side of the set to '
            'meet in the centre, but ${middle.a} and ${middle.b} are standing '
            'in the same line in $where',
          ),
        );
      }
      final rest = [
        for (final id in [
          ...formation.dancersInRow(band.topRow),
          ...formation.dancersInRow(band.bottomRow),
        ])
          if (id != middle.a && id != middle.b) id,
      ];
      if (rest.length != 2) {
        return Err<List<_HeyLine>, OpError>(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'hey is a figure for four, but $where holds ${rest.length + 2} '
            'dancers, so there is no line of four to weave along',
          ),
        );
      }
      lines.add((centers: middle, ends: (a: rest.first, b: rest.last)));
    }
    if (lines.isEmpty) {
      return Err<List<_HeyLine>, OpError>(
        const OpError(
          ErrorKind.unresolvableDancerSet,
          'hey found no complete hands four to weave in',
        ),
      );
    }
    return Ok<List<_HeyLine>, OpError>(lines);
  }

  @override
  Iterable<Warning> lint(Formation formation) {
    final anchor = pass2;
    if (anchor == null) return const [];
    final lines = _lines(formation).valueOrNull;
    if (lines == null) return const [];
    for (final line in lines) {
      if (whoMatches(formation, line.ends.a, line.ends.b, anchor)) continue;
      return [
        Warning(
          WarningKind.anchorMismatch,
          detail:
              'hey says the ends pair are the ${anchor.key}, but with '
              '${pass1.key} in the centre the ends are ${line.ends.a} and '
              '${line.ends.b}, who are not. The hey still weaves as pass1 '
              'describes it; only the second pass is misdescribed',
        ),
      ];
    }
    return const [];
  }

  /// Whether a pair ends exchanged, given how many of its centre meetings were
  /// ricocheted away.
  ///
  /// An exchange is an involution, so it is the **parity** of the meetings that
  /// actually happened that survives, not their count.
  bool _exchanges(List<bool> ricochets) {
    final met = length.centerMeetingsPerPair;
    var happened = 0;
    for (var i = 0; i < met; i++) {
      if (!ricochets[i]) happened++;
    }
    return happened.isOdd;
  }

  /// Places [pair], exchanged or not, and hands their facing to the next
  /// figure: a hey ends mid-flow, and what a dancer is looking at depends on
  /// what is called next (`docs/fundamentals.md` §6).
  void _place(
    Formation formation,
    Map<DancerId, DancerState> changes,
    DancerPair pair, {
    required bool exchange,
  }) {
    final stateA = formation.stateOf(pair.a);
    final stateB = formation.stateOf(pair.b);
    changes[pair.a] = stateA.copyWith(
      position: exchange ? stateB.position : stateA.position,
      facing: Facing.flexible,
    );
    changes[pair.b] = stateB.copyWith(
      position: exchange ? stateA.position : stateB.position,
      facing: Facing.flexible,
    );
  }

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      _lines(formation).map((lines) {
        final changes = <DancerId, DancerState>{};
        for (final line in lines) {
          _place(
            formation,
            changes,
            line.centers,
            exchange: _exchanges([rico1, rico3]),
          );
          _place(
            formation,
            changes,
            line.ends,
            exchange: _exchanges([rico2, rico4]),
          );
        }
        return formation.withUpdates(changes);
      });

  @override
  bool operator ==(Object other) =>
      other is HeyForFour &&
      other.pass1 == pass1 &&
      other.length == length &&
      other.pass2 == pass2 &&
      other.meetTarget == meetTarget &&
      other.shoulder == shoulder &&
      other.dir == dir &&
      other.rico1 == rico1 &&
      other.rico2 == rico2 &&
      other.rico3 == rico3 &&
      other.rico4 == rico4;

  @override
  int get hashCode => Object.hash(
    name,
    pass1,
    length,
    pass2,
    meetTarget,
    shoulder,
    dir,
    rico1,
    rico2,
    rico3,
    rico4,
  );

  @override
  String toString() => 'hey(${pass1.key} first, ${length.key}, ${dir.key})';
}
