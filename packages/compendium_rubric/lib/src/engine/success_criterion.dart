import 'package:meta/meta.dart';

import '../domain/couple_number.dart';
import '../domain/dancer.dart';
import '../domain/facing.dart';
import '../domain/formation.dart';
import '../domain/position.dart';
import '../domain/role.dart';
import '../geometry/geometry.dart';
import 'end_normalization.dart';

/// A named success condition: what the dance is *supposed* to achieve
/// (`docs/architecture.md` §8.2, D6).
///
/// A criterion computes its [expected] end state **independently**, from the
/// input formation alone (§3.4). It never inspects the operation list, so it
/// is a genuine oracle rather than a restatement of what the figures did — a
/// dance that lands somewhere else produces a [Mismatch] precisely because the
/// two computations had no chance to agree by construction.
///
/// Sealed so the compiler can switch exhaustively, and so the criterion set
/// stays as closed as the operation taxonomy.
@immutable
sealed class SuccessCriterion {
  const SuccessCriterion();

  /// The registry key — the `criterion` field in the external JSON.
  String get name;

  /// Extra hands four this criterion requires beyond the base (§3.1, D7).
  int get hands4Contribution;

  /// The state the dance must land in, computed from [input] alone.
  Formation expected(Formation input);
}

/// "The dance progresses [count] times" — Single (1), Double (2), Triple (3).
///
/// Parameterized by count rather than modelled as three separate criteria so
/// sizing and logic scale uniformly (§8.2).
///
/// The computation is the **net displacement** of a progression
/// (`docs/fundamentals.md` §10.6), not the per-figure progression mechanic.
/// The two are deliberately different things: a progression-flagged figure runs
/// the state-driven end-normalization of §10.2, while this reference walks the
/// whole set by construction. Their agreeing is the entire test.
final class ProgressionCriterion extends SuccessCriterion {
  const ProgressionCriterion({this.count = 1})
    : assert(count >= 1, 'a progression criterion needs at least one round');

  /// How many progressions the dance performs.
  final int count;

  @override
  String get name => 'progression';

  /// A single progression fits in the base two hands four; each additional
  /// round needs another (§3.1: *"a **double** progression adds room a single
  /// does not"*, and its worked example — double + one expanding figure ⇒ four
  /// hands four ⇒ the double contributes exactly `+1`).
  @override
  int get hands4Contribution => count - 1;

  @override
  Formation expected(Formation input) {
    var state = input;
    for (var round = 0; round < count; round++) {
      state = _oneProgression(state);
    }
    return state;
  }

  /// One round of net displacement, followed by the same end-normalization a
  /// progression-flagged figure would run.
  ///
  /// Reusing [applyEndNormalization] here is deliberate. The end behaviour —
  /// take the end's number, turn back into the set, normalize, change over the
  /// waiting couples — is stated once in §10.2/§10.3.2 and is identical
  /// whichever path reaches it; duplicating it in the oracle would let the two
  /// drift apart, which is the one failure mode an independent oracle must not
  /// have.
  Formation _oneProgression(Formation formation) => applyEndNormalization(
    _shift(formation),
    servedRound: waitingCouples(formation),
  );

