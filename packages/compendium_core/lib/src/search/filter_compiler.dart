import '../dialect/canonicalize.dart';
import '../dialect/dialect.dart';
import '../model/enums.dart';
import 'filter.dart';
import 'search_sort.dart';

/// A compiled search: one parameterized SQL statement plus its ordered bind
/// list. Binds are emitted in pre-order, left-to-right, so bind index always
/// matches the `?` order in [sql].
class CompiledFilter {
  const CompiledFilter(this.sql, this.binds);

  final String sql;
  final List<Object?> binds;
}

/// Compiles a [DanceFilter] tree into a single parameterized `SELECT id FROM
/// dances …` (`docs/design/search.md` "SQL compilation").
///
/// Injection-safe by construction: every user value is a bind variable; only
/// an allow-list of column names, operators and JSON key paths is ever
/// interpolated (JSON keys are validated at [FigureLeaf] construction).
///
/// Dialect canonicalization happens at this boundary, once, before any bind is
/// produced: full-text queries and role-valued figure params are run through
/// [canonicalizeText], and move names are mapped back through the active
/// dialect's move substitutions — mirroring how data was canonicalized on the
/// way in, so a dialect user's query matches the canonical tokens stored in
/// the derived indexes.
class FilterCompiler {
  FilterCompiler([Dialect? dialect]) : dialect = dialect ?? Dialect.canonical {
    // Reverse the dialect's move substitutions (display → canonical id),
    // skipping templated (`%S`) substitutions which aren't reversible by a
    // plain word match. Conservative: unknown/unmapped moves pass through.
    final reverse = <String, String>{};
    for (final entry in this.dialect.moves.entries) {
      final display = entry.value;
      if (display.contains('%S')) continue;
      reverse[display.toLowerCase()] = entry.key;
    }
    _moveReverse = reverse;
  }

  final Dialect dialect;
  late final Map<String, String> _moveReverse;

  /// Compiles [filter] with the given [sort] (default [SearchSort.title]).
  CompiledFilter compile(
    DanceFilter filter, {
    SearchSort sort = SearchSort.title,
  }) {
    // Relevance is only meaningful for a bare full-text search; it needs a
    // dedicated shape that can `ORDER BY bm25(dance_fts)`.
    if (sort == SearchSort.relevance && filter is FullTextFilter) {
      return _compileRelevance(filter);
    }

    final binds = <Object?>[];
    final pred = _dance(filter, binds);
    final sql =
        'SELECT id FROM dances '
        'WHERE deleted_at IS NULL AND ($pred) '
        'ORDER BY ${_orderBy(sort)}';
    return CompiledFilter(sql, binds);
  }

  CompiledFilter _compileRelevance(FullTextFilter filter) {
    final query = canonicalizeText(filter.query, dialect);
    const sql =
        'SELECT dance_fts.dance_id FROM dance_fts '
        'JOIN dances ON dances.id = dance_fts.dance_id '
        'WHERE dance_fts MATCH ? AND dances.deleted_at IS NULL '
        'ORDER BY bm25(dance_fts)';
    return CompiledFilter(sql, [query]);
  }

  /// SQL `ORDER BY` fragment for a [SearchSort]. [SearchSort.author] and
  /// [SearchSort.lastCalled] are applied in Dart after the id fetch, so they
  /// use the stable [title] base ordering here; [relevance] on a non-bare
  /// tree likewise degrades to [title].
  static String _orderBy(SearchSort sort) => switch (sort) {
    SearchSort.recentlyAdded => 'created_at DESC',
    SearchSort.recentlyEdited => 'updated_at DESC',
    // Canonical PartialDate strings sort lexicographically == chronologically.
    // NULLs (no composed date) sort last; ties break by title.
    SearchSort.composedOn =>
      'composed_on IS NULL, composed_on, title COLLATE NOCASE',
    // Highest rating first; unrated (NULL) last (the explicit `rating IS NULL`
    // key overrides SQLite's default NULLs-first on `DESC`); title tiebreak.
    SearchSort.rating => 'rating IS NULL, rating DESC, title COLLATE NOCASE',
    SearchSort.title ||
    SearchSort.author ||
    SearchSort.lastCalled ||
    SearchSort.relevance => 'title COLLATE NOCASE',
  };

  // ---- DanceFilter -> predicate over the current `dances` row ----

