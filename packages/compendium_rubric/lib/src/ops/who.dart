import 'dart:async';

import '../domain/couple_number.dart';
import '../domain/dancer.dart';
import '../domain/formation.dart';
import '../domain/role.dart';
import '../geometry/geometry.dart';
import 'diagnostics.dart';
import 'params.dart';

/// Whether [a] and [b] stand in the relationship named by [who].
///
/// `docs/taxonomy.md` ("`who` semantics"), read within a single hands four
/// `L1-x / R1-x / L2-y / R2-y`. This is a **validation** predicate: figures like
/// `swing` pair whoever is physically in position and use `who` only to check
/// that the dancers who ended up together are the ones the caller named.
///
/// The cross-hands-four sets test the same thing `neighbors` does. That is not
/// a shortcut: [Operation.apply] re-bands the set *before* the figure runs, so
/// by the time any figure asks, your next neighbours are simply the neighbours
/// you are standing with. The part that is genuinely about *which* grouping
/// they came from is checked once, in [crossHandsFourRefusal], against the
/// grouping structure the figure was handed.
bool whoMatches(Formation formation, DancerId a, DancerId b, WhoSet who) {
  final stateA = formation.stateOf(a);
  final stateB = formation.stateOf(b);
  return switch (who) {
    WhoSet.partners => a.coupleIndex == b.coupleIndex,
    // Opposite role, different couple, and different number - all three, which
    // is what separates a neighbour from a partner or a same-role pairing.
    WhoSet.neighbors ||
    WhoSet.prevNeighbors ||
    WhoSet.nextNeighbors ||
    WhoSet.thirdNeighbors ||
    WhoSet.fourthNeighbors =>
      a.coupleIndex != b.coupleIndex &&
          a.role != b.role &&
          stateA.number != stateB.number,
    // Opposite role, different couple, and the SAME number: your partner's
    // counterpart one hands four along. Read from the current numbers, which
    // the end of the set flips (§10.3), so a couple waiting out at an end has
    // the 1s or 2s beside it as its shadows. At an end with no couple out,
    // the shadow wraps round to your neighbour. *(User-ruled 2026-11-22: "If
    // there's a couple out at the top, then that's your shadow. If there's no
    // one out at the top, then it wraps around to your neighbor.")*
    WhoSet.shadows =>
      a.coupleIndex != b.coupleIndex &&
          a.role != b.role &&
          (stateA.number == stateB.number ||
              _wrapsAtAnEnd(formation, stateA.row, stateB.row)),
    WhoSet.role1s => a.role == Role.lark && b.role == Role.lark,
    WhoSet.role2s => a.role == Role.robin && b.role == Role.robin,
    WhoSet.ones =>
      stateA.number == CoupleNumber.one && stateB.number == CoupleNumber.one,
    WhoSet.twos =>
      stateA.number == CoupleNumber.two && stateB.number == CoupleNumber.two,
    WhoSet.everyone => true,
  };
}

/// Whether rows [rowA] and [rowB] both lie in the hands four at an end of the set
/// with no couple waiting out beyond it, where a shadow wraps to a neighbour.
bool _wrapsAtAnEnd(Formation formation, int rowA, int rowB) {
  final bands = handsFourBands(formation);
  if (bands.isEmpty) return false;
  final waiting = waitingOutRows(formation);
  bool holds(({int topRow, int bottomRow}) band) =>
      {band.topRow, band.bottomRow}.containsAll({rowA, rowB});
  final top = bands.first;
  final bottom = bands.last;
  return (holds(top) && waiting.every((row) => row > top.topRow)) ||
      (holds(bottom) && waiting.every((row) => row < bottom.bottomRow));
}

