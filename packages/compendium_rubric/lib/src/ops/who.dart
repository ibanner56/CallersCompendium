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
    WhoSet.role1s => a.role == Role.lark && b.role == Role.lark,
    WhoSet.role2s => a.role == Role.robin && b.role == Role.robin,
    WhoSet.ones =>
      stateA.number == CoupleNumber.one && stateB.number == CoupleNumber.one,
    WhoSet.twos =>
      stateA.number == CoupleNumber.two && stateB.number == CoupleNumber.two,
    WhoSet.everyone => true,
  };
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
bool whoIncludes(Formation formation, DancerId id, WhoSet who) {
  final state = formation.stateOf(id);
  return switch (who) {
    WhoSet.everyone ||
    WhoSet.partners ||
    WhoSet.neighbors ||
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
/// Returns every unordered pair of dancers in the band that satisfies [who].
/// Used by the figures that *act on* a named pair (`do_si_do`) rather than
/// those that merely validate one (`swing`).
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
  final pairs = <({DancerId a, DancerId b})>[];
  final taken = <DancerId>{};
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
/// Both starting formations lay couple `2k` and couple `2k + 1` out as hands
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