  String _dance(DanceFilter filter, List<Object?> binds) {
    switch (filter) {
      case AndFilter(:final children):
        if (children.isEmpty) return '1';
        return '(${children.map((c) => _dance(c, binds)).join(' AND ')})';
      case OrFilter(:final children):
        if (children.isEmpty) return '0';
        return '(${children.map((c) => _dance(c, binds)).join(' OR ')})';
      case NotFilter(:final child):
        return 'NOT (${_dance(child, binds)})';
      case FullTextFilter(:final query):
        binds.add(canonicalizeText(query, dialect));
        return 'id IN (SELECT dance_id FROM dance_fts WHERE dance_fts MATCH ?)';
      case AuthorFilter(:final choreographerId):
        binds.add(choreographerId);
        return 'id IN (SELECT dance_id FROM dance_authors '
            'WHERE choreographer_id = ?)';
      case TagFilter(:final tagId):
        binds.add(tagId);
        return 'id IN (SELECT dance_id FROM dance_tags WHERE tag_id = ?)';
      case FormFilter(:final form):
        binds.add(form.name);
        return 'form = ?';
      case FormationFilter(:final shape):
        binds.add(shape.name);
        return 'formation_shape = ?';
      case ProgressionFilter(:final progression):
        binds.add(progression.name);
        return 'progression = ?';
      case StatusFilter(:final status):
        binds.add(status.name);
        return 'status = ?';
      case LevelFilter(:final level, :final op):
        return _level(level, op, binds);
      case MixedLevelFilter(:final mixed):
        binds.add(mixed ? 1 : 0);
        return 'mixed_level = ?';
      case RatingFilter(:final minRating):
        // Unrated dances (NULL) are not a point on the scale, so they never
        // match an ordered comparison (mirrors the LevelFilter NULL guard).
        binds.add(minRating);
        return 'rating IS NOT NULL AND rating >= ?';
      case CustomFieldFilter():
        return _customField(filter, binds);
      case FigureFilter(:final query):
        return _figureIn(query, binds);
      case ThenFilter(:final before, :final after):
        return _then(before, after, binds);
    }
  }

  String _customField(CustomFieldFilter f, List<Object?> binds) {
    binds.add(f.fieldId);
    final legal = customFieldOpsByType[f.fieldType] ?? const {};
    if (!legal.contains(f.op)) {
      // Defensive: construction already rejects this, but never trust the
      // tree at compile time.
      throw ArgumentError(
        'operator ${f.op.name} is not valid for a ${f.fieldType.name} field',
      );
    }
    final opPred = _customFieldOp(f, binds);
    return 'EXISTS (SELECT 1 FROM custom_field_values v '
        'WHERE v.dance_id = dances.id AND v.field_id = ? AND $opPred)';
  }

  String _customFieldOp(CustomFieldFilter f, List<Object?> binds) {
    switch (f.op) {
      case CustomFieldOp.contains:
        binds.add(f.value);
        return "v.value_text LIKE '%' || ? || '%'";
      case CustomFieldOp.equals:
        binds.add(f.value);
        return 'v.value_text = ?';
      case CustomFieldOp.eq:
        binds.add(f.value);
        return 'v.value_num = ?';
      case CustomFieldOp.lt:
        binds.add(f.value);
        return 'v.value_num < ?';
      case CustomFieldOp.gt:
        binds.add(f.value);
        return 'v.value_num > ?';
      case CustomFieldOp.between:
        final range = f.value as List;
        binds.add(range[0]);
        binds.add(range[1]);
        return 'v.value_num BETWEEN ? AND ?';
      case CustomFieldOp.is_:
        if (f.fieldType == CustomFieldType.boolean) {
          binds.add((f.value as bool) ? 1 : 0);
          return 'v.value_num = ?';
        }
        binds.add(f.value);
        return 'v.value_text = ?';
      case CustomFieldOp.in_:
        final values = f.value as List;
        binds.addAll(values);
        final placeholders = List.filled(values.length, '?').join(', ');
        return 'v.value_text IN ($placeholders)';
    }
  }

  /// Compiles a [LevelFilter] against the ordered [DanceLevel] scale.
  ///
  /// [LevelOp.eq] is a plain name match (`level = ?`). The ordered ops map the
  /// stored enum-name text to its ordinal via a `CASE` generated from
  /// [DanceLevel.values] — the enum names are compile-time constants (never
  /// user input), so interpolating them is injection-safe — and compare that
  /// ordinal to the target level's index. A `level IS NOT NULL` guard keeps
  /// unspecified dances out of ordered comparisons (an unspecified difficulty
  /// is not a point on the scale).
  String _level(DanceLevel level, LevelOp op, List<Object?> binds) {
    switch (op) {
      case LevelOp.eq:
        binds.add(level.name);
        return 'level = ?';
      case LevelOp.lte:
      case LevelOp.gte:
        final cmp = op == LevelOp.lte ? '<=' : '>=';
        final cases = [
          for (final v in DanceLevel.values) "WHEN '${v.name}' THEN ${v.index}",
        ].join(' ');
        binds.add(level.index);
        return 'level IS NOT NULL AND (CASE level $cases END) $cmp ?';
    }
  }

