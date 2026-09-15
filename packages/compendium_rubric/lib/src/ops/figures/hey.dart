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
typedef _HeyLine = ({DancerPair centers, DancerPair ends, bool sideStart});

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
/// parameter — so they must be one on each side of the set. The remaining two
/// are the ends by construction, which is why [pass2] can only ever
/// corroborate.
///
/// The passes alternate between the centre and the sides. The centres meet
/// first; then, having crossed, each of them passes the end dancer who was
/// standing on the far side. So the second pass is a **side** pass, and it
/// pairs a centre dancer with an end dancer rather than naming the ends pair —
/// which is what [pass2] describes.
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
/// centre alternates: [rico1] and [rico3] are the two meetings of whichever
/// pair meets in the centre **first**, [rico2] and [rico4] the other pair's.
///
/// The flags count centre meetings only, never side passes (user-ruled; the
/// exceptions are out of scope). That is what makes them survive a hey that
/// opens on the side: opening there moves the first centre meeting from pass 1
/// to pass 2, but it does not change how many centre meetings each pair has,
/// nor which pair has the first of them — in a side opening that pair is the
/// one [pass2] names, and this figure has already resolved it before the flags
/// are read.
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

  /// The pair who make the **second** pass, which happens on the sides.
  ///
  /// Not the ends pair. The passes of a hey alternate between the centre and
  /// the sides, and [pass1] takes the first — so the second is danced on the
  /// sides, by a centre dancer and the end dancer standing where that centre
  /// dancer arrives. Core's `hey` MoveDef comments this parameter as "the ends
  /// pair", but core's own Caller's Box dialect fills it from the *who* of the
  /// second pass code (`callersbox_figure_dialect.dart`, the `position == 2`
  /// branch), and the dialect is what actually populates the records this
  /// compiler reads.
  ///
  /// An **anchor**, on the [FormLongWaves] precedent: once [pass1] is resolved
  /// the side pairings follow from the geometry, so a stated [pass2] cannot
  /// select anybody. It is checked against the pairs the figure derived and
  /// reported through [WarningKind.anchorMismatch] when the two disagree.
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

  /// The pair who meet in the centre first ricochet at that meeting.
  ///
  /// That is the [pass1] pair when the hey opens in the centre, and the [pass2]
  /// pair when it opens on the side.
  final bool rico1;

  /// The other pair ricochet at their first centre meeting.
  final bool rico2;

  /// The pair who met first ricochet at their second meeting (full hey only).
  final bool rico3;

  /// The other pair ricochet at their second centre meeting (full hey only).
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
  ///
  /// A hey's passes alternate between the centre and the sides, and `pass1`
  /// names the **first** one — which is usually, but not always, the centre.
  /// Which it is here is read off the floor rather than declared: a pair
  /// standing one on each side of the set can only meet in the middle, and a
  /// pair standing on the same side can only pass there. So when `pass1`
  /// resolves to one **spanning** pair the hey opens in the centre, and when it
  /// resolves to pairs that each stand on **one side** the hey opens with the
  /// two side passes danced at once, and the centre pass falls to `pass2`.
  ///
  /// In the side-opening case `pass2` stops being an anchor and becomes a
  /// genuine selector, because nothing else can say who meets in the middle —
  /// in a duple-improper set after an allemande that swaps a diagonal, *both*
  /// role pairs span. Per the anchor doctrine (`docs/implementation.md` §8) an
  /// absent `pass2` there is a refusal, never a guess.
  Result<List<_HeyLine>, OpError> _lines(Formation formation) {
    bool spans(DancerPair pair) =>
        formation.stateOf(pair.a).position.col !=
        formation.stateOf(pair.b).position.col;

    final lines = <_HeyLine>[];
    for (final band in handsFourBands(formation)) {
      final where = 'the hands four at rows ${band.topRow}-${band.bottomRow}';
      final opening = resolveWhoPairs(
        formation,
        pass1,
        topRow: band.topRow,
        bottomRow: band.bottomRow,
      );
      if (opening.isEmpty) {
        return Err<List<_HeyLine>, OpError>(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'hey needs pass1 to name the pair or pairs who pass first, but '
            '${pass1.key} names nobody standing together in $where',
          ),
        );
      }

      final DancerPair middle;
      final bool sideStart;
      if (opening.length == 1 && spans(opening.single)) {
        middle = opening.single;
        sideStart = false;
      } else if (_coversBothSides(opening, spans)) {
        final error = _deferredSideStart();
        if (error != null) return Err<List<_HeyLine>, OpError>(error);
        final centers = _resolveSideStartCenters(formation, band, spans, where);
        switch (centers) {
          case Err(:final error):
            return Err<List<_HeyLine>, OpError>(error);
          case Ok(:final value):
            middle = value;
            sideStart = true;
        }
      } else if (opening.length == 1) {
        return Err<List<_HeyLine>, OpError>(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'hey needs the ${pass1.key} pair either one on each side of the '
            'set, to meet in the centre, or matched by a second pair on the '
            'far side, to pass on the sides; ${opening.single.a} and '
            '${opening.single.b} are standing in the same line in $where with '
            'nobody named opposite them',
          ),
        );
      } else {
        return Err<List<_HeyLine>, OpError>(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'hey cannot tell where ${pass1.key} passes in $where: it names '
            '${opening.length} pairs, which is neither the one pair standing '
            'across the set that meets in the centre nor the two same-side '
            'pairs that pass on the sides',
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
      lines.add((
        centers: middle,
        ends: (a: rest.first, b: rest.last),
        sideStart: sideStart,
      ));
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

  /// Whether [opening] describes the side pass of a hey rather than a pass in
  /// the centre.
  ///
  /// A hey's side pass is danced on **both** sides at once, so the reading only
  /// holds when the named pairs account for the whole hands four: two pairs,
  /// neither of them spanning the set, between them covering all four dancers.
  /// One same-side pair names half a pass and leaves the other half unsaid,
  /// which is not enough to weave from.
  bool _coversBothSides(
    List<DancerPair> opening,
    bool Function(DancerPair) spans,
  ) {
    if (opening.length != 2) return false;
    if (opening.any(spans)) return false;
    final named = {
      for (final pair in opening) ...[pair.a, pair.b],
    };
    return named.length == 4;
  }

  /// Why a hey that opens on the side is deferred unless it is a full one.
  ///
  /// Opening on the side shifts every later pass by one, so the **half-way
  /// point** lands somewhere this model has no worked example for. A full hey
  /// is exempt because the whole weave is danced either way.
  ///
  /// Ricochets are *not* deferred. They count centre meetings rather than
  /// passes (user-ruled), and opening on the side changes neither how many
  /// centre meetings a pair has nor which pair has the first one — it only
  /// moves that meeting from pass 1 to pass 2. Since [_exchanges] reads
  /// nothing but the per-pair meeting parity, the shift cannot reach it.
  OpError? _deferredSideStart() {
    if (length != HeyLength.full) {
      return OpError(
        ErrorKind.unsupportedParam,
        'hey length:${length.key} opening on the side is deferred: opening '
        'there shifts every pass by one, so where the weave stops half way is '
        'not the place a centre-opening half hey stops, and no worked example '
        'pins it',
      );
    }
    return null;
  }

  /// Who meets in the centre when `pass1` named the side passes.
  Result<DancerPair, OpError> _resolveSideStartCenters(
    Formation formation,
    ({int topRow, int bottomRow}) band,
    bool Function(DancerPair) spans,
    String where,
  ) {
    final anchor = pass2;
    if (anchor == null) {
      return Err<DancerPair, OpError>(
        OpError(
          ErrorKind.unresolvableDancerSet,
          'hey opens with ${pass1.key} passing on the sides in $where, so the '
          'centre pass is the second one and nothing names it; pass2 is '
          'needed to say who meets in the middle',
        ),
      );
    }
    final candidates = resolveWhoPairs(
      formation,
      anchor,
      topRow: band.topRow,
      bottomRow: band.bottomRow,
    ).where(spans).toList();
    if (candidates.length != 1) {
      return Err<DancerPair, OpError>(
        OpError(
          ErrorKind.unresolvableDancerSet,
          'hey opens on the sides in $where, so pass2 must name the pair who '
          'meet in the centre, but ${anchor.key} names ${candidates.length} '
          'pairs standing across the set',
        ),
      );
    }
    return Ok<DancerPair, OpError>(candidates.single);
  }

  /// The two pairs who dance the second pass, which happens on the sides.
  ///
  /// Passing in the centre puts each of the centre dancers on the far side of
  /// the set, so each comes out beside the end dancer who was standing there.
  /// The side passes therefore cross the line: centre-west with end-east, and
  /// centre-east with end-west.
  List<DancerPair> _sidePairs(Formation formation, _HeyLine line) {
    bool isWest(DancerId id) =>
        formation.stateOf(id).position.col < kColumnCount ~/ 2;

    final forCenterA = isWest(line.ends.a) == isWest(line.centers.a)
        ? line.ends.b
        : line.ends.a;
    return [
      (a: line.centers.a, b: forCenterA),
      (
        a: line.centers.b,
        b: forCenterA == line.ends.a ? line.ends.b : line.ends.a,
      ),
    ];
  }

  @override
  Iterable<Warning> lint(Formation formation) {
    final anchor = pass2;
    if (anchor == null) return const [];
    final lines = _lines(formation).valueOrNull;
    if (lines == null) return const [];
    for (final line in lines) {
      // In a side-opening hey `pass2` is what named these centres, so checking
      // it against the second pass would be checking it against itself.
      if (line.sideStart) continue;
      for (final pair in _sidePairs(formation, line)) {
        if (whoMatches(formation, pair.a, pair.b, anchor)) continue;
        return [
          Warning(
            WarningKind.anchorMismatch,
            detail:
                'hey says the second pass is danced by the ${anchor.key}, but '
                'with ${pass1.key} meeting first in the centre it falls to '
                '${pair.a} and ${pair.b} on the side, who are not. The hey '
                'still weaves as pass1 describes it; only the second pass is '
                'misdescribed',
          ),
        ];
      }
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
