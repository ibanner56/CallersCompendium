part of '../operation.dart';

/// The wave figures (`docs/fundamentals.md` §8.5).
///
/// A wave is a line of dancers with joined hands and **alternating facing**.
/// Three figures form one, and they divide along the axis the wave runs on:
/// [FormShortWaves] builds a wave of four **across** the set inside each hands
/// four, while [FormLongWaves] and [FormALongWave] build waves that run
/// **along** it — the first as the two side lines, the second as a single line
/// down the centre.
///
/// None of them declares [Operation.preservesWaveOffsets]. That is deliberate
/// and load-bearing rather than an oversight: each is defined over settled side
/// columns, so letting §8.5.4's normalization run first is what makes them
/// composable. Forming short waves twice in a row re-forms them from c0/c4
/// instead of compounding two offsets, and `form_a_long_wave`'s "come back out
/// to the sides" case needs no code at all, because returning a centre dancer
/// to the line they left is precisely what the normalizer does.

/// The four corner dancers of a band, named by row and side.
typedef _Corners = ({
  DancerId topWest,
  DancerId bottomWest,
  DancerId topEast,
  DancerId bottomEast,
});

/// A band paired with its corner dancers.
typedef _CorneredBand = ({Band band, _Corners corners});

/// [band]'s four corner dancers, or `null` if any corner is empty.
_Corners? _bandCorners(Formation formation, Band band) {
  const east = kColumnCount - 1;
  final topWest = formation.dancerAt(Position(band.topRow, 0));
  final bottomWest = formation.dancerAt(Position(band.bottomRow, 0));
  final topEast = formation.dancerAt(Position(band.topRow, east));
  final bottomEast = formation.dancerAt(Position(band.bottomRow, east));
  if (topWest == null ||
      bottomWest == null ||
      topEast == null ||
      bottomEast == null) {
    return null;
  }
  return (
    topWest: topWest,
    bottomWest: bottomWest,
    topEast: topEast,
    bottomEast: bottomEast,
  );
}

/// Every band of [formation] that holds a complete ring of four.
///
/// Incomplete bands are dropped rather than refused, matching
/// [rotateHandsFourRings]: a couple standing out at an end of the set is not in
/// a hands four and has no wave to form.
List<_CorneredBand> _corneredBands(Formation formation) => [
  for (final band in handsFourBands(formation))
    if (_bandCorners(formation, band) case final corners?)
      (band: band, corners: corners),
];

/// `form_short_waves` — each hands four steps into a wave of four across the
/// set (`docs/taxonomy.md`, `docs/fundamentals.md` §8.5.1).
///
/// **The geometry is one bit wide.** A wave alternates hands along its length,
/// so naming either join fixes the other, and fixing either one fixes every
/// dancer's offset. The figure carries three parameters that all speak to that
/// single bit — [centerHand], [center] and [sides] — which makes two of them
/// redundant and therefore useful: they are checked against the arrangement
/// rather than trusted, and a contradiction is [ErrorKind.whoMismatch].
///
/// [centerHand] drives, inverted to give the hand the facing pairs join. When
/// the source states no hand, [center] drives instead — it names the same bit
/// from the other side, and preferring a stated parameter to a defaulted one
/// is what keeps a record that says "robins in the middle" from being refused
/// for disagreeing with a hand it never mentioned.
///
/// **Which role ends in the middle is an output, not an input.** The offset is
/// derived from facing throughout (§8.5.1), so the same hand puts different
/// roles in the centre from different arrangements — which is exactly what the
/// real corpus shows, carrying both `(nr,wl)` and `(nr,ml)` in quantity.
final class FormShortWaves extends Operation {
  const FormShortWaves({
    this.dir = Direction.across,
    this.balance = false,
    this.center = WhoSet.role2s,
    this.centerHand,
    this.sides = WhoSet.neighbors,
  });

  /// Which way the wave runs. Only `across` is implemented.
  final Direction dir;

  /// Whether the wave is balanced once formed. No end-state effect, matching
  /// `petronella`'s flag and `swing`'s `prefix`.
  final bool balance;

  /// Who the source says ends in the two centre cells. Verified, not trusted.
  final WhoSet center;

