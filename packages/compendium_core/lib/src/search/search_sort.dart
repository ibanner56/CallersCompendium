/// Sort orderings for a dance search (`docs/design/search.md` "Combinators &
/// sort"). A fixed allow-list mapped to columns — never user text.
///
/// [title] and [recentlyEdited] compile to a SQL `ORDER BY`; [author] and
/// [lastCalled] reuse the Phase 3.1 orderings and are applied in Dart after
/// the id set is fetched (author name / last-called timestamp are not on the
/// `dances` row). [relevance] is FTS5 `bm25` and is only honoured when the
/// whole filter tree is a bare [FullTextFilter]; for any other tree it falls
/// back to [title] (`bm25` is undefined outside a `MATCH` query).
enum SearchSort {
  /// FTS relevance (`bm25`); only for a bare full-text search.
  relevance,

  /// Title, case-insensitive ascending (the default).
  title,

  /// First author name, case-insensitive ascending (Dart post-sort).
  author,

  /// Most recently edited first (`updated_at DESC`).
  recentlyEdited,

  /// Most recently called first, never-called last (Dart post-sort).
  lastCalled,
}
