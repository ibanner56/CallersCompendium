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

/// An in-memory [CompendiumDatabase] whose executor is wrapped with [counter],
/// letting a test observe how many (matching) statements a repository issues.
CompendiumDatabase openCountingTestDatabase(QueryInterceptor counter) =>
    CompendiumDatabase(NativeDatabase.memory().interceptWith(counter));
