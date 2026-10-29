import 'package:drift/drift.dart' as drift;

/// Fails the first statement of one kind that mentions [table], then behaves
/// normally, so a screen's error path and its Retry can both be exercised
/// against a real database.
///
/// Nothing fails until [arm] is called, which lets a test seed its rows first.
/// [fired] says whether the failure really happened; assert it, because an
/// injection that silently misses makes the surrounding test pass for the
/// wrong reason.
class FailOnceInterceptor extends drift.QueryInterceptor {
  FailOnceInterceptor(this.table, {this.failUpdates = false});

  final String table;

  /// Fails the first UPDATE on [table] instead of the first SELECT.
  final bool failUpdates;

  bool _armed = false;
  bool _fired = false;

  bool get fired => _fired;

  void arm() => _armed = true;

  /// Whole-word, so `tags` does not also match `dance_tags`.
  bool _hit(String statement) =>
      _armed && !_fired && RegExp('\\b$table\\b').hasMatch(statement);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (!failUpdates && _hit(statement)) {
      _fired = true;
      throw Exception('injected $table read failure');
    }
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (failUpdates && _hit(statement)) {
      _fired = true;
      throw Exception('injected $table write failure');
    }
    return executor.runUpdate(statement, args);
  }

}