  /// The hand the centre pair joins — **not** the hand the wave is named for,
  /// which is the outer join alternation makes its opposite (§8.5.1).
  ///
  /// `null` is the upstream `unspecified` sentinel rather than a missing value:
  /// a record that states which role takes the middle but not by which hand has
  /// said everything needed, and defaulting a hand on its behalf would
  /// manufacture a contradiction with the parameter it did state. The baseline
  /// taxonomy declares a `right` default, which is deliberately not honoured:
  /// the canonical wave is the centre pair joining **left** and the sides
  /// right, so a stated `center` derives the hand and beats a literal default
  /// that would contradict it.
  final Hand? centerHand;

  /// Who the source says the facing pairs are. Verified, not trusted.
  final WhoSet sides;

  @override
  String get name => 'form_short_waves';

  @override
  Iterable<WhoSet?> get dancerSets => [center, sides];

  /// The hand the **facing pairs** join — the opposite of the centre join.
  ///
  /// Resolved once for the whole set rather than per band: this is one figure
  /// danced everywhere at once, and a set whose bands disagreed about which
  /// hand they were giving would not be dancing the same wave.
  Hand _outerHand(Formation formation) {
    final stated = centerHand;
    if (stated != null) {
      return stated == Hand.right ? Hand.left : Hand.right;
    }
    for (final entry in _corneredBands(formation)) {
      final withRight = _centrePair(entry.corners, Hand.right);
      final withLeft = _centrePair(entry.corners, Hand.left);
      final rightFits = whoMatches(formation, withRight.a, withRight.b, center);
      final leftFits = whoMatches(formation, withLeft.a, withLeft.b, center);
      if (rightFits != leftFits) return rightFits ? Hand.right : Hand.left;
    }
    // `center` did not discriminate either — it can name a set both pairs
    // satisfy, or neither. Fall back to the canonical wave, which is the
    // centre pair joining **left** while the sides join right.
    return Hand.right;
  }

  /// The pair who end in the centre cells when the facing pairs join [hand].
  ///
  /// Follows from the offset rule and nothing else: giving right hands sends
  /// each dancer toward their own left, which from the top row is east and from
  /// the bottom row is west, so the top-row westerner and the bottom-row
  /// easterner are the two who step in. Left hands select the other diagonal.
  static DancerPair _centrePair(_Corners corners, Hand hand) =>
      hand == Hand.right
      ? (a: corners.topWest, b: corners.bottomEast)
      : (a: corners.bottomWest, b: corners.topEast);

  /// Where each corner dancer stands and faces once the wave is formed.
  ///
  /// The facing a wave needs is the facing its pairs already have at rest —
  /// each looking at the dancer across the band from them, the top row down and
  /// the bottom row up — and that is alternating facing read along the wave, so
  /// there is nothing extra to impose. It is passed to [waveOffsetColumn]
  /// rather than assumed, which is what keeps the offset a consequence of
  /// facing (§8.5.1) instead of a hard-coded column.
  static Map<DancerId, ({Position position, Facing facing})> _placements(
    Band band,
    _Corners corners,
    Hand hand,
  ) {
    const east = kColumnCount - 1;
    final resting = [
      (id: corners.topWest, row: band.topRow, col: 0, facing: Facing.down),
      (id: corners.topEast, row: band.topRow, col: east, facing: Facing.down),
      (id: corners.bottomWest, row: band.bottomRow, col: 0, facing: Facing.up),
      (
        id: corners.bottomEast,
        row: band.bottomRow,
        col: east,
        facing: Facing.up,
      ),
    ];
    return {
      for (final dancer in resting)
        dancer.id: (
          position: Position(
            dancer.row,
            waveOffsetColumn(
              col: dancer.col,
              facing: dancer.facing,
              hand: hand,
            ),
          ),
          facing: dancer.facing,
        ),
    };
  }

  @override
  Iterable<Warning> lint(Formation formation) {
    for (final entry in _corneredBands(formation)) {
      for (final dancer in _placements(
        entry.band,
        entry.corners,
        _outerHand(formation),
      ).entries) {
        final actual = formation.stateOf(dancer.key).facing;
        if (actual == dancer.value.facing) continue;
        return [
          Warning(
            WarningKind.facingPrecondition,
            detail:
                'form_short_waves needs each pair looking at each other across '
                'the band, but ${dancer.key} faces ${actual.label} rather than '
                '${dancer.value.facing.label}; they turn to it before stepping '
                'into the wave',
          ),
        ];
      }
    }
    return const [];
  }

