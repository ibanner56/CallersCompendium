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

/// An in-memory [CompendiumDatabase] whose executor is wrapped with [counter],
/// letting a test observe how many (matching) statements a repository issues.
CompendiumDatabase openCountingTestDatabase(QueryInterceptor counter) =>
    CompendiumDatabase(NativeDatabase.memory().interceptWith(counter));