/// Whether [id] is one of the dancers [who] names.
///
/// The unary counterpart of [whoMatches], for the figures that act on a *set*
/// of dancers rather than on pairs (`turn_alone`).
///
/// The relational sets are total: every dancer has a partner and a neighbour,
/// so `partners` and `neighbors` include everyone. They narrow *pairings*, not
/// membership, which is why they mean something quite different here than they
/// do in [whoMatches].
///
/// `shadows` is total on the same reasoning. A figure naming it is only
/// reached once [Operation.apply] has found the shadows standing together
/// (unless it also names a distance set), so a unary figure naming shadows is
/// refused there when they are not. `form_long_waves` reads its `who` here
/// with no such check, which is why the parser defers `shadows` there.
bool whoIncludes(Formation formation, DancerId id, WhoSet who) {
  final state = formation.stateOf(id);
  return switch (who) {
    WhoSet.everyone ||
    WhoSet.partners ||
    WhoSet.neighbors ||
    WhoSet.shadows ||
    WhoSet.prevNeighbors ||
    WhoSet.nextNeighbors ||
    WhoSet.thirdNeighbors ||
    WhoSet.fourthNeighbors => true,
    WhoSet.role1s => id.role == Role.lark,
    WhoSet.role2s => id.role == Role.robin,
    WhoSet.ones => state.number == CoupleNumber.one,
    WhoSet.twos => state.number == CoupleNumber.two,
  };
}

/// The pairs [who] names inside the band bounded by [topRow] and [bottomRow].
///
/// Pairs the band's dancers first match first, so a dancer who matches two
/// others pairs with the first, and a dancer left with no match stays
/// unpaired. Used by the figures that *act on* a named pair (`do_si_do`)
/// rather than those that merely validate one (`swing`).
///
/// For `shadows`, two dancers who remember each other as shadows
/// ([DancerState.shadow]) pair first, and the rest pair first match first.
/// Your shadow is the same dancer all dance *(user-ruled 2026-11-23)*; at an
/// end with nobody out the first match could otherwise take one of a
/// remembered pair, since the wrap lets a neighbour match too. Only a mutual
/// memory counts, since a one-sided one is not a pair that danced *(agent's
/// call, 2026-11-24)*.
///
/// Where keeping the remembered pairs leaves dancers unpaired who could all
/// have been paired, with a remembered pair beside each other
/// ([shadowMemoryStrandsDancers]), the remembered pairs are still returned and
/// the band is reported to the enclosing [watchShadowStrands], whose figure is
/// then refused: it never falls back to another pairing. Anywhere else,
/// remembered pairs that would leave more dancers unpaired than first match
/// give way to first match.
List<({DancerId a, DancerId b})> resolveWhoPairs(
  Formation formation,
  WhoSet who, {
  required int topRow,
  required int bottomRow,
}) {
  final members = [
    ...formation.dancersInRow(topRow),
    ...formation.dancersInRow(bottomRow),
  ];
  if (who != WhoSet.shadows) {
    return _pairFirstMatch(formation, who, members, const []);
  }
  final remembered = _rememberedShadowPairs(formation, members);
  final pairs = _pairFirstMatch(formation, who, members, remembered);
  if (_strands(formation, members, remembered, pairs)) {
    final onStrand = Zone.current[_strandsKey];
    if (onStrand is void Function(int topRow, int bottomRow)) {
      onStrand(topRow, bottomRow);
    }
    return pairs;
  }
  // Outside the case ruled on, remembered pairs that would leave more dancers
  // unpaired than first match give way to first match, as they did before the
  // ruling *(agent's call, 2026-11-24)*.
  final firstMatch = _pairFirstMatch(formation, who, members, const []);
  return pairs.length < firstMatch.length ? firstMatch : pairs;
}

final Object _strandsKey = Object();

/// Runs [body] with no [watchShadowStrands] watching, so the pairings it
/// probes are reported to nobody.
T unwatchedShadowStrands<T>(T Function() body) =>
    Zone.current[_strandsKey] == null
    ? body()
    : runZoned(body, zoneValues: {_strandsKey: null});

/// Runs [body], calling [onStrand] for each band in which a shadows pairing
/// it asks [resolveWhoPairs] for leaves dancers stranded by the remembered
/// pairs.
///
/// A zone rather than a parameter, so that every figure that picks shadow
/// pairs, in its preconditions or its transform, primary `who` or another
/// slot, is caught without each figure having to pass anything on, and a
/// figure that only reads positions, never asking for pairs, is not.
T watchShadowStrands<T>(
  T Function() body,
  void Function(int topRow, int bottomRow) onStrand,
) => runZoned(body, zoneValues: {_strandsKey: onStrand});