  @override
  OpError? checkPreconditions(Formation formation) {
    if (dir != Direction.across) {
      return OpError(
        ErrorKind.unsupportedParam,
        'form_short_waves supports dir:across only; ${dir.key} builds the wave '
        'on a diagonal, which reaches across hands four and has no worked '
        'example on record',
      );
    }
    final bands = _corneredBands(formation);
    if (bands.isEmpty) {
      return const OpError(
        ErrorKind.unresolvableDancerSet,
        'form_short_waves found no complete hands four to build a wave in',
      );
    }

    final hand = _outerHand(formation);
    for (final entry in bands) {
      final corners = entry.corners;
      final facingPairs = <DancerPair>[
        (a: corners.topWest, b: corners.bottomWest),
        (a: corners.topEast, b: corners.bottomEast),
      ];
      for (final pair in facingPairs) {
        if (whoMatches(formation, pair.a, pair.b, sides)) continue;
        return OpError(
          ErrorKind.whoMismatch,
          'form_short_waves names sides:${sides.key}, but ${pair.a} and '
          '${pair.b} are the pair standing face to face; the dancers giving '
          'hands on the ends are not the ones the figure names',
        );
      }
      final centre = _centrePair(corners, hand);
      if (whoMatches(formation, centre.a, centre.b, center)) continue;
      return OpError(
        ErrorKind.whoMismatch,
        'form_short_waves names center:${center.key} with the ends giving '
        '${hand.key} hands, but that offset puts ${centre.a} and ${centre.b} '
        'in the middle; the hand and the centre pair the figure names '
        'disagree',
      );
    }
    return null;
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final hand = _outerHand(formation);
    final changes = <DancerId, DancerState>{};
    for (final entry in _corneredBands(formation)) {
      _placements(entry.band, entry.corners, hand).forEach((id, placement) {
        changes[id] = formation
            .stateOf(id)
            .copyWith(position: placement.position, facing: placement.facing);
      });
    }
    return Ok<Formation, OpError>(formation.withUpdates(changes));
  }

  @override
  bool operator ==(Object other) =>
      other is FormShortWaves &&
      other.dir == dir &&
      other.balance == balance &&
      other.center == center &&
      other.centerHand == centerHand &&
      other.sides == sides;

  @override
  int get hashCode =>
      Object.hash(name, dir, balance, center, centerHand, sides);

  @override
  String toString() =>
      'form_short_waves(${dir.key}, center: ${center.key} by '
      '${centerHand?.key ?? 'unspecified'}, sides: ${sides.key})';
}

/// `form_long_waves` — the two side lines become waves running along the set
/// (`docs/taxonomy.md`, `docs/fundamentals.md` §8.5.5).
///
/// **Nobody moves.** §8.5.1's offset exists so that dancers who face *each
/// other* can join matching hands; in a long wave you join hands with the
/// dancers **beside** you along your own line, whom you do not face, and the
/// line already runs the way the wave does. So the figure is facing and nothing
/// else — which is also why it can be danced by the whole set at once, ends
/// included, rather than band by band.
///
/// The facing is **across the set, alternating in and out**, which is what
/// makes balancing a long wave a balance right and left along the hall. [who]
/// names the pair facing **in**; everyone else faces out. That is the parameter
/// the baseline taxonomy documents, and it is a selector rather than a set of
/// movers precisely because there is no movement to scope.
///
/// The alternation is a consequence of the role-scoped [who] the figure is
/// written with: roles alternate down a line, so naming one of them lands the
/// facings in and out, in and out. A [who] that does not alternate produces a
/// line of joined hands that is not a wave; the figure still runs, since the
/// arrangement is legal and only the label is wrong.
///
/// **[whom] and [hand] are anchors.** They state which dancer you hold and by
/// which hand — a fact [who] already determines, since a dancer's hands follow
/// from their facing and their facing follows from [who]. They are read twice
/// over. When [who] is absent they **resolve** it, because naming the hold
/// fixes the facing pair just as surely as naming the pair does. When it is
/// present they **corroborate** it, and a hold that the arrangement cannot
/// produce raises [WarningKind.anchorMismatch] rather than refusing — the
/// figure never needed them, so what is wrong is the description.
/// *(User-ruled.)*
final class FormLongWaves extends Operation {
  const FormLongWaves({this.who, this.whom, this.hand, this.balance = false});

