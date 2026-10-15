import '../dialect/canonicalize.dart';
import '../dialect/dialect.dart';
import '../model/figure.dart';
import 'taxonomy.dart';

/// Where a name a user typed for their own glossary entry already exists
/// (#709).
enum GlossaryNameSource {
  /// A shipped move's or alias's name.
  shippedFigure,

  /// A shipped move's or alias's search keyword, legacy names included.
  shippedKeyword,

  /// A move renamed by the active dialect or one of the user's dialects.
  dialectMove,

  /// One of the user's shorthand tokens.
  shorthand,

  /// Another of the user's own glossary entries.
  userEntry,
}

/// A name as names are compared: trimmed, lowercase, single-spaced.
String normalizeGlossaryName(String name) =>
    name.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

/// The sources [candidate] collides with, case-insensitively (maintainer,
/// 2026-10-14). Empty when the name is free.
///
/// [dialects] should be the active dialect and every dialect the user has
/// made, so that switching dialect cannot create a collision after the fact.
/// A dialect's `%s` placeholder is ignored, as [Dialect.validate] ignores it.
/// [userEntryNames] should leave out the entry being edited.
///
/// [candidate] may be the name as typed or as stored, canonical (#709): the
/// app compares stored names, as the Glossary flags duplicates by them. A
/// dialect's renames and the shorthand tokens are written in display words, so
/// each is compared both as written and canonicalized as its dialect would
/// store it — a rename "robins chain" and a name stored as "role2s chain" are
/// the same name to the user.
Set<GlossaryNameSource> glossaryNameCollisions(
  String candidate, {
  required Taxonomy taxonomy,
  Iterable<Dialect> dialects = const [],
  Iterable<String> shorthandTokens = const [],
  Iterable<String> userEntryNames = const [],
}) {
  final name = normalizeGlossaryName(candidate);
  if (name.isEmpty) return const {};
  bool same(String other) => normalizeGlossaryName(other) == name;
  final found = <GlossaryNameSource>{};
  for (final move in taxonomy.moves.values) {
    if (move.id == customMoveId) continue;
    if (same(move.displayName) || same(move.id)) {
      found.add(GlossaryNameSource.shippedFigure);
    }
    if (move.searchKeywords.any(same)) {
      found.add(GlossaryNameSource.shippedKeyword);
    }
  }
  for (final alias in taxonomy.aliases.values) {
    if (same(alias.displayName) || same(alias.id)) {
      found.add(GlossaryNameSource.shippedFigure);
    }
    if (alias.searchKeywords.any(same)) {
      found.add(GlossaryNameSource.shippedKeyword);
    }
  }
  bool sameIn(String written, Dialect dialect) =>
      same(written) || same(canonicalizeGlossaryText(written, dialect));
  for (final dialect in dialects) {
    for (final rename in dialect.moves.values) {
      final written = rename.replaceAll(RegExp('%s', caseSensitive: false), '');
      if (sameIn(written, dialect)) {
        found.add(GlossaryNameSource.dialectMove);
      }
    }
  }
  if (shorthandTokens.any(
    (token) => same(token) || dialects.any((d) => sameIn(token, d)),
  )) {
    found.add(GlossaryNameSource.shorthand);
  }
  if (userEntryNames.any(same)) found.add(GlossaryNameSource.userEntry);
  return found;
}
