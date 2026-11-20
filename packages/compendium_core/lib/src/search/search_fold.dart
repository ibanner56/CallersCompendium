import 'title_sort_key.dart';

/// The SQL function that folds a value for an accent-insensitive search:
/// `cc_fold(text)` is [foldForSearch] of `text` with its surrounding
/// whitespace trimmed (lowercased, accents removed), or NULL for a NULL or
/// non-text argument. The search calls it only for a value that is not all
/// ASCII, and folds an ASCII value with SQLite's own `LIKE`, `lower` and
/// `trim`.
///
/// `applyCompendiumSqliteSetup` registers it on every connection. An All
/// fields or Author search compiles to it (the meter, key and interpreter
/// matches), so a connection opened without that setup fails those searches
/// with "no such function".
const String searchFoldSqlFunction = 'cc_fold';

/// Folds [text] for an accent-insensitive comparison: lowercased, with
/// combining marks removed, so "Émile" and "emile" fold alike, as they do in
/// the Collection's text index (`remove_diacritics`). The same fold the
/// title surfaces use ([foldForTitleMatch]).
String foldForSearch(String text) => foldForTitleMatch(text);
