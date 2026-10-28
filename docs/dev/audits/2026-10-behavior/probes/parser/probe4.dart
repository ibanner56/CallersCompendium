import 'package:compendium_core/compendium_core.dart';

void main() {
  final t = contraTaxonomy;
  final r = FigureRenderer(t);
  final d = Dialect.larksRobins;
  bool m(String q, String id, String dn, String dl, List<String> kw) =>
      dn.toLowerCase().contains(q) || dl.toLowerCase().contains(q) || id.toLowerCase().contains(q) || kw.any((k) => k.toLowerCase().contains(q));
  for (final target in t.moves.values) {
    final q = r.displayMoveName(target.id, d).toLowerCase();
    MoveDef? first;
    for (final mv in t.moves.values) {
      if (m(q, mv.id, mv.displayName, r.displayMoveName(mv.id, d), mv.searchKeywords)) { first = mv; break; }
    }
    if (first != null && first.id != target.id) print('typing "$q" + Enter picks ${first.id} ("${r.displayMoveName(first.id, d)}") not ${target.id}');
  }
}
