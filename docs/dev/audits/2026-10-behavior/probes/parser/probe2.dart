import 'package:compendium_core/compendium_core.dart';

void dump(Figure f, String ind) {
  print('$ind move=${f.move} params=${f.params} note=${f.note} custom=${f.isCustom} assumed=${f.assumedSubject}');
  for (final c in f.subFigures) dump(c, '$ind  ');
}

void main(List<String> args) {
  final d = Dialect.larksRobins;
  for (final line in args) {
    print('== $line');
    final figs = parseFreeTextFigureEntry(line, taxonomy: contraTaxonomy, dialect: d);
    for (final f in figs) {
      dump(f, ' ');
      print('  validate: ${contraTaxonomy.validateFigure(f).map((i) => '${i.severity.name}:${i.message}').toList()}');
    }
  }
}