  /// The pair who face **in**; the other pair faces out.
  ///
  /// `null` is the upstream `unspecified` sentinel, and it is **carried rather
  /// than defaulted** for the reason [FormShortWaves.centerHand] is: the
  /// baseline defaults this to `role1s`, but a record can fix the same bit of
  /// geometry by naming the hold instead — and from a duple-improper start
  /// `whom: neighbors` by the `right` is the *other* pair. Supplying the
  /// default on such a record's behalf would make it contradict itself over a
  /// value it never stated. See [resolvedWho].
  final WhoSet? who;

  /// Whom you hold. An anchor: no end-state effect, `null` is the upstream
  /// `unspecified` sentinel.
  final WhoSet? whom;

  /// The hand you hold [whom] by. An anchor, on the same footing as [whom] —
  /// and unlike a short wave's, this hand displaces nobody, because nobody
  /// steps anywhere to reach it.
  final Hand? hand;

  /// Whether the wave is balanced once formed. No end-state effect.
  final bool balance;

  @override
  String get name => 'form_long_waves';

  /// The canonical pair, used when nothing in the record discriminates.
  static const _canonicalWho = WhoSet.role1s;

  /// The pairs a record could mean by [who], in the order they are tried.
  static const _candidates = [WhoSet.role1s, WhoSet.role2s];

  /// Which pair ends up facing in, once the anchors have had their say.
  ///
  /// [who] wins when it is stated. Otherwise the anchors are asked: each
  /// candidate pair is formed and tested against them, and a candidate is
  /// adopted only when it is the **only** one that fits. Anything less — no
  /// anchors, anchors that fit both, anchors that fit neither — falls back to
  /// the canonical pair, so a record can never be silently read as a dance it
  /// did not describe.
  WhoSet resolvedWho(Formation formation) {
    if (who != null) return who!;
    if (whom == null && hand == null) return _canonicalWho;
    final fits = [
      for (final candidate in _candidates)
        if (_anchorMismatch(formation, candidate) == null) candidate,
    ];
    return fits.length == 1 ? fits.single : _canonicalWho;
  }

  /// The facings [candidate] produces, as a formation.
  ///
  /// Nobody moves: this is the whole of the figure's effect (§8.5.5), factored
  /// out so the anchor check can interrogate the wave the figure *would* form
  /// rather than the settled set it was handed.
  Formation _faced(Formation formation, WhoSet candidate) {
    final changes = <DancerId, DancerState>{};
    for (final entry in formation.dancers.entries) {
      final col = entry.value.col;
      if (col != 0 && col != kColumnCount - 1) continue;
      final inward = acrossFacingInto(col);
      final facing = whoIncludes(formation, entry.key, candidate)
          ? inward
          : inward.reversed;
      if (facing == entry.value.facing) continue;
      changes[entry.key] = entry.value.copyWith(facing: facing);
    }
    return formation.withUpdates(changes);
  }

  /// How the anchors contradict the wave [candidate] forms, or `null` if they
  /// do not.
  ///
  /// A dancer's hand-side partner in a long wave is the dancer **beside them
  /// along their own line** — same column, one rank away, on the side their
  /// facing puts that hand. Ends of the wave have a free hand, which is normal
  /// and never a contradiction, so a missing partner is skipped rather than
  /// counted against the anchor.
  ///
  /// With [hand] absent the test is the weaker "either hand would do", which
  /// still falsifies a hold no rank offers at all.
  String? _anchorMismatch(Formation formation, WhoSet candidate) {
    if (whom == null) return null;
    final wave = _faced(formation, candidate);
    final hands = hand == null ? const [Hand.right, Hand.left] : [hand!];
    for (final entry in wave.dancers.entries) {
      final col = entry.value.col;
      if (col != 0 && col != kColumnCount - 1) continue;
      var offered = false;
      var held = false;
      for (final side in hands) {
        final toward = side == Hand.right
            ? entry.value.facing.turnedRight
            : entry.value.facing.turnedLeft;
        final row = entry.value.row + (toward == Facing.up ? -1 : 1);
        final mate = wave.dancerAt(Position(row, col));
        if (mate == null) continue;
        offered = true;
        if (_holds(wave, entry.key, mate)) held = true;
      }
      if (offered && !held) {
        return '${entry.key} is beside a dancer who is not their '
            '${whom!.key}';
      }
    }
    return null;
  }