  // ---- Structural predicates ----

  /// A dance-level structural predicate over `dance_figures`, compiled as an
  /// `id IN (SELECT dance_id FROM dance_figures …)` subquery.
  ///
  /// This is the index-driven equivalent of the design's correlated `EXISTS`
  /// (`docs/design/search.md`): driving *from* `dance_figures` lets SQLite use
  /// the `dance_figures_move_section` index on `move (, section)`, whereas a
  /// correlated `EXISTS` under a full `dances` scan cannot. A top-level
  /// [FigureNot] flips to `NOT IN` ("the dance has no figure matching");
  /// `dance_id` is `NOT NULL`, so `NOT IN` is safe from the NULL pitfall.
  String _figureIn(FigureQuery query, List<Object?> binds) {
    final negate = query is FigureNot;
    final body = negate ? query.child : query;
    final clause = _figureClause(body, 'f', binds);
    final subquery = 'SELECT f.dance_id FROM dance_figures f WHERE $clause';
    return negate ? 'id NOT IN ($subquery)' : 'id IN ($subquery)';
  }

  String _then(FigureQuery before, FigureQuery after, List<Object?> binds) {
    final a = _figureClause(before, 'a', binds);
    final b = _figureClause(after, 'b', binds);
    return 'id IN (SELECT a.dance_id FROM dance_figures a '
        'JOIN dance_figures b ON a.dance_id = b.dance_id '
        'AND a.idx < b.idx '
        'WHERE ($a) AND ($b))';
  }

  /// Compiles a [FigureQuery] to a boolean clause over the columns of the
  /// `dance_figures` row aliased [alias].
  String _figureClause(FigureQuery query, String alias, List<Object?> binds) {
    switch (query) {
      case FigureLeaf():
        return _figureLeaf(query, alias, binds);
      case FigureAnd(:final children):
        if (children.isEmpty) return '1';
        return '(${children.map((c) => _figureClause(c, alias, binds)).join(' AND ')})';
      case FigureOr(:final children):
        if (children.isEmpty) return '0';
        return '(${children.map((c) => _figureClause(c, alias, binds)).join(' OR ')})';
      case FigureNot(:final child):
        // COALESCE the child to 0 (false) before negating, so a NULL child
        // (e.g. `json_extract` of an absent key) negates to TRUE rather than
        // NULL under SQL three-valued logic — "this figure does not match".
        return 'NOT COALESCE((${_figureClause(child, alias, binds)}), 0)';
    }
  }

  static final RegExp _paramKeyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  String _figureLeaf(FigureLeaf leaf, String alias, List<Object?> binds) {
    final parts = <String>['$alias.move = ?'];
    binds.add(_canonicalizeMove(leaf.move));
    // Deterministic param order so emitted SQL and binds are stable.
    final keys = leaf.params.keys.toList()..sort();
    for (final key in keys) {
      // Defensive: keys are validated at [FigureLeaf] construction, but never
      // trust the tree — only well-formed identifiers may be interpolated.
      if (!_paramKeyPattern.hasMatch(key)) {
        throw ArgumentError.value(key, 'params key', 'illegal JSON path key');
      }
      parts.add("json_extract($alias.params_json, '\$.$key') = ?");
      binds.add(_paramBind(leaf.params[key]));
    }
    if (leaf.section != null) {
      parts.add('$alias.section = ?');
      binds.add(leaf.section);
    }
    return parts.length == 1 ? parts.first : '(${parts.join(' AND ')})';
  }

  /// Canonicalizes a move name via the active dialect's (reversed) move
  /// substitutions. Unknown/unmapped names pass through unchanged.
  String _canonicalizeMove(String move) =>
      _moveReverse[move.toLowerCase()] ?? move;

  /// Prepares a figure-param value for binding against `json_extract`'s
  /// natural typing. Role-valued strings are canonicalized; booleans compare
  /// against `json_extract`'s 1/0.
  Object? _paramBind(Object? value) {
    if (value is String) return canonicalizeText(value, dialect);
    if (value is bool) return value ? 1 : 0;
    return value;
  }
}
