import 'package:compendium_core/compendium_core.dart';

void main(List<String> args) {
  final d = Dialect.larksRobins;
  final r = FigureRenderer(contraTaxonomy);
  for (final line in args) {
    final figs = parseFreeTextFigureEntry(line, taxonomy: contraTaxonomy, dialect: d);
    for (final f in figs) {
      if (!f.isCustom) { print('[$line] -> structured ${r.renderSummary(f, d)}'); continue; }
      final t = f.params['text'] as String;
      final saved = canonicalizeText(t, d);
      final shown = r.renderFreeText(saved, d);
      print('[$line] -> parsed text [$t] -> saved [$saved] -> shown [$shown] beats=${f.params['beats']}');
    }
  }
}
