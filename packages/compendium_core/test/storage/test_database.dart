import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// An in-memory [CompendiumDatabase] for tests. Each call returns a fresh,
/// isolated database (no shared state between tests).
CompendiumDatabase openTestDatabase() =>
    CompendiumDatabase(NativeDatabase.memory());

/// Counts the SELECT statements executed against the database, keyed by a
/// caller-supplied match on the statement text. Only SELECTs are observed —
/// [runSelect] is the sole intercepted method — which is all the batched-loader
/// query-count invariants need (e.g. asserting a loader issues O(1), not O(n),
/// child SELECTs). Override [matches] to narrow which SELECTs are counted.
class QueryCounter extends QueryInterceptor {
  int _count = 0;

  /// The number of matching SELECT statements seen so far.
  int get count => _count;

  /// Resets the counter to zero.
  void reset() => _count = 0;

  /// Override to count only SELECT statements of interest. Defaults to counting
  /// every SELECT.
  bool matches(String statement) => true;

  void _maybeCount(String statement) {
    if (matches(statement)) _count++;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _maybeCount(statement);
    return super.runSelect(executor, statement, args);
  }
}

/// A [QueryCounter] that only counts SELECTs touching `program_slots`.
class SlotSelectCounter extends QueryCounter {
  @override
  bool matches(String statement) {
    final s = statement.toLowerCase();
    return s.startsWith('select') && s.contains('program_slots');
  }
}

/// A [QueryCounter] that only counts SELECTs touching `venues` — used to assert
/// bulk restore/import validate `venueId`s against a preloaded set (O(1) venue
/// queries) rather than an N+1 of per-program existence reads.
class VenueSelectCounter extends QueryCounter {
  @override
  bool matches(String statement) {
    final s = statement.toLowerCase();
    return s.startsWith('select') && s.contains('venues');
  }
}

/// A [QueryCounter] that counts SELECTs against any of [DanceRepository]'s six
/// child-relation tables — the per-dance fan-out that
/// [DanceRepository.listAll] batches. A batched load issues a fixed number of
/// these (one per table per id-chunk) no matter how many dances are loaded, so
/// an N+1 regression (one set of child selects per dance) would make this count
/// scale with the collection size.
class DanceChildSelectCounter extends QueryCounter {
  static const _childTables = [
    'dance_authors',
    'dance_tags',
    'dance_links',
    'dance_sources',
    'custom_field_values',
    'provenance',
  ];

  @override
  bool matches(String statement) {
    final s = statement.toLowerCase();
    if (!s.startsWith('select')) return false;
    return _childTables.any(s.contains);
  }
}

/// Counts per-dance `DELETE FROM dance_fts WHERE dance_id = ?` statements — the
/// FTS delete-by-scan that made [DanceRepository.rebuildAllDerived] O(N²)
/// (`dance_fts.dance_id` is `UNINDEXED`, so each delete scans the whole index).
///
/// A full rebuild clears the index once (`DELETE FROM dance_fts`) and re-inserts
/// every dance instead, so it must issue ZERO per-dance FTS deletes (#440); a
/// regression that reintroduces them makes this count scale with the collection.
/// Per-dance deletes reach the executor as custom statements ([runCustom]); the
/// [runDelete] override is defensive in case drift routes them differently.
class FtsDeleteByDanceCounter extends QueryInterceptor {
  int count = 0;

  bool _matches(String statement) => statement
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .contains('delete from dance_fts where dance_id');

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_matches(statement)) count++;
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_matches(statement)) count++;
    return super.runDelete(executor, statement, args);
  }
}

/// A [QueryCounter] that only counts full-table SELECTs against
/// `choreographers` (i.e. [ChoreographerRepository.listAll], which has no
/// `WHERE` clause) — used to assert the import pipeline's `plan → commit`
/// cycle loads the choreographer collection once (via a shared [DedupeIndex]
/// snapshot) instead of a redundant second `listAll()` in `commit` (#625).
/// Deliberately excludes the per-author `WHERE id = ?` lookups
/// `DanceRepository` also issues against this table while writing a dance's
/// searchable author text, which are unrelated to the load being counted.
class ChoreographerSelectCounter extends QueryCounter {
  @override
  bool matches(String statement) {
    final s = statement.toLowerCase();
    if (!s.startsWith('select') || !s.contains('choreographers')) return false;
    // "No WHERE at all" identified a full-collection load until schema v25
    // (#898), when `listAll` gained a `deleted_at IS NULL` live filter — so
    // that rule started reading every full load as a targeted one and the
    // counter silently fell to zero. Strip exactly the live filter (and only
    // it) before applying the original rule, so a genuinely targeted select
    // still has a WHERE left over and is still not counted.
    final withoutLiveFilter = s.replaceFirst(
      RegExp(r'where\s+"deleted_at"\s+is\s+null'),
      '',
    );
    return !withoutLiveFilter.contains('where');
  }
}

/// An in-memory [CompendiumDatabase] whose executor is wrapped with [counter],
/// letting a test observe how many (matching) statements a repository issues.
CompendiumDatabase openCountingTestDatabase(QueryInterceptor counter) =>
    CompendiumDatabase(NativeDatabase.memory().interceptWith(counter));

/// Counts `BEGIN TRANSACTION` calls issued against the database — used to
/// assert a multi-read/multi-write operation (e.g. archive export/restore)
/// opens exactly one transaction rather than leaving its reads/writes as
/// independently-snapshotted statements (#615).
class TransactionCounter extends QueryInterceptor {
  int _count = 0;

  /// The number of transactions begun so far.
  int get count => _count;

  /// Resets the counter to zero.
  void reset() => _count = 0;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    _count++;
    return super.beginTransaction(parent);
  }
}

/// Captures the bound arguments of a repository's post-fetch **sort aggregate**
/// SELECT so a test can assert the aggregate is scoped to the result-set ids
/// (chunked `dance_id IN (…)`) rather than scanning the whole collection (#465).
///
/// [matches] selects which SELECT to watch; every bound argument of a matching
/// statement is appended to [boundArgs] (across id-chunks) and each matching
/// statement bumps [selectCount]. For both the author and last-called sort
/// aggregates the only bound placeholders are the `dance_id` ids, so
/// `boundArgs` is exactly the set of ids the aggregate touched.
abstract class SortAggregateArgCapture extends QueryInterceptor {
  final List<Object?> boundArgs = [];
  int selectCount = 0;

  /// Override to select the sort aggregate SELECT of interest.
  bool matches(String statement);

  /// Clears captured args/count so a test can ignore statements issued during
  /// setup and observe only the query under test.
  void reset() {
    boundArgs.clear();
    selectCount = 0;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (matches(statement)) {
      selectCount++;
      boundArgs.addAll(args);
    }
    return super.runSelect(executor, statement, args);
  }
}

/// Watches the author sort aggregate (`dance_authors … WHERE position = 0`).
class AuthorSortArgCapture extends SortAggregateArgCapture {
  @override
  bool matches(String statement) {
    final s = statement.toLowerCase();
    return s.startsWith('select') &&
        s.contains('dance_authors') &&
        s.contains('position = 0');
  }
}

/// Watches the last-called sort aggregate
/// (`program_slots … GROUP BY program_slots.dance_id`).
class LastCalledSortArgCapture extends SortAggregateArgCapture {
  @override
  bool matches(String statement) {
    final s = statement.toLowerCase();
    return s.startsWith('select') &&
        s.contains('program_slots') &&
        s.contains('group by program_slots.dance_id');
  }
}