/// Whether, in the band bounded by [topRow] and [bottomRow], pairing the
/// shadows who remember each other first leaves dancers unpaired who could
/// all have been paired, by any pairing at all.
///
/// The case ruled on: a remembered pair beside each other at an end with
/// nobody out, with the couple across the set from them partners and so not
/// shadows. Keeping the pair would leave that couple standing idle while the
/// figure succeeds, and pairing everyone would break the remembered pair; the
/// figure is refused *(user-ruled 2026-11-24)*. *(Agent's calls:)* comparing
/// against the largest pairing, rather than against first match, is what
/// makes the answer the same whichever way round the dancers stand; and it is
/// only asked where a remembered pair stands beside each other, as in the case
/// ruled on. A remembered pair across the set from each other, with a couple
/// beside them, is left to pair as before ([resolveWhoPairs] falls back to
/// first match there when that pairs more): at the bottom of the set that couple
/// is often the one waiting out, brought into the band only by the phase the
/// figure is danced in, and refusing there cost three dances that compile.
bool shadowMemoryStrandsDancers(
  Formation formation, {
  required int topRow,
  required int bottomRow,
}) {
  final members = [
    ...formation.dancersInRow(topRow),
    ...formation.dancersInRow(bottomRow),
  ];
  final remembered = _rememberedShadowPairs(formation, members);
  final withMemory = _pairFirstMatch(
    formation,
    WhoSet.shadows,
    members,
    remembered,
  );
  return _strands(formation, members, remembered, withMemory);
}

/// Whether [pairs], the band's shadow pairs with [remembered] taken first,
/// leave dancers unpaired who could all have been paired, where a remembered
/// pair stands beside each other in one side column.
bool _strands(
  Formation formation,
  List<DancerId> members,
  List<({DancerId a, DancerId b})> remembered,
  List<({DancerId a, DancerId b})> pairs,
) {
  final besideEachOther = remembered.any(
    (pair) => formation.stateOf(pair.a).col == formation.stateOf(pair.b).col,
  );
  return besideEachOther &&
      pairs.length < _mostPairs(formation, members, WhoSet.shadows);
}

/// The largest number of disjoint pairs [who] can make among [members].
///
/// An exhaustive search: a band holds at most a handful of dancers.
int _mostPairs(Formation formation, List<DancerId> members, WhoSet who) {
  int best(int from, Set<DancerId> taken) {
    var i = from;
    while (i < members.length && taken.contains(members[i])) {
      i++;
    }
    if (i >= members.length) return 0;
    // Leave members[i] unpaired, or pair it with any later free match.
    var most = best(i + 1, taken);
    for (var j = i + 1; j < members.length; j++) {
      if (taken.contains(members[j])) continue;
      if (!whoMatches(formation, members[i], members[j], who)) continue;
      final paired = 1 + best(i + 1, {...taken, members[i], members[j]});
      if (paired > most) most = paired;
    }
    return most;
  }

  return best(0, const {});
}

/// The pairs among [members] who remember each other as shadows and still
/// stand as shadows.
List<({DancerId a, DancerId b})> _rememberedShadowPairs(
  Formation formation,
  List<DancerId> members,
) {
  final remembered = <({DancerId a, DancerId b})>[];
  final taken = <DancerId>{};
  for (final a in members) {
    if (taken.contains(a)) continue;
    final b = formation.stateOf(a).shadow;
    if (b == null || taken.contains(b) || !members.contains(b)) continue;
    if (formation.stateOf(b).shadow != a) continue;
    if (!whoMatches(formation, a, b, WhoSet.shadows)) continue;
    remembered.add((a: a, b: b));
    taken
      ..add(a)
      ..add(b);
  }
  return remembered;
}

/// [seed] followed by [members] not in it, paired first match first.
List<({DancerId a, DancerId b})> _pairFirstMatch(
  Formation formation,
  WhoSet who,
  List<DancerId> members,
  List<({DancerId a, DancerId b})> seed,
) {
  final pairs = [...seed];
  final taken = <DancerId>{
    for (final pair in seed) ...[pair.a, pair.b],
  };
  for (var i = 0; i < members.length; i++) {
    if (taken.contains(members[i])) continue;
    for (var j = i + 1; j < members.length; j++) {
      if (taken.contains(members[j])) continue;
      if (!whoMatches(formation, members[i], members[j], who)) continue;
      pairs.add((a: members[i], b: members[j]));
      taken
        ..add(members[i])
        ..add(members[j]);
      break;
    }
  }
  return pairs;
}

