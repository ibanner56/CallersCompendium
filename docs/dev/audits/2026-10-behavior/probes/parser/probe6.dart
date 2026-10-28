import 'package:compendium_core/compendium_core.dart';
void main() {
  final r = FigureRenderer(contraTaxonomy);
  final d = Dialect.larksRobins;
  for (final f in [
    Figure(move: 'hey', params: {'length': 'full'}),
    Figure(move: 'hey', params: {'length': 'half'}),
    Figure(move: 'petronella', params: {'balance': true}),
    Figure(move: 'long_lines', params: {'goBack': false}),
  ]) {
    print('render="${r.render(f, d)}"  summary="${r.renderSummary(f, d)}"');
  }
}
