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

  /// By curatorial [Dance.rating], highest first; unrated dances (`rating`
  /// NULL) sort **last**. Compiles to a plain SQL `ORDER BY` with an explicit
  /// `rating IS NULL` guard so unrated rows are forced to the end regardless of
  /// SQLite's default NULL placement; ties break by title.
  rating,

  /// Most recently called first, never-called last (Dart post-sort).
  lastCalled,
}

/// The direction a [SearchSort] is applied in. [ascending] and [descending]
/// name the *primary* comparison's direction (A→Z / low→high vs Z→A / high→low,
/// or best-match→worst vs worst→best for `relevance`).
///
/// Each [SearchSort] has a [SearchSortDirectionX.defaultDirection] equal to its
/// historical (pre-toggle) behavior, so a caller that leaves the direction
/// unset gets exactly the previous ordering. The two direction-independent
/// invariants — NULL/absent values sort **last**, and `title` is the stable
/// tiebreak — hold in both directions.
enum SortDirection { ascending, descending }

extension SearchSortDirectionX on SearchSort {
  /// The historical direction for this sort key, used as the default when a
  /// caller does not specify one (so behavior is unchanged until a user flips
  /// the direction toggle).
  SortDirection get defaultDirection => switch (this) {
    SearchSort.title ||
    SearchSort.author ||
    SearchSort.composedOn ||
    SearchSort.relevance => SortDirection.ascending,
    SearchSort.recentlyAdded ||
    SearchSort.recentlyEdited ||
    SearchSort.rating ||
    SearchSort.lastCalled => SortDirection.descending,
  };
}