  /// Moves every dancer still in the set one row along their line, and brings
  /// the waiting couples back in.
  ///
  /// In **Duple Improper** a couple standing out is already lying the way a DI
  /// couple lies — along a row — so re-entry costs it no movement at all
  /// (§10.3.2's worked table: B and C simply stay where they are, and the
  /// change-over alone puts them back in a hands four).
  ///
  /// In **Becket** it does not: a couple collected across an end row is lying
  /// *across* the set, but a Becket couple lies *along a column*. §10.6 is
  /// explicit that such a couple **re-enters on the opposite line** — the line
  /// whose number it took at the end — so for Becket the re-entry is a real
  /// move, and the oracle has to make it.
  Formation _shift(Formation formation) {
    final targets = <DancerId, int>{};
    for (final entry in formation.dancers.entries) {
      if (entry.value.waitingOut) continue;
      targets[entry.key] = entry.value.position.row + _delta(formation, entry);
    }

    final changes = <DancerId, DancerState>{};
    final collected = <int>{};
    for (final entry in targets.entries) {
      final row = entry.value;
      if (row >= 0 && row <= formation.lastRow) continue;
      // A partner has run off an end, so the whole couple collects into that
      // end row (§10.6) rather than half of it sliding into nothing.
      collected.add(entry.key.coupleIndex);
    }

    for (final coupleIndex in collected) {
      final offTop = targets.entries.any(
        (e) => e.key.coupleIndex == coupleIndex && e.value < 0,
      );
      final row = offTop ? 0 : formation.lastRow;
      final facing = offTop ? Facing.down : Facing.up;
      _placeCouple(
        formation,
        changes,
        coupleIndex: coupleIndex,
        placement: normalizeAlongHall(row: row, facing: facing),
        facing: facing,
      );
    }

    if (formation.type.couplesShareColumn) {
      _reenterWaitingCouples(formation, changes);
    }

    for (final entry in targets.entries) {
      if (collected.contains(entry.key.coupleIndex)) continue;
      final state = formation.stateOf(entry.key);
      changes[entry.key] = state.copyWith(
        position: Position(entry.value, state.position.col),
      );
    }
    return formation.withUpdates(changes);
  }

  /// Stands each waiting Becket couple back up on its destination line.
  ///
  /// §10.6: *"It then re-enters on the **opposite line**, where that number is
  /// the line's number (a 1 travels down c4; a 2 travels up c0)."* The couple
  /// took its number from the end it reached, so the number already names the
  /// line — `#1 ⇒ c4`, `#2 ⇒ c0`, in both Becket senses. It re-enters from the
  /// end it is sitting at, taking that end row and the one beside it, and
  /// normalizes across facing into the set like any other side couple.
  void _reenterWaitingCouples(
    Formation formation,
    Map<DancerId, DancerState> changes,
  ) {
    final waiting = <int, DancerState>{};
    for (final entry in formation.dancers.entries) {
      if (entry.value.waitingOut) waiting[entry.key.coupleIndex] = entry.value;
    }

    for (final entry in waiting.entries) {
      final atTop = entry.value.position.row == 0;
      final col = entry.value.number == CoupleNumber.one ? kColumnCount - 1 : 0;
      final facing = col == 0 ? Facing.acrossEast : Facing.acrossWest;
      _placeCouple(
        formation,
        changes,
        coupleIndex: entry.key,
        placement: normalizeAcross(
          col: col,
          topRow: atTop ? 0 : formation.lastRow - 1,
          facing: facing,
        ),
        facing: facing,
      );
    }
  }

  void _placeCouple(
    Formation formation,
    Map<DancerId, DancerState> changes, {
    required int coupleIndex,
    required CouplePlacement placement,
    required Facing facing,
  }) {
    for (final id in formation.dancers.keys) {
      if (id.coupleIndex != coupleIndex) continue;
      changes[id] = formation
          .stateOf(id)
          .copyWith(
            position: id.role == Role.lark ? placement.lark : placement.robin,
            facing: facing,
          );
    }
  }

  /// Which way one dancer travels, in rows.
  ///
  /// Delegates to [travelDirection], which is shared with the cross-hands-four
  /// dancer sets so that "on down the set" cannot come to mean two different
  /// things in two places. The rule itself is §10.3.1's: Duple Improper couples
  /// share a row and travel by **number**, Becket couples share a column and
  /// travel by **line**.
  int _delta(Formation formation, MapEntry<DancerId, DancerState> dancer) =>
      travelDirection(formation, dancer.key);

  @override
  bool operator ==(Object other) =>
      other is ProgressionCriterion && other.count == count;

  @override
  int get hashCode => Object.hash(name, count);

  @override
  String toString() => 'progression(x$count)';
}
