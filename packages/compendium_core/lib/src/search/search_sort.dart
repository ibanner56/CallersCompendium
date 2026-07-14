/// Sort orderings for a dance search (`docs/design/search.md` "Combinators &
/// sort"). A fixed allow-list mapped to columns — never user text.
///
/// [title], [recentlyAdded] and [recentlyEdited] compile to a SQL `ORDER BY`;
/// [author] and [lastCalled] reuse the Phase 3.1 orderings and are applied in
/// Dart after the id set is fetched (author name / last-called timestamp are
/// not on the `dances` row). [relevance] is FTS5 `bm25` and is only honoured
/// when the whole filter tree is a bare [FullTextFilter]; for any other tree
/// it falls back to [title] (`bm25` is undefined outside a `MATCH` query).
enum SearchSort {
  /// FTS relevance (`bm25`); only for a bare full-text search.
  relevance,

  /// Title, case-insensitive ascending (the default).
  title,

  /// First author name, case-insensitive ascending (Dart post-sort).
  author,

  /// Most recently added first (`created_at DESC`). This is the Collection's
  /// "recently added" order (`docs/design/ux.md` §1) and the SQL analogue of
  /// the Phase 3.1 `DanceSort.recentlyAdded`.
  recentlyAdded,

  /// Most recently edited first (`updated_at DESC`).
  recentlyEdited,

  /// By author composition date ([Dance.composedOn]), earliest first, dances
  /// with no composed date last. Partial dates are stored as the canonical
  /// [PartialDate] string, whose lexicographic order is chronological, so this
  /// is a plain SQL `ORDER BY` (a year-only value sorts before a
  /// month-qualified value in the same year).
  composedOn,

  /// By curator [Dance.rating], highest first, unrated (NULL) dances last.
  /// Compiles to `rating IS NULL, rating DESC, title COLLATE NOCASE`: the
  /// explicit `rating IS NULL` leading key forces unrated dances after all
  /// rated ones (SQLite's bare `rating DESC` would otherwise sort NULLs first),
  /// with a case-insensitive title tiebreak.
  rating,

  /// Most recently called first, never-called last (Dart post-sort).
  lastCalled,
}
