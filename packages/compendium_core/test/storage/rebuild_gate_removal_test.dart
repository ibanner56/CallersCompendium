import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// Guards for removing #1346's `_derivedRebuildIsBlocked` rebuild gate.
///
/// The gate deferred a derived rebuild whenever `normalisation_skips` held any
/// `dances` row, because a rebuild that met a row it could not read raised out
/// of `ensureMigrated()`. #1347 removed that hazard at its source — the rebuild
/// now loads such a row as `UnreadableFigures` — so there is nothing left to
/// defer.
void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  Future<void> storeRaw(String id, String raw) => db.customStatement(
    'UPDATE dances SET figures_json = ? WHERE id = ?',
    [raw, id],
  );

  Future<void> clearMarker(String key) =>
      db.customStatement('DELETE FROM settings WHERE key = ?', [key]);

  Future<bool> markerPresent(String key) async =>
      (await db
              .customSelect(
                'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
                variables: [Variable<String>(key)],
              )
              .get())
          .isNotEmpty;

  test('the rebuild completes for an undecodable row with NO skip', () async {
    // The case the gate never covered, and the reason it was a false mechanism
    // rather than a safety one: `[1,2,3]` is valid JSON, so the normalisation
    // pass records no skip for it, so a gate keyed on `normalisation_skips`
    // never fires — while the rebuild still had to read the row. This passes
    // both with and without the gate; it documents what the gate did not do.
    await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
    await repos.ensureMigrated();
    await storeRaw('d1', '[1,2,3]');

    expect(
      await db.customSelect('SELECT 1 FROM normalisation_skips').get(),
      isEmpty,
      reason: 'precondition: normalisable, so no skip is recorded',
    );

    await repos.dances.rebuildAllDerived();

    expect(
      await db
          .customSelect(
            'SELECT 1 FROM dance_fts WHERE dance_id = ?',
            variables: [const Variable<String>('d1')],
          )
          .get(),
      isNotEmpty,
    );
  });

  test('a recorded dances skip no longer defers the index repair', () async {
    // The behaviour this PR changes, and it is only visible on the ONE-TIME
    // path: the repair sweep is marker-gated, so a guard that runs after
    // `ensureMigrated()` has written its marker can never enter it. Clearing
    // `normalisationDerivedIndexRepairDoneKey` first is what makes the case
    // reachable at all.
    //
    // With the gate present the sweep sees a `dances` skip, defers, and leaves
    // its marker absent. Without it the repair runs to completion and writes
    // the marker.
    await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
    await repos.ensureMigrated();
    await storeRaw('d1', '[{"kind":');
    await db.customStatement(
      'INSERT OR REPLACE INTO normalisation_skips '
      '(table_name, column_name, record_id) VALUES (?, ?, ?)',
      ['dances', 'figures_json', 'd1'],
    );
    await clearMarker(normalisationDerivedIndexRepairDoneKey);

    await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

    expect(
      await markerPresent(normalisationDerivedIndexRepairDoneKey),
      isTrue,
      reason:
          'the repair is performed rather than deferred, so its marker is '
          'written; with the gate present it stays absent',
    );
    expect(
      await db
          .customSelect(
            'SELECT figures_json FROM dances WHERE id = ?',
            variables: [const Variable<String>('d1')],
          )
          .getSingle()
          .then((r) => r.read<String>('figures_json')),
      '[{"kind":',
      reason: 'the undecodable row is still left exactly as stored',
    );
  });
}
