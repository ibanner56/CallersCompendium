import '../model/figure.dart';
import 'callersbox_figure_dialect.dart' show hasTopLevelSeparator;

/// Gives a line's lone box circulate the balance its beats imply (maintainer
/// decision, #1975): 8 beats is a balance and circulate, 4 a circulate alone.
///
/// Applied only where the beats are settled and are the box circulate's own:
/// a [lineText] with no top-level `;` that produced exactly one figure. A `;`
/// line spreads its total over its clauses, or keeps it on one figure while a
/// clause becomes a note, and neither says what the box circulate's own beats
/// are. The flag is set explicitly both ways because the renderer shows a box
/// circulate's balance when the flag is absent. A balance the line already
/// states, or any other beat count, is left as it is.
List<Figure> withBeatImpliedBalance(String lineText, List<Figure> figures) {
  if (figures.length != 1) return figures;
  final figure = figures.single;
  final implied = beatImpliedBalance(lineText, figure);
  return identical(implied, figure) ? figures : [implied];
}

/// [withBeatImpliedBalance] for the one [figure] read from [lineText].
Figure beatImpliedBalance(String lineText, Figure figure) {
  if (figure.move != 'box_circulate' ||
      figure.params.containsKey('balance') ||
      hasTopLevelSeparator(lineText, ';')) {
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
