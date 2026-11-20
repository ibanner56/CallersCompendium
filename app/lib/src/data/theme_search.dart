import 'package:compendium_core/compendium_core.dart' show foldForTitleMatch;

/// The words a query is split into: runs of letters and digits, so
/// punctuation and spacing never have to match ("rosé-pine" searches for
/// "rosé" and "pine"; "synthwave '84" for "synthwave" and "84").
final RegExp _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// What one theme on the Theme screen can be found by.
///
/// [names] are matched anywhere inside (a search for "night" finds
/// "Tokyo Night"); [terms] are keyword words — color and character words,
/// section and brightness headings — matched from their start, so typing
/// "re" offers red and retro but not every theme tagged green.
///
/// Both are folded once, here, with the same case- and accent-insensitive fold
/// the Collection's title search uses, so "rose" finds "Rosé Pine" and
/// "frappe" finds "Catppuccin Frappé".
class ThemeSearchEntry {
  ThemeSearchEntry({
    required Iterable<String> names,
    required Iterable<String> terms,
  }) : _names = [for (final n in names) foldForTitleMatch(n)],
       _terms = [
         for (final t in terms)
           for (final word in foldForTitleMatch(t).split(_separators))
             if (word.isNotEmpty) word,
       ];

  final List<String> _names;
  final List<String> _terms;

  /// Whether this theme answers [query]: every word of the query must be found
  /// in a name or start a term, so "dark purple" narrows to the dark themes
  /// that are purple. A query with no words matches everything.
  bool matches(String query) {
    for (final word in foldForTitleMatch(query).split(_separators)) {
      if (word.isEmpty) continue;
      final found =
          _names.any((name) => name.contains(word)) ||
          _terms.any((term) => term.startsWith(word));
      if (!found) return false;
    }
    return true;
  }
}

/// Whether [query] has anything to search for once its punctuation and
/// spacing are set aside. The Theme screen shows its grouped gallery until it
/// does, so a query of a lone space or comma never collapses the headings.
bool themeQueryIsEmpty(String query) =>
    foldForTitleMatch(query).split(_separators).every((w) => w.isEmpty);