  /// Whether [a] and [b] stand in the relationship [whom] names.
  ///
  /// Two questions, because [whoMatches] answers only the first. It settles the
  /// *kind* of pairing — opposite role, different couple, different number for
  /// a neighbour — but it deliberately treats all five neighbour sets alike,
  /// since by the time most figures ask, the set has been re-banded and the
  /// distance is spent. Nothing re-bands here, so the **distance** is still a
  /// live claim and is checked directly: `neighbors` means the couple in your
  /// own grouping, and the named distances mean that many groupings along in
  /// your own direction of travel.
  bool _holds(Formation wave, DancerId a, DancerId b) {
    if (!whoMatches(wave, a, b, whom!)) return false;
    if (whom != WhoSet.neighbors && !whom!.isCrossHandsFour) return true;
    final wanted = (whom!.distance ?? 0) * travelDirection(wave, a);
    return homeGrouping(b) - homeGrouping(a) == wanted;
  }

  @override
  Iterable<Warning> lint(Formation formation) {
    final resolved = resolvedWho(formation);
    final mismatch = _anchorMismatch(formation, resolved);
    if (mismatch == null) return const [];
    return [
      Warning(
        WarningKind.anchorMismatch,
        detail:
            'form_long_waves says the dancers hold their ${whom!.key}'
            '${hand == null ? '' : ' by the ${hand!.key}'}, but with '
            '${resolved.key} facing in, $mismatch. The wave still forms as '
            '${resolved.key} describes it; only the hold is misdescribed',
      ),
    ];
  }

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok<Formation, OpError>(_faced(formation, resolvedWho(formation)));

  @override
  bool operator ==(Object other) =>
      other is FormLongWaves &&
      other.who == who &&
      other.whom == whom &&
      other.hand == hand &&
      other.balance == balance;

  @override
  int get hashCode => Object.hash(name, who, whom, hand, balance);

  @override
  String toString() =>
      'form_long_waves(${who?.key ?? 'unspecified'} facing in, holding '
      '${whom?.key ?? 'unspecified'} by ${hand?.key ?? 'unspecified'})';
}

/// `form_a_long_wave` — one role steps into the centre of the set and waves
/// down the middle (`docs/taxonomy.md`, `docs/fundamentals.md` §8.5.5).
///
/// **The centre column is exact — there is no offset.** As with
/// [FormLongWaves], the dancers of this wave stand beside one another along the
/// set rather than facing each other across it, so nobody steps sideways to
/// find a hand.
///
/// **Why the figure is role-scoped is structural, not stylistic.** A rank holds
/// two dancers and `c2` holds one, so a centre wave cannot be danced by
/// everyone. Every rank contains exactly one of each role, so a role-scoped
/// [who] puts exactly one dancer per rank in the centre and the counts land
/// exactly. Anything else is refused rather than approximated.
///
/// [stepsIn] and [stepsOut] describe the two directions of traffic. Stepping in
/// is the move; **stepping out needs no code**, because §8.5.4's normalization
/// has already returned anyone standing in the centre to the line they left
/// before this figure runs — and that is the same rule that evicts the other
/// role when [who] arrives to take its place.
final class FormALongWave extends Operation {
  const FormALongWave({
    this.who = WhoSet.role2s,
    this.stepsIn = true,
    this.stepsOut = false,
    this.balance = true,
  });

  /// Which role forms the wave.
  final WhoSet who;

  /// Whether [who] steps into the centre column. The taxonomy spells this
  /// `in`, which Dart reserves.
  final bool stepsIn;

  /// Whether [who] returns to the side lines. The taxonomy spells this `out`.
  final bool stepsOut;

  /// Whether the wave is balanced once formed. No end-state effect.
  final bool balance;

  @override
  String get name => 'form_a_long_wave';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  /// The centre column of the set.
  static const int _centreColumn = kColumnCount ~/ 2;

