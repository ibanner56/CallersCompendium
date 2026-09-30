// A dance's wire body carries a custom-field value only while the field's
// definition is live and shareable (`CompendiumSyncStorage.snapshot`). A change
// to that state therefore changes the body of every dance holding a value
// without touching the dance's own row, and sync-spec §6.5 I1 requires it to
// advance their `updatedAt` anyway. Without that, two devices carry the same
// `updatedAt` over different bodies and merge reports `equalUpdatedAt` forever.
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:test/test.dart';

import 'test_database.dart';

final _t0 = DateTime.utc(2026, 1, 1, 12);
final _t1 = DateTime.utc(2026, 1, 2, 12);
final _t2 = DateTime.utc(2026, 1, 3, 12);
final _t3 = DateTime.utc(2026, 1, 4, 12);
final _t4 = DateTime.utc(2026, 1, 5, 12);

CustomFieldDef _def({bool shareable = true, String label = 'Origin'}) =>
    CustomFieldDef(
      id: 'f1',
      key: 'origin',
      label: label,
      type: CustomFieldType.text,
      shareable: shareable,
    );

Dance _dance(String id, {bool withValue = true}) => Dance(
  id: id,
  title: 'Dance $id',
  figures: [testFigure(move: 'balance')],
  customFields: [
    if (withValue) CustomFieldValue(fieldId: 'f1', value: 'New England'),
  ],
  createdAt: _t0,
  updatedAt: _t0,
);

final class _Device {
  _Device() : db = openTestDatabase() {
    repositories = CompendiumRepositories(db, contraTaxonomy);
    storage = CompendiumSyncStorage(repositories);
  }

  final CompendiumDatabase db;
  late final CompendiumRepositories repositories;
  late final CompendiumSyncStorage storage;

  CustomFieldDefRepository get defs => repositories.customFieldDefs;

  Future<void> seed({required bool shareable}) async {
    // ignore: unused_result
    await defs.upsert(_def(shareable: shareable), at: _t0);
    await repositories.dances.create(_dance('d1'));
  }

  Future<DateTime> updatedAt(String id) async => (await (db.select(
    db.dances,
  )..where((t) => t.id.equals(id))).getSingle()).updatedAt.toUtc();

  Future<SyncMergeCandidate> danceCandidate(String id) async =>
      (await storage.snapshot()).local[(
        kind: SyncRecordKind.dance,
        recordId: id,
      )]!;
}

void main() {
  // The two-device tests hold two in-memory databases on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late _Device device;

  setUp(() => device = _Device());
  tearDown(() => device.db.close());

  group('shareability flip', () {
    for (final start in [true, false]) {
      test('${start ? 'shareable to private' : 'private to shareable'} stamps '
          'every dance holding a value, live or tombstoned', () async {
        await device.seed(shareable: start);
        await device.repositories.dances.create(_dance('d2'));
        await device.repositories.dances.softDelete('d2', at: _t1);
        await device.repositories.dances.create(
          _dance('none', withValue: false),
        );

        // ignore: unused_result
        await device.defs.upsert(_def(shareable: !start), at: _t2);

        expect(await device.updatedAt('d1'), _t2);
        expect(await device.updatedAt('d2'), _t2);
        expect(await device.updatedAt('none'), _t0);
      });
    }

    test('an edit that leaves shareability alone stamps nothing', () async {
      await device.seed(shareable: true);

      // ignore: unused_result
      await device.defs.upsert(_def(label: 'Renamed'), at: _t2);

      expect(await device.updatedAt('d1'), _t0);
    });

    test('an inbound definition write stamps nothing', () async {
      await device.seed(shareable: true);

      await device.defs.writeFromSync(_def(shareable: false), at: _t2);

      expect(await device.updatedAt('d1'), _t0);
    });

    test('re-creating over a tombstoned definition stamps the dances that '
        'still hold its values', () async {
      await device.seed(shareable: true);
      await device.repositories.dances.softDelete('d1', at: _t1);
      await device.defs.delete('f1', at: _t2);
      expect(await device.updatedAt('d1'), _t2);

      // ignore: unused_result
      await device.defs.upsert(_def(), at: _t3);

      expect(await device.updatedAt('d1'), _t3);
    });
  });

  group('definition delete and restore', () {
    test('deleting a shareable definition stamps a tombstoned dance that '
        'still holds a value', () async {
      await device.seed(shareable: true);
      await device.repositories.dances.softDelete('d1', at: _t1);

      await device.defs.delete('f1', at: _t2);

      expect(await device.updatedAt('d1'), _t2);
    });

    test('restoring a shareable definition stamps a live dance that holds a '
        'value for it', () async {
      await device.seed(shareable: true);
      await device.repositories.dances.softDelete('d1', at: _t1);
      await device.defs.delete('f1', at: _t2);
      await device.repositories.dances.restore('d1', at: _t3);

      await device.defs.restore('f1', at: _t4);

      expect(await device.updatedAt('d1'), _t4);
    });

    test('a private definition never reaches the wire, so neither delete nor '
        'restore stamps', () async {
      await device.seed(shareable: false);
      await device.repositories.dances.softDelete('d1', at: _t1);

      await device.defs.delete('f1', at: _t2);
      expect(await device.updatedAt('d1'), _t1);

      await device.defs.restore('f1', at: _t3);
      expect(await device.updatedAt('d1'), _t1);
    });

    test('deleting an already deleted definition stamps nothing', () async {
      await device.seed(shareable: true);
      await device.repositories.dances.softDelete('d1', at: _t1);
      await device.defs.delete('f1', at: _t2);

      await device.defs.delete('f1', at: _t3);

      expect(await device.updatedAt('d1'), _t2);
    });

    test('restoring a live definition stamps nothing', () async {
      await device.seed(shareable: true);

      await device.defs.restore('f1', at: _t2);

      expect(await device.updatedAt('d1'), _t0);
    });
  });

  group('two devices', () {
    for (final start in [true, false]) {
      test(
        '${start ? 'shareable to private' : 'private to shareable'} flip '
        'made on A is downloaded by B, not reported as equalUpdatedAt',
        () async {
          final a = device;
          final b = _Device();
          addTearDown(b.db.close);
          await a.seed(shareable: start);
          await b.seed(shareable: start);
          final synced = await b.danceCandidate('d1');
          expect(
            (await a.danceCandidate('d1')).wireHash,
            synced.wireHash,
            reason: 'the devices start in sync',
          );

          // ignore: unused_result
          await a.defs.upsert(_def(shareable: !start), at: _t1);

          final fromA = await a.danceCandidate('d1');
          expect(
            fromA.wireHash,
            isNot(synced.wireHash),
            reason: 'the flip changes the wire body',
          );
          final plan = const SyncMergeEngine().plan(
            local: (await b.storage.snapshot()).local,
            baseline: {
              synced.address: SyncBaselineEntry(
                kind: synced.address.kind,
                recordId: synced.address.recordId,
                wireHash: synced.wireHash,
              ),
            },
            peers: [
              {fromA.address: fromA},
            ],
          );

          expect(plan.reports, isEmpty);
          expect(
            plan.decisions
                .singleWhere((d) => d.address == fromA.address)
                .action,
            SyncMergeAction.download,
          );
        },
      );
    }
  });
}
