import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late SnapshotRepository repo;

  setUp(() {
    db = openTestDatabase();
    repo = SnapshotRepository(db);
  });

  tearDown(() => db.close());

  test('round-trips a snapshot record', () async {
    final snap = SnapshotRecord(
      source: 'callersbox',
      snapshotDate: DateTime.utc(2026, 6, 1),
      manifestJson: '{"count": 4000}',
      importedAt: DateTime.utc(2026, 6, 2),
    );
    await repo.upsert(snap);
    expect(await repo.getBySource('callersbox'), snap);
  });

  test('upsert replaces the prior snapshot for the same source', () async {
    await repo.upsert(
      SnapshotRecord(
        source: 'callersbox',
        snapshotDate: DateTime.utc(2026, 1, 1),
        manifestJson: '{"count": 100}',
        importedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await repo.upsert(
      SnapshotRecord(
        source: 'callersbox',
        snapshotDate: DateTime.utc(2026, 6, 1),
        manifestJson: '{"count": 4000}',
        importedAt: DateTime.utc(2026, 6, 2),
      ),
    );
    final all = await repo.listAll();
    expect(all, hasLength(1));
    expect(all.single.manifestJson, '{"count": 4000}');
  });

  test('getBySource returns null when unknown', () async {
    expect(await repo.getBySource('nope'), isNull);
  });

  test('delete removes the record', () async {
    await repo.upsert(
      SnapshotRecord(
        source: 'contradb',
        snapshotDate: DateTime.utc(2026),
        manifestJson: '{}',
        importedAt: DateTime.utc(2026),
      ),
    );
    await repo.delete('contradb');
    expect(await repo.getBySource('contradb'), isNull);
  });
}
