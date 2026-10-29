import '../model/figure.dart';

/// Gives a line's lone box circulate the balance its beats imply (maintainer
/// decision, #1975): 8 beats is a balance and circulate, 4 a circulate alone.
///
/// Applied only where the beats are settled and are the box circulate's own:
/// a line that produced exactly one figure. A line that split (`;`, a compound
/// beats prefix) spreads its total in ways that say nothing about one piece.
/// The flag is set explicitly both ways because the renderer shows a box
/// circulate's balance when the flag is absent. A balance the line already
/// states, or any other beat count, is left as it is.
List<Figure> withBeatImpliedBalance(List<Figure> lineFigures) {
  if (lineFigures.length != 1) return lineFigures;
  final figure = lineFigures.single;
  final implied = beatImpliedBalance(figure);
  return identical(implied, figure) ? lineFigures : [implied];
}

/// [withBeatImpliedBalance] for a single figure known to be the whole line.
Figure beatImpliedBalance(Figure figure) {
  if (figure.move != 'box_circulate' || figure.params.containsKey('balance')) {
    return figure;
  }
  final balance = switch (figure.params['beats']) {
    8 => true,
    4 => false,
    _ => null,
  };
  if (balance == null) return figure;
  return figure.copyWith(params: {...figure.params, 'balance': balance});
}