  /// The rows this figure has to place a dancer in, each with the dancer who
  /// steps to the centre and the side column their rank leaves free.
  ///
  /// Returns an error rather than a partial answer when a rank cannot seat the
  /// wave: the capacity argument above is what makes the figure well defined,
  /// so a rank that does not hold exactly one [who] dancer and one other has no
  /// centre wave to join, and guessing would strand a dancer in a line that is
  /// not theirs.
  Result<List<({DancerId mover, int row, int from})>, OpError> _steppingIn(
    Formation formation,
  ) {
    final rows = <int>{for (final state in formation.dancers.values) state.row};
    final steps = <({DancerId mover, int row, int from})>[];
    for (final row in rows.toList()..sort()) {
      final ids = formation.dancersInRow(row);
      final movers = [
        for (final id in ids)
          if (whoIncludes(formation, id, who)) id,
      ];
      if (movers.length != 1 || ids.length != 2) {
        return Err<List<({DancerId mover, int row, int from})>, OpError>(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'form_a_long_wave needs exactly one ${who.key} dancer per rank to '
            'step into the centre and one to hold the line, but rank $row '
            'holds ${ids.length} dancer(s), ${movers.length} of them '
            '${who.key}; the centre column has room for one',
          ),
        );
      }
      steps.add((
        mover: movers.single,
        row: row,
        from: formation.stateOf(movers.single).col,
      ));
    }
    return Ok<List<({DancerId mover, int row, int from})>, OpError>(steps);
  }

  @override
  OpError? checkPreconditions(Formation formation) {
    if (!stepsIn) return null;
    return _steppingIn(formation).errorOrNull;
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    // Stepping out has already happened: the normalizer returned every centre
    // dancer to the side their rank left free before this figure was handed
    // the state.
    if (!stepsIn) return Ok<Formation, OpError>(formation);

    return _steppingIn(formation).map((steps) {
      final changes = <DancerId, DancerState>{};
      for (final step in steps) {
        // A dancer walks in facing the way they walk, which alternates down the
        // set for free because consecutive ranks step in from opposite lines.
        final facing = step.from < _centreColumn
            ? Facing.acrossEast
            : Facing.acrossWest;
        changes[step.mover] = formation
            .stateOf(step.mover)
            .copyWith(
              position: Position(step.row, _centreColumn),
              facing: facing,
            );
      }
      return formation.withUpdates(changes);
    });
  }

  @override
  bool operator ==(Object other) =>
      other is FormALongWave &&
      other.who == who &&
      other.stepsIn == stepsIn &&
      other.stepsOut == stepsOut &&
      other.balance == balance;

  @override
  int get hashCode => Object.hash(name, who, stepsIn, stepsOut, balance);

  @override
  String toString() =>
      'form_a_long_wave(${who.key}, in: $stepsIn, out: $stepsOut)';
}

/// `pass_the_ocean` — the set passes through across the hall and takes the
/// short wave it lands in, in one figure.
///
/// Two moves already stated elsewhere, composed in the stated order:
///
/// 1. **Pass through**, across the set. Every dancer trades columns with their
///    row-mate — the "all cross over" of the worked example — which is the
///    column reflection [reflectBands] performs.
/// 2. **Form the wave** from where that leaves them, by delegating to
///    [FormShortWaves] with this figure's own wave parameters.
///
/// Composing rather than reimplementing is the point. The wave geometry is one
/// bit wide and [FormShortWaves] already owns it, including the cross-checks
/// that catch a record whose `center` and `centerHand` disagree; a second
/// derivation here could only drift from it.
///
/// **Rows never change**, which follows from step 1 being a column reflection
/// and step 2 an offset within a rank (§8.5.1). A dancer who appears to have
/// changed rank across this figure has not danced it.
///
/// The pass is **across the hall**, so the figure wants a set already facing
/// that way. That is reported by [lint] and never refused: facing is a warning
/// in this compiler, never an error, so a set facing along the hall turns to
/// the pass and dances it rather than being rejected.
final class PassTheOcean extends Operation {
  const PassTheOcean({
    this.dir = Direction.across,
    this.balance = false,
    this.center = WhoSet.role2s,
    this.centerHand,
    this.sides = WhoSet.neighbors,
  });

  /// Which way the wave runs. Only `across` is implemented, as for
  /// [FormShortWaves].
  final Direction dir;

