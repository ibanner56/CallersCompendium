import '../dialect/canonicalize.dart';
import '../dialect/dialect.dart';
import '../dialect/renderer.dart';
import 'saved_search.dart';
import 'search_enrichment.dart';

/// The text codec for a saved search typed under [dialect]: the text is stored
/// canonicalized the way a search compiles it (same [enrichment], the
/// always-on role synonyms the compiler uses, `filter_compiler.dart`) and
/// shown through [renderer] in the dialect active when it is loaded.
///
/// So a saved "larks chain" returns the same dances after a switch to a
/// dialect that calls the roles something else (the precedent is #1608, where
/// custom figure text is stored as `role1s`/`role2s`). The stored text is
/// whatever [canonicalizeText] makes of the typed text; loading shows
/// `renderFreeText(stored)`, and the round trip of stored canonical text is
/// the one `role_move_words_test.dart` already pins.
SavedSearchTextCodec savedSearchTextCodec({
  required Dialect saveDialect,
  required Dialect showDialect,
  required SearchEnrichment enrichment,
  required FigureRenderer renderer,
}) => SavedSearchTextCodec(
  canonicalize: (typed) => canonicalizeText(
    typed,
    saveDialect,
    extraRoleSynonyms: enrichment.roleSynonyms,
  ),
  display: (stored) => renderer.renderFreeText(stored, showDialect),
);
