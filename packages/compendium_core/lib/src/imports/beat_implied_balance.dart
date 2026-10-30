import '../model/figure.dart';
import 'callersbox_figure_dialect.dart' show hasTopLevelSeparator;

/// Gives a line's lone box circulate or square through the balance its beats
/// imply (maintainer decisions, #1975).
///
/// * **Box circulate:** 8 beats is a balance and circulate, 4 a circulate
///   alone. Any other count, or a balance the line already states, is left as
///   it is. The flag is set explicitly both ways because the renderer shows a
///   box circulate's balance when the flag is absent.
/// * **Square through:** a balance when the beats are at least twice the
///   places plus 4, so square through 2 in 8 is balanced and square through 3
///   in 8 or 2 in 4 is not. A stated balance (`balance: true`) is kept, and so
///   is a line that says `without hands`, which passes with no
///   balance-and-pull (#1971). The Caller's Box pass-list decoder writes
///   `balance: false` on a `;` list; this rule replaces it, as the maintainer
///   decided the rule applies to The Caller's Box too.
///
/// Applied only where the beats are settled and are the figure's own: a
/// [lineText] with no top-level `;` that produced exactly one figure. A `;`
/// line spreads its total over its clauses, or keeps it on one figure while a
/// clause becomes a note, and neither says what the figure's own beats are.
/// The Caller's Box applies it to a standalone line only, never to a compound
/// parent or child (maintainer decision on #1975), and to a square through only
/// after its cross-line merge, so a balance line before it still folds in.
List<Figure> withBeatImpliedBalance(String lineText, List<Figure> figures) {
  if (figures.length != 1) return figures;
  final figure = figures.single;
  final implied = beatImpliedBalance(lineText, figure);
  return identical(implied, figure) ? figures : [implied];
}

/// [withBeatImpliedBalance] for the one [figure] read from [lineText].
Figure beatImpliedBalance(String lineText, Figure figure) {
  if (hasTopLevelSeparator(lineText, ';')) return figure;
  final beats = figure.params['beats'];
  final bool? balance;
  switch (figure.move) {
    case 'box_circulate':
      if (figure.params.containsKey('balance')) return figure;
      balance = switch (beats) {
        8 => true,
        4 => false,
        _ => null,
      };
    case 'square_through':
      if (figure.params['balance'] == true ||
          _withoutHands.hasMatch(lineText) ||
          beats is! int) {
        return figure;
      }
      final places = figure.params['places'] ?? _squareThroughPlaces;
      if (places is! int) return figure;
      balance = beats >= 2 * places + 4;
    default:
      return figure;
  }
  if (balance == null || figure.params['balance'] == balance) return figure;
  return figure.copyWith(params: {...figure.params, 'balance': balance});
}

/// The `square_through` MoveDef's default places, used when a line states no
/// count (`Square through`).
const int _squareThroughPlaces = 2;

final RegExp _withoutHands = RegExp(
  r'\bwithout\s+hands\b',
  caseSensitive: false,
);
