import '../domain/dancer.dart';
import '../domain/facing.dart';
import '../domain/formation.dart';
import '../domain/role.dart';
import '../geometry/geometry.dart';

/// Applies the progression **end-normalization** of `docs/fundamentals.md`
/// §10.2 to [formation].
///
/// This runs *after* a progression-flagged operation's own transform
/// (`docs/architecture.md` §3.2). Progression is only ever triggered by that
/// explicit flag — never inferred from the matrix (§10.1) — so this function
/// deliberately performs no "does this look progressed?" test.
///
/// Each end is evaluated independently; one end may normalize while the other
/// is skipped.
///
/// **Waiting-out lifecycle (§10.3).** A progression is also the moment the
/// standing-out couples change over, and the two halves happen in order:
///
/// 1. **Clear** — every dancer currently marked as waiting out has now served
///    their round (§10.6: *"wait-out = one round"*) and re-enters the set.
/// 2. **Mark** — the sole whole couple at each end (§10.2.1) is normalized and
///    marked as waiting out, *unless* it is one of the couples just cleared.
///
/// The exemption in step 2 is what makes the change-over actually happen. A
/// couple standing out is outside every active hands four, so no figure's
/// transform touches it and it is still sitting in the end row when the next
/// progression fires; without the exemption it would simply be re-marked and
/// wait out forever. Worked through on a four-row Duple Improper set:
///
/// | | Marked before | After the figure's transform | Result |
/// |---|---|---|---|
/// | Progression 1 | nobody | B / A / D / C | mark B and C; active band `(1,2)` |
/// | Progression 2 | B, C | B / D / A / C | clear both, both exempt; bands `(0,1)` = B,D and `(2,3)` = A,C |
///
/// **Idempotent in the matrix, deliberately not in waiting-out state.** Because
/// the end number is assigned from the end reached rather than flipped
/// (`FormationType.topEndNumber`), re-applying this leaves every position,
/// number and facing exactly as it found them — the movement in a progression
/// comes from the figure's own transform, not from this step. The change-over
/// in step 1 above *is* stateful, and must be: it is what counts the round.
///
/// **[servedRound] is read from the state the figure *started* in.** For every
/// figure but one, who is standing out before and after the transform is the
/// same set, so this is invisible. `slide_along_set` is the exception: it
/// re-bands the set and so decides its own waiting-out state, and taking the
/// served list from the state it produced would immediately retire the couples
/// it had just sent out — clearing them and then exempting them from being
/// re-marked, so the pair collected at each end would never take their end
/// number. Reading it from before the figure ran retires only couples that had
/// genuinely already served a round.
///
/// Omitted, it is derived from [formation] itself. That is correct for any
/// caller whose transform left waiting-out state alone, which is every figure
/// but the slide; [OperationInvocation.apply] passes it explicitly because it
/// is the one path that must be right for all of them.
Formation applyEndNormalization(Formation formation, {Set<int>? servedRound}) {
  final served = servedRound ?? waitingCouples(formation);

  var result = formation.withUpdates({
    for (final entry in formation.dancers.entries)
      if (entry.value.waitingOut)
        entry.key: entry.value.copyWith(waitingOut: false),
  });

  // A set-of-rows, so a degenerate single-row matrix is not processed twice.
  final endRows = <int>{0, result.lastRow};
  for (final row in endRows) {
    result = _normalizeEndRow(result, row, exempt: served);
  }
  return result;
}

/// The couples with a dancer currently standing out.
///
/// The exemption list for [applyEndNormalization]: read from the state a figure
/// *started* in, so that a figure which changes waiting-out state itself does
/// not have its own work retired on the same beat.
Set<int> waitingCouples(Formation formation) => {
  for (final entry in formation.dancers.entries)
    if (entry.value.waitingOut) entry.key.coupleIndex,
};

/// Normalizes one end row, or returns [formation] unchanged if that row does
/// not hold exactly one whole couple.
///
/// **Selection is by whole couple** (§10.2.1). §10.6 describes the mechanic as
/// *"a **couple** that reaches an end **collects into that end row**"*, and in
/// every one of the five documented reference states (§10.5 plus §10.6's four)
/// an end row holds both partners of one couple. Requiring both partners is
/// what makes it structurally impossible for this step to leave a couple
/// holding two different numbers — a number is a property of the couple, so it
/// is only ever written for both partners at once.
///
/// Anything else is a **silent skip**: an empty row, a lone dancer, a
/// non-partner pair, or a line of four (§8.1 — two whole couples in one row is
/// an entire hands four, not an end couple). The figure's own transform stands
/// and later figures are expected to resolve the shape.
///
/// A couple whose index is in [exempt] has just finished waiting out and is
/// re-entering the set, so it is left entirely alone — position, number and
/// facing all stand.
Formation _normalizeEndRow(
  Formation formation,
  int row, {
  required Set<int> exempt,
}) {
  final couple = _soleWholeCoupleIn(formation, row);
  if (couple == null) return formation;
  if (exempt.contains(couple.lark.coupleIndex)) return formation;

  // They have reached an end and turn back into the set.
  final facing = row == 0 ? Facing.down : Facing.up;
  final number = row == 0
      ? formation.type.topEndNumber
      : formation.type.bottomEndNumber;
  final placement = normalizeAlongHall(row: row, facing: facing);

  return formation.withUpdates({
    couple.lark: formation
        .stateOf(couple.lark)
        .copyWith(
          position: placement.lark,
          number: number,
          facing: facing,
          waitingOut: true,
        ),
    couple.robin: formation
        .stateOf(couple.robin)
        .copyWith(
          position: placement.robin,
          number: number,
          facing: facing,
          waitingOut: true,
        ),
  });
}

/// The one couple with **both** partners in [row], or `null` when there is no
/// such couple or more than one.
({DancerId lark, DancerId robin})? _soleWholeCoupleIn(
  Formation formation,
  int row,
) {
  final byCouple = <int, List<DancerId>>{};
  for (final id in formation.dancersInRow(row)) {
    byCouple.putIfAbsent(id.coupleIndex, () => []).add(id);
  }

  ({DancerId lark, DancerId robin})? found;
  for (final members in byCouple.values) {
    if (members.length != 2) continue;
    // A DancerId is (couple, role) and is a map key, so two entries sharing a
    // couple index necessarily differ in role — but assert it rather than
    // relying on that invariant holding forever.
    final lark = members.where((id) => id.role == Role.lark).firstOrNull;
    final robin = members.where((id) => id.role == Role.robin).firstOrNull;
    if (lark == null || robin == null) continue;
    // Two whole couples in one row is a line of four, not an end couple.
    if (found != null) return null;
    found = (lark: lark, robin: robin);
  }
  return found;
}