  /// Whether the wave is balanced once formed. No end-state effect.
  final bool balance;

  /// Who the source says ends in the two centre cells. Verified, not trusted.
  final WhoSet center;

  /// The hand the centre pair joins. See [FormShortWaves.centerHand] — `null`
  /// is the upstream `unspecified` sentinel, not a missing value.
  final Hand? centerHand;

  /// Who the source says the facing pairs are. Verified, not trusted.
  final WhoSet sides;

  @override
  String get name => 'pass_the_ocean';

  @override
  Iterable<WhoSet?> get dancerSets => [center, sides];

  /// The wave this figure lands in, as its own figure.
  FormShortWaves get _wave => FormShortWaves(
    dir: dir,
    balance: balance,
    center: center,
    centerHand: centerHand,
    sides: sides,
  );

  @override
  Iterable<Warning> lint(Formation formation) {
    final wrongWay = [
      for (final entry in formation.dancers.entries)
        if (entry.value.facing.isConcrete && !entry.value.facing.isAcross)
          entry.key,
    ];
    if (wrongWay.isEmpty) return const [];
    return [
      Warning(
        WarningKind.facingPrecondition,
        detail:
            'pass_the_ocean passes across the hall, but '
            '${wrongWay.length} dancer(s) were facing along it '
            '(${wrongWay.first} and others); they turn across before passing',
      ),
    ];
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    // The pass: every dancer trades columns with their row-mate.
    final passed = reflectBands(formation, columns: true);
    // The wave owns the facing (§8.5.6). This is not decoration — the §8.5.1
    // offset is *derived* from facing, and a set that entered facing across
    // (which is what this figure asks for) yields no offset at all, so
    // delegating without this would quietly produce a settled set and call it
    // a wave. Taking the rank's resting facing also makes the wave's
    // handedness follow the stated [centerHand] rather than whichever way the
    // set happened to arrive.
    final turned = mapBandFacing(
      passed,
      (id, state, band) => state.row == band.topRow ? Facing.down : Facing.up,
    );
    // Delegated through the public entry point rather than the protected
    // transform, so the wave's own preconditions and cross-checks run against
    // the state the pass actually produced.
    return _wave.apply(turned);
  }

  @override
  bool operator ==(Object other) =>
      other is PassTheOcean &&
      other.dir == dir &&
      other.balance == balance &&
      other.center == center &&
      other.centerHand == centerHand &&
      other.sides == sides;

  @override
  int get hashCode =>
      Object.hash(name, dir, balance, center, centerHand, sides);

  @override
  String toString() =>
      'pass_the_ocean(centerHand: ${centerHand?.key ?? 'unspecified'})';
}

/// `rory_o_more` — the dancers standing in a wave balance it and slide
/// sideways past the dancer beside them, landing in the wave of opposite hand.
///
/// One rule covers both wave orientations: **every sliding dancer steps one
/// cell toward their own named side**, and which side that is comes from their
/// own [DancerState.facing] rather than from the wave's handedness. Facing
/// itself is untouched — a slide changes which hand you give, not where you
/// look — so the alternation that makes the line a wave survives the step.
///
/// The consequences differ by orientation only because facing does:
///
/// * In a **short wave across the set** the dancers face along the hall, so
///   their sides are the columns and the slide moves them across — the
///   canonical right-hand wave becomes the mirror left-hand one, in place.
/// * In a **long wave along the sides** they face across, so their sides are
///   the rows and the slide moves them along the set, each pair trading ranks.
///
/// Handedness needs no detection: the wave a slide cannot leave is the one
/// whose dancers would step off the matrix, so the grid boundary refuses it.
/// From the canonical right-hand short wave a slide left sends the c4 dancer
/// to c5 and is rejected; a slide right lands cleanly and the return slide
/// left then works, which is exactly the pair of slides a dance calls.
///
/// Declares [Operation.preservesWaveOffsets] — the third figure to, alongside
/// `balance` and `stand_still`. It meets the §8.5.4 premise squarely: this is
/// not a figure that merely tolerates a wave but one that has no meaning
/// outside of it, so settling the offsets away first would delete the very
/// state it reads.
final class RoryOMore extends Operation {
  const RoryOMore({
    this.who = WhoSet.everyone,
    this.balance = true,
    this.slide = Hand.right,
  });

