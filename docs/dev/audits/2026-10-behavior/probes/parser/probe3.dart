import 'package:compendium_core/compendium_core.dart';

void main(List<String> args) {
  final t = contraTaxonomy;
  for (final q0 in args) {
    final q = q0.trim().toLowerCase();
    String? first;
    for (final m in t.moves.values) {
      if (m.displayName.toLowerCase().contains(q) || m.id.toLowerCase().contains(q) || m.searchKeywords.any((k) => k.toLowerCase().contains(q))) { first = '${m.id} (${m.displayName})'; break; }
    }
    if (first == null) {
      for (final a in t.aliases.values) {
        if (a.displayName.toLowerCase().contains(q) || a.id.toLowerCase().contains(q) || a.searchKeywords.any((k) => k.toLowerCase().contains(q))) { first = 'alias ${a.id}'; break; }
      }
    }
    print('"$q0" -> ${first ?? "(no option: parsed as free text)"}');
  }
}
