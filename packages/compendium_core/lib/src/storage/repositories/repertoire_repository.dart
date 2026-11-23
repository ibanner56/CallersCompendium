import 'package:drift/drift.dart';

import '../../analysis/repertoire_stats.dart';
import '../../model/enums.dart';
import '../../model/figure.dart' show customMove;
import '../../model/formation.dart' show FormationShape;
import '../../search/filter.dart' show VenueKey;
import '../../search/title_sort_key.dart' show foldForTitleMatch;
import '../calling_history_scope.dart';
import '../database.dart';

/// Read-only aggregates over the whole collection and its calling history,
/// for the Repertoire page (#2357). Derived on every read; nothing is stored.
///
/// Every number is a SQL `GROUP BY` over the same counted-slot gates the rest
/// of the app uses ([callingHistoryCountedSlotClause], and
/// [callingHistoryRecencyDateSql] for the window), so a dance's count here is
/// the "called ×N" on its Collection row, and a window selects the calls a
/// `CalledFilter.since` of the same date selects. [load] issues a fixed number
/// of statements however many programs there are.
class RepertoireRepository {
  RepertoireRepository(this._db);

  final CompendiumDatabase _db;

  /// How many dances [load] puts in each ranked list by default.
  static const int defaultTopCount = 10;

  /// How many titles [load] lists under Never called by default.
  static const int defaultSampleCount = 5;