  /// The dancers who slide. Defaults to the whole wave.
  final WhoSet who;

  /// Whether the wave is balanced first. No end-state effect, exactly as
  /// `petronella`'s flag has none.
  final bool balance;

  /// The side each sliding dancer steps toward, read against their own facing.
  /// Spelled with [Hand] because "slide right" names the dancer's right, the
  /// same reference `shoulder` uses.
  final Hand slide;

  @override
  String get name => 'rory_o_more';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get preservesWaveOffsets => true;

  /// Where [state] lands, or `null` if the step leaves the matrix or the
  /// dancer has no side to step toward.
  ///
  /// Deliberately does **not** reuse `waveOffsetColumn`: that helper holds a
  /// dancer in place when the step would go off-grid and returns no
  /// displacement at all for an across-facing dancer. Both of those are silent
  /// no-ops here, and a figure that quietly moves nobody is the one outcome
  /// this compiler refuses to produce.
  Position? _landing(Formation formation, DancerState state) {
    final step = slide == Hand.right
        ? state.facing.turnedRight
        : state.facing.turnedLeft;
    final target = switch (step) {
      Facing.acrossEast => Position(state.row, state.col + 1),
      Facing.acrossWest => Position(state.row, state.col - 1),
      Facing.up => Position(state.row - 1, state.col),
      Facing.down => Position(state.row + 1, state.col),
      // A dancer who is not facing anywhere in particular has no right and no
      // left, so there is nothing to resolve the slide against.
      Facing.flexible => null,
    };
    if (target == null) return null;
    if (target.row < 0 || target.row >= formation.rowCount) return null;
    if (target.col < 0 || target.col >= kColumnCount) return null;
    return target;
  }

  /// Every slider paired with the cell they land in, or the reason they cannot.
  Result<Map<DancerId, Position>, OpError> _slides(Formation formation) {
    final landings = <DancerId, Position>{};
    for (final id in formation.dancers.keys) {
      if (!whoIncludes(formation, id, who)) continue;
      final state = formation.stateOf(id);
      final target = _landing(formation, state);
      if (target == null) {
        return Err<Map<DancerId, Position>, OpError>(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'rory_o_more cannot slide ${slide.key}: $id is at '
            '(${state.row}, ${state.col}) facing ${state.facing.label} and the '
            'step leaves the set. A wave slides only toward the hand its '
            'dancers can reach, so this is the other wave\'s slide',
          ),
        );
      }
      landings[id] = target;
    }
    // No empty-selection guard: every value in the `who` vocabulary selects by
    // an attribute each dancer carries — role, number, or "everyone" — so a
    // populated formation always yields at least one slider, and an empty one
    // is not reachable from any dance.
    // With a scoped `who` the sliders can land on a dancer who is standing
    // still, and two sliders facing opposite ways can land on each other.
    // Formation's factory would throw on the collision; refusing here reports
    // it as the dance error it is.
    final held = {
      for (final id in formation.dancers.keys)
        if (!landings.containsKey(id)) formation.stateOf(id).position: id,
    };
    final taken = <Position, DancerId>{};
    for (final entry in landings.entries) {
      final blocker = held[entry.value] ?? taken[entry.value];
      if (blocker != null) {
        return Err<Map<DancerId, Position>, OpError>(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'rory_o_more would slide ${entry.key} onto $blocker at '
            '${entry.value}; two dancers cannot share a cell',
          ),
        );
      }
      taken[entry.value] = entry.key;
    }
    return Ok<Map<DancerId, Position>, OpError>(landings);
  }

  @override
  OpError? checkPreconditions(Formation formation) =>
      _slides(formation).errorOrNull;

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      _slides(formation).map(
        (landings) => formation.withUpdates({
          for (final entry in landings.entries)
            entry.key: formation
                .stateOf(entry.key)
                .copyWith(position: entry.value),
        }),
      );

  @override
  bool operator ==(Object other) =>
      other is RoryOMore &&
      other.who == who &&
      other.balance == balance &&
      other.slide == slide;

  @override
  int get hashCode => Object.hash(name, who, balance, slide);

  @override
  String toString() => 'rory_o_more(${who.key}, slide: ${slide.key})';
}