/// Refuses a [who] naming a distance along the set that the set cannot serve.
///
/// Resolution rule (`docs/taxonomy.md`, "The neighbor-distance sets"): a
/// dancer's next neighbours are the **opposite-number couple one grouping on
/// in their direction of travel**, so the 1s look one grouping down the hall
/// and the 2s one grouping up. `thirdNeighbors` is two groupings on,
/// `fourthNeighbors` three, and `prevNeighbors` one grouping back.
///
/// Two things are refused here.
///
/// **Sizing.** [shifted] is the set in the phase the distance's parity names,
/// and whoever stands together there is who dances. A set with fewer groupings
/// than the distance reaches has nowhere to reach, and dancing in it would
/// leave the figure with no hands four at all — a silent no-op, which is the
/// failure this refusal exists to prevent.
///
/// **The relationship**, checked against each couple's [homeGrouping] rather
/// than against where they are standing now. This distinction is the whole
/// point: an earlier version read the grouping off the formation and had to be
/// abandoned, because travel invalidates it — half way through a grand right
/// and left the third neighbours stand *one* grouping apart, not two, since
/// the set has strung out along the hall. A couple's home grouping is fixed by
/// its letter and does not move, so the same arithmetic holds at every point
/// in a figure list, including on the way back.
OpError? crossHandsFourRefusal(
  Formation before,
  Formation shifted,
  WhoSet who,
  String moveName, {
  int? distance,
}) {
  // The set's own distance is its label at the start of the dance; the caller
  // passes what is left of it here and now. They differ once the dance has
  // progressed, and it is the remaining travel that has to be reachable.
  final effective = distance ?? who.distance;
  if (effective == null) return null;
  if (!who.isVerifiedDistance) {
    return OpError(
      ErrorKind.unsupportedParam,
      '$moveName names ${who.key}, which reaches $effective groupings along '
      'the set; the sets reached against the direction of travel have no '
      'worked example on record, so they are deferred rather than resolved on '
      'an untested rule',
    );
  }

  final reach = effective.abs();
  final groupingCount = groupingsDownTheSet(before).length;
  if (groupingCount <= reach) {
    return OpError(
      ErrorKind.unresolvableDancerSet,
      '$moveName names ${who.key}, which reaches $reach grouping(s) along the '
      'set, but the set has only $groupingCount; there is nowhere to reach, '
      'and re-banding it would leave the figure with no hands four to dance in',
    );
  }

  if (handsFourBands(shifted).isEmpty) {
    return OpError(
      ErrorKind.unresolvableDancerSet,
      '$moveName names ${who.key}, but the set re-banded to reach them holds '
      'no complete hands four, so the figure would quietly do nothing',
    );
  }

  for (final band in handsFourBands(shifted)) {
    final pairs = resolveWhoPairs(
      shifted,
      WhoSet.neighbors,
      topRow: band.topRow,
      bottomRow: band.bottomRow,
    );
    for (final pair in pairs) {
      final travel = travelDirection(shifted, pair.a);
      final actual = homeGrouping(pair.b) - homeGrouping(pair.a);
      if (actual == effective * travel) continue;

      return OpError(
        ErrorKind.whoMismatch,
        '$moveName names ${who.key}, which reaches $effective grouping(s) '
        'along the set, but ${_letter(pair.a)} and ${_letter(pair.b)} started '
        '${actual.abs()} grouping(s) apart and are standing together; the '
        'couples named are not the ones in position to dance',
      );
    }
  }
  return null;
}

/// The grouping a couple began the repetition in, fixed by its letter.
///
/// Every starting formation lays couple `2k` and couple `2k + 1` out as hands
/// four `k` (`lib/src/domain/starting_formations.dart`), so this needs no
/// stored state: identity is already carried by [DancerId.coupleIndex], and
/// the arithmetic that turns it into a grouping is a constant.
///
/// This is *home*, not *here*. A dancer part way through a grand right and
/// left is standing somewhere else entirely; that is the point. Neighbour
/// distance is measured from where you started, which is what lets a figure
/// list reach out along the set and then retrace its steps.
int homeGrouping(DancerId id) => id.coupleIndex ~/ 2;

String _letter(DancerId id) => String.fromCharCode(0x41 + id.coupleIndex);
