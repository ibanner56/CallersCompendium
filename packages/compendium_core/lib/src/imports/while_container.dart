import '../model/figure.dart';

/// Moves that can be the CORE of a `while` modifier: whole-set moves whose
/// dancing another group can change without becoming a separate group.
const Set<String> _whileCoreMoves = {'long_lines', 'slice'};

/// Moves that MODIFY a [_whileCoreMoves] core when written after `while`.
const Set<String> _whileModifierMoves = {'roll_away', 'give_and_take'};

/// The regex both front-ends split a `while` line on. `whiles` is ContraDB's
/// spelling; `while` alone would cut it mid-word without the word boundary.
final RegExp whileConnective = RegExp(r'\bwhiles?\b', caseSensitive: false);

/// Decides whether the two [sides] of an `A while B` line are a **modifier**
/// (`B` changes how `A`, a whole-set move, is danced) and, if so, builds the
/// [Figure.modifier] container. Returns `null` for anything else, so each
/// front-end keeps its existing behaviour for the line: ContraDB builds a
/// [Figure.meanwhile] (two groups acting at once), Caller's Box leaves the line
/// custom.
///
/// The one place both front-ends make this call, so they cannot drift apart. A
/// line is a modifier only when it is exactly two structured sides in
/// core-first order: `long_lines` or `slice`, then `roll_away` or
/// `give_and_take` (ContraDB's take-only `give: false` included; `give` is not
/// inspected). A custom side, a container side, a reversed order and any other
/// pairing all decline: the reversed line does not say which side is the core,
/// and a genuine `larks X while robins Y` is two groups.
///
/// The source states one combined beat total, which rides on the container
/// ([beats]); the children carry none, the same rule the `||` fan-out follows.
Figure? whileModifierContainer(
  List<Figure> sides, {
  required int beats,
  bool progression = false,
}) {
  if (sides.length != 2) return null;
  final core = sides[0];
  final modifier = sides[1];
  if (core.isCustom || core.isContainer) return null;
  if (modifier.isCustom || modifier.isContainer) return null;
  if (!_whileCoreMoves.contains(core.move)) return null;
  if (!_whileModifierMoves.contains(modifier.move)) return null;
  return Figure.modifier(
    figures: sides,
    beats: beats < 0 ? 0 : beats,
    progression: progression,
  );
}