  /// Everything the Repertoire page shows for [scope]. See [RepertoireStats]
  /// for which figures honor the window.
  ///
  /// Throws [ArgumentError] when the scope's `since` is not a UTC calendar
  /// date, as a `CalledFilter.since` does.
  Future<RepertoireStats> load(
    RepertoireScope scope, {
    int topCount = defaultTopCount,
    int sampleCount = defaultSampleCount,
  }) async {
    final since = scope.since;
    if (since != null &&
        (!since.isUtc ||
            since != DateTime.utc(since.year, since.month, since.day))) {
      throw ArgumentError.value(
        since,
        'RepertoireScope.since',
        'must be a UTC calendar date, DateTime.utc(y, m, d)',
      );
    }
    final caller = normalizeCallingHistoryCaller(scope.callerFilter);
    final form = scope.form;

    // Read in one transaction so every section sees the same revision.
    return _db.transaction(() async {
      final formRows = await _db
          .customSelect(
            'SELECT form, COUNT(*) AS n FROM dances '
            'WHERE deleted_at IS NULL GROUP BY form',
            readsFrom: {_db.dances},
          )
          .get();
      final countsByForm = <DanceForm, int>{};
      for (final row in formRows) {
        final f = _formOf(row.read<String>('form'));
        if (f != null) countsByForm[f] = row.read<int>('n');
      }
      final danceCountsByForm = form == null
          ? countsByForm
          : {form: ?countsByForm[form]};
      final danceCount = danceCountsByForm.values.fold(0, (a, b) => a + b);

      final counted = _countedCte(scope, caller);

      final danceRows = await _db
          .customSelect(
            '${counted.sql}'
            'SELECT c.dance_id AS dance_id, d.title AS title, '
            'COUNT(*) AS n FROM counted c '
            'JOIN dances d ON d.id = c.dance_id AND d.deleted_at IS NULL '
            'GROUP BY c.dance_id',
            variables: counted.variables,
            readsFrom: _readSet,
          )
          .get();
      final perDance = [
        for (final row in danceRows)
          RepertoireDanceCount(
            danceId: row.read<String>('dance_id'),
            title: row.read<String>('title'),
            count: row.read<int>('n'),
          ),
      ];
      final most = [...perDance]
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : _byTitle(a, b);
        });
      final mostCalled = most.take(topCount).toList(growable: false);
      final shown = {for (final d in mostCalled) d.danceId};
      final least =
          [
            for (final d in perDance)
              if (!shown.contains(d.danceId)) d,
          ]..sort((a, b) {
            final byCount = a.count.compareTo(b.count);
            return byCount != 0 ? byCount : _byTitle(a, b);
          });

      final never = await _notCalled(
        scope,
        caller,
        withWindow: false,
        limit: sampleCount,
      );
      final notInWindow = since == null
          ? null
          : await _notCalled(
              scope,
              caller,
              withWindow: true,
              limit: sampleCount,
            );

      final figureDanceRows = await _db
          .customSelect(
            'SELECT d.form AS form, f.move AS move, '
            'COUNT(DISTINCT d.id) AS n FROM dance_figures f '
            'JOIN dances d ON d.id = f.dance_id AND d.deleted_at IS NULL '
            'WHERE f.move <> ? '
            '${form == null ? '' : 'AND d.form = ? '}'
            'GROUP BY d.form, f.move',
            variables: [
              const Variable<String>(customMove),
              if (form != null) Variable<String>(form.name),
            ],
            readsFrom: {_db.dances, _db.danceFigures},
          )
          .get();
      final figureCallRows = await _db
          .customSelect(
            '${counted.sql}'
            'SELECT d.form AS form, m.move AS move, COUNT(*) AS n '
            'FROM counted c JOIN dances d ON d.id = c.dance_id AND d.deleted_at IS NULL '
            'JOIN (SELECT DISTINCT dance_id, move FROM dance_figures '
            'WHERE move <> ?) m ON m.dance_id = c.dance_id '
            'GROUP BY d.form, m.move',
            variables: [
              ...counted.variables,
              const Variable<String>(customMove),
            ],
            readsFrom: _readSet,
          )
          .get();
      final figureCalls = <(DanceForm, String), int>{};
      for (final row in figureCallRows) {
        final f = _formOf(row.read<String>('form'));
        if (f == null) continue;
        figureCalls[(f, row.read<String>('move'))] = row.read<int>('n');
      }
      final figures = <RepertoireFigureCount>[
        for (final row in figureDanceRows)
          if (_formOf(row.read<String>('form')) case final f?)
            RepertoireFigureCount(
              form: f,
              move: row.read<String>('move'),
              danceCount: row.read<int>('n'),
              callCount: figureCalls[(f, row.read<String>('move'))] ?? 0,
            ),
      ]..sort(_byFigure);

      final authorRows = await _db
          .customSelect(
            '${counted.sql}'
            'SELECT ch.id AS id, ch.name AS name, COUNT(*) AS n '
            'FROM counted c '
            'JOIN dance_authors da ON da.dance_id = c.dance_id '
            'JOIN choreographers ch ON ch.id = da.choreographer_id '
            'WHERE ch.deleted_at IS NULL '
            'GROUP BY ch.id',
            variables: counted.variables,
            readsFrom: {..._readSet, _db.danceAuthors, _db.choreographers},
          )
          .get();
      final authors = [
        for (final row in authorRows)
          RepertoireAuthorCount(
            choreographerId: row.read<String>('id'),
            name: row.read<String>('name'),
            callCount: row.read<int>('n'),
          ),
      ]..sort(_byAuthor);

      final formationRows = await _db
          .customSelect(
            '${counted.sql}'
            'SELECT d.formation_shape AS shape, COUNT(*) AS n '
            'FROM counted c JOIN dances d ON d.id = c.dance_id AND d.deleted_at IS NULL '
            'GROUP BY d.formation_shape',
            variables: counted.variables,
            readsFrom: _readSet,
          )
          .get();
      final formations =
          <RepertoireFormationCount>[
            for (final row in formationRows)
              if (_shapeOf(row.read<String>('shape')) case final shape?)
                RepertoireFormationCount(
                  shape: shape,
                  callCount: row.read<int>('n'),
                ),
          ]..sort((a, b) {
            final byCount = b.callCount.compareTo(a.callCount);
            return byCount != 0
                ? byCount
                : a.shape.index.compareTo(b.shape.index);
          });

      final venueRows = await _db
          .customSelect(
            '${counted.sql}'
            // `venue` is a bare column beside the single MAX: SQLite takes it
            // from the row holding the maximum, the group's latest call.
            'SELECT c.venue_id AS venue_id, c.venue AS venue, '
            'CASE WHEN c.venue_id IS NULL '
            'THEN $callingHistoryVenueKeySqlFunction(c.venue) END AS typed, '
            'c.dance_id AS dance_id, d.title AS title, COUNT(*) AS n, '
            'MAX(c.called_at) AS called_at '
            'FROM counted c JOIN dances d ON d.id = c.dance_id AND d.deleted_at IS NULL '
            'WHERE c.venue_id IS NOT NULL '
            'OR $callingHistoryVenueKeySqlFunction(c.venue) IS NOT NULL '
            'GROUP BY c.venue_id, typed, c.dance_id',
            variables: counted.variables,
            readsFrom: _readSet,
          )
          .get();
      final venues = _venuesFromRows(venueRows);

      final totalCalls = perDance.fold(0, (a, d) => a + d.count);
      return RepertoireStats(
        formsPresent: countsByForm.keys.toSet(),
        danceCount: danceCount,
        danceCountsByForm: danceCountsByForm,
        totalCalls: totalCalls,
        calledDanceCount: perDance.length,
        callCounts: {for (final d in perDance) d.danceId: d.count},
        mostCalled: mostCalled,
        leastCalled: least.take(topCount).toList(growable: false),
        neverCalledCount: never.count,
        neverCalledSample: never.sample,
        notCalledInWindowCount: notInWindow?.count,
        notCalledInWindowSample: notInWindow?.sample ?? const [],
        figures: figures,
        authorCount: authors.length,
        authors: authors,
        formations: formations,
        venues: venues,
      );
    });
  }

  Set<ResultSetImplementation<dynamic, dynamic>> get _readSet => {
    _db.programs,
    _db.programSlots,
    _db.dances,
    _db.danceFigures,
  };

  /// The `counted` CTE: one row per counted slot in the window, of a live
  /// dance of the scope's type. Its variables bind in the order its SQL names
  /// them: the caller, the window's first day, the type.
  ({String sql, List<Variable<Object>> variables}) _countedCte(
    RepertoireScope scope,
    String? caller,
  ) {
    final since = scope.since;
    final form = scope.form;
    final orderDate = callingHistoryDateSql(slotTable: 'ps', programTable: 'p');
    final sql =
        'WITH counted AS (SELECT ps.dance_id AS dance_id, '
        'p.venue_id AS venue_id, p.venue AS venue, '
        '$orderDate AS called_at '
        'FROM program_slots ps JOIN programs p ON p.id = ps.program_id '
        'JOIN dances d ON d.id = ps.dance_id AND d.deleted_at IS NULL '
        'WHERE p.deleted_at IS NULL '
        '${callingHistoryCountedSlotClause(slotTable: 'ps', programTable: 'p', performedOnly: scope.performedOnly, requireEventDate: scope.requireEventDate, caller: caller)}'
        '${_windowClause(scope)}'
        '${form == null ? '' : 'AND d.form = ? '}'
        ') ';
    return (
      sql: sql,
      variables: [
        if (caller != null) Variable<String>(caller),
        if (since != null) Variable<DateTime>(since),
        if (form != null) Variable<String>(form.name),
      ],
    );
  }

  /// The window rule over `ps`/`p`, or nothing for all time. The same
  /// expression a `CalledFilter.since` compiles to.
  String _windowClause(RepertoireScope scope) => scope.since == null
      ? ''
      : 'AND ${callingHistoryRecencyDateSql(slotTable: 'ps', programTable: 'p', requireEventDate: scope.tracking.recencyRequireEventDate, requirePerformed: scope.tracking.recencyRequirePerformed)} >= ? ';

  /// Live dances of the scope's type with no counted call (in the window when
  /// [withWindow]): how many, and the first [limit] by title. The predicate is
  /// the Not called filter's.
  Future<({int count, List<RepertoireDanceCount> sample})> _notCalled(
    RepertoireScope scope,
    String? caller, {
    required bool withWindow,
    required int limit,
  }) async {
    final form = scope.form;
    final since = withWindow ? scope.since : null;
    final rows = await _db
        .customSelect(
          'SELECT d.id AS id, d.title AS title, COUNT(*) OVER () AS total '
          'FROM dances d WHERE d.deleted_at IS NULL '
          '${form == null ? '' : 'AND d.form = ? '}'
          'AND NOT EXISTS (SELECT 1 FROM program_slots ps '
          'JOIN programs p ON p.id = ps.program_id '
          'WHERE ps.dance_id = d.id AND p.deleted_at IS NULL '
          '${callingHistoryCountedSlotClause(slotTable: 'ps', programTable: 'p', performedOnly: scope.performedOnly, requireEventDate: scope.requireEventDate, caller: caller)}'
          '${withWindow ? _windowClause(scope) : ''}'
          ') ORDER BY d.title COLLATE NOCASE, d.id LIMIT ?',
          variables: [
            if (form != null) Variable<String>(form.name),
            if (caller != null) Variable<String>(caller),
            if (since != null) Variable<DateTime>(since),
            Variable<int>(limit),
          ],
          readsFrom: _readSet,
        )
        .get();
    return (
      count: rows.isEmpty ? 0 : rows.first.read<int>('total'),
      sample: [
        for (final row in rows)
          RepertoireDanceCount(
            danceId: row.read<String>('id'),
            title: row.read<String>('title'),
            count: 0,
          ),
      ],
    );
  }

  List<RepertoireVenueRepeats> _venuesFromRows(List<QueryRow> rows) {
    final byKey =
        <
          String,
          ({
            VenueKey key,
            DateTime latest,
            String? text,
            List<RepertoireDanceCount> repeats,
          })
        >{};
    for (final row in rows) {
      final venue = row.read<String?>('venue');
      final key = VenueKey.forProgram(
        venueId: row.read<String?>('venue_id'),
        venue: venue,
      );
      if (key == null) continue;
      final calledAt = row.read<DateTime>('called_at');
      final count = row.read<int>('n');
      final text = _displayVenueText(venue);
      final current = byKey[key.storageKey];
      final newer = current == null || calledAt.isAfter(current.latest);
      final repeats = current?.repeats ?? <RepertoireDanceCount>[];
      if (count > 1) {
        repeats.add(
          RepertoireDanceCount(
            danceId: row.read<String>('dance_id'),
            title: row.read<String>('title'),
            count: count,
          ),
        );
      }
      byKey[key.storageKey] = (
        key: key,
        latest: newer ? calledAt : current.latest,
        text: newer ? (text ?? current?.text) : (current.text ?? text),
        repeats: repeats,
      );
    }
    final venues = byKey.values.toList()
      ..sort((a, b) {
        final byDate = b.latest.compareTo(a.latest);
        return byDate != 0
            ? byDate
            : a.key.storageKey.compareTo(b.key.storageKey);
      });
    return [
      for (final v in venues)
        RepertoireVenueRepeats(
          key: v.key,
          latestVenueText: v.text,
          repeats: v.repeats
            ..sort((a, b) {
              final byCount = b.count.compareTo(a.count);
              return byCount != 0 ? byCount : _byTitle(a, b);
            }),
        ),
    ];
  }

  static String? _displayVenueText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  static int _byTitle(RepertoireDanceCount a, RepertoireDanceCount b) {
    // The Collection's title order, accents and case folded.
    final byTitle = foldForTitleMatch(
      a.title,
    ).compareTo(foldForTitleMatch(b.title));
    return byTitle != 0 ? byTitle : a.danceId.compareTo(b.danceId);
  }

  static int _byFigure(RepertoireFigureCount a, RepertoireFigureCount b) {
    final byForm = a.form.index.compareTo(b.form.index);
    if (byForm != 0) return byForm;
    final byCount = b.danceCount.compareTo(a.danceCount);
    return byCount != 0 ? byCount : a.move.compareTo(b.move);
  }

  static int _byAuthor(RepertoireAuthorCount a, RepertoireAuthorCount b) {
    final byCount = b.callCount.compareTo(a.callCount);
    if (byCount != 0) return byCount;
    final byName = foldForTitleMatch(
      a.name,
    ).compareTo(foldForTitleMatch(b.name));
    return byName != 0
        ? byName
        : a.choreographerId.compareTo(b.choreographerId);
  }

  static DanceForm? _formOf(String name) =>
      DanceForm.values.where((f) => f.name == name).firstOrNull;

  static FormationShape? _shapeOf(String name) =>
      FormationShape.values.where((s) => s.name == name).firstOrNull;
}
