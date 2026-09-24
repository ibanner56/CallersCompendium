// A record withheld from sync because this device cannot decode its stored
// figures or tunes must SAY SO (#1347). The withhold itself is older and is not
// what these tests guard: they guard that it stopped being silent.
//
// Shaped around the property rather than around one instance, because this
// issue has now been bitten four times by the opposite:
//
//   * the #1382 withholds tested `figuresSource` only, so a tunes-only row was
//     still published;
//   * the sync guards asserted `figuresRaw` never appears in a body, which a
//     tunes-only row satisfies while publishing an empty list;
//   * `choreographyFingerprintForDance`'s field list gained `figuresRaw` and
//     not `tunesRaw`;
//   * and `unreadable_tunes_test.dart`'s own withhold guard drives `snapshot()`
//     and `snapshotCandidates()` while reading as two paths —
//     `snapshotCandidates()` is a delegation to `snapshot()`
//     (`sync_storage.dart`), so one of the four withhold sites was covered
//     twice and two were not covered at all for that column.
//
// So: BOTH columns against EACH reporting path, every path driven by its own
// public entry point, and never through a delegation.
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

Future<void> _storeRawFigures(CompendiumDatabase db, String id, String raw) =>
    db.customStatement('UPDATE dances SET figures_json = ? WHERE id = ?', [
      raw,
      id,
    ]);

Future<void> _storeRawTunes(CompendiumDatabase db, String id, String raw) =>
    db.customStatement('UPDATE dances SET tunes_json = ? WHERE id = ?', [
      raw,
      id,
    ]);

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;
  late CompendiumSyncStorage storage;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
    storage = CompendiumSyncStorage(repos);
  });

  tearDown(() => db.close());

  /// The two stored columns the withhold covers, each with a value that is
  /// undecodable for a *different* reason so neither case is a re-run of the
  /// other: the figure text is not JSON at all, the tune list is well-formed
  /// JSON whose elements are the wrong type.
  final columns = <String, Future<void> Function(String id)>{
    'figures': (id) => _storeRawFigures(db, id, '[{"kind":'),
    'tunes': (id) => _storeRawTunes(db, id, '[1,2,3]'),
  };

  Future<void> seedUndecodable(
    Future<void> Function(String id) corrupt, {
    String id = 'd1',
    String title = 'Corrupt',
  }) async {
    await repos.dances.create(sampleDance(id: id, title: title));
    await repos.ensureMigrated();
    await corrupt(id);
  }

  Iterable<SyncReport> withheldFor(Iterable<SyncReport> reports, String id) =>
      reports.where(
        (report) =>
            report.code == SyncReportCode.withheldUnreadableRecord &&
            report.recordId == id,
      );

  group('a withheld record is reported, not silently absent', () {
    columns.forEach((column, corrupt) {
      // Each path gets its own test per column. Driving one path and asserting
      // over a union of reports would let a single emission satisfy all three.
      test('$column: snapshot() reports the record it withholds', () async {
        await seedUndecodable(corrupt);

        final snapshot = await storage.snapshot();

        expect(
          snapshot.local[(kind: SyncRecordKind.dance, recordId: 'd1')],
          isNull,
          reason: 'precondition: the withhold itself still holds',
        );
        expect(
          withheldFor(snapshot.withheld, 'd1'),
          hasLength(1),
          reason: 'the withhold must not be silent',
        );
      });

      test('$column: a fresh attach reports the record it will not '
          'offer as a dedupe match', () async {
        // Drives `deduplicateFreshAttach()`, which builds its candidates
        // straight from `listAll` and never takes a snapshot — so a report
        // here can only have come from the dedupe plan's own withhold.
        await seedUndecodable(corrupt);

        final result = await storage.deduplicateFreshAttach();

        expect(result.duplicateCount, 0);
        expect(withheldFor(result.reports, 'd1'), hasLength(1));
      });

      test('$column: a steady-state pass reports a queued review candidate '
          'it can no longer read', () async {
        // Drives `refreshDanceAmbiguityReviews()`, the only pass-reachable
        // caller that passes a sink to the merge-candidate build. The pair is
        // queued while both rows are readable, then one is corrupted, which is
        // the order a real install reaches this in.
        final stamp = DateTime.utc(2026, 3, 1);
        await repos.dances.create(
          Dance(
            id: 'd1',
            title: 'Shared dance',
            figures: [testFigure(move: 'swing')],
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
        await repos.dances.create(
          Dance(
            id: 'd2',
            title: 'Shared dance',
            figures: [testFigure(move: 'balance')],
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
        await repos.ensureMigrated();
        await storage.deduplicateFreshAttach();
        expect(
          await repos.syncLocal.listReviewQueue(),
          hasLength(1),
          reason: 'precondition: the pair is queued while both rows read',
        );

        await corrupt('d1');
        final result = await storage.refreshDanceAmbiguityReviews();

        expect(withheldFor(result.reports, 'd1'), hasLength(1));
      });
    });

    test('the report names the record and blames no peer', () async {
      await seedUndecodable(columns['figures']!);

      final report = (await storage.snapshot()).withheld.single;

      expect(report.code, SyncReportCode.withheldUnreadableRecord);
      expect(report.kind, SyncRecordKind.dance);
      expect(report.recordId, 'd1');
      // Load-bearing, not incidental. A null peer id is what says the fault is
      // a row on THIS device; the app's notice mapping already uses exactly
      // that distinction to keep `quarantinedRecord`'s local case away from
      // copy that sends the user to another device.
      expect(report.peerId, isNull);
    });

    test('a healthy library reports nothing', () async {
      // The complementary vector. Without it, a mutation that reports every
      // dance unconditionally passes every test above.
      await repos.dances.create(sampleDance(id: 'd1', title: 'Fine'));
      await repos.dances.create(sampleDance(id: 'd2', title: 'Also fine'));
      await repos.ensureMigrated();

      expect((await storage.snapshot()).withheld, isEmpty);
      expect(
        (await storage.deduplicateFreshAttach()).reports.where(
          (report) => report.code == SyncReportCode.withheldUnreadableRecord,
        ),
        isEmpty,
      );
    });

    test('each withheld record is reported once per path, so the '
        "coordinator's sink coalesces them to one notice", () async {
      // Two undecodable rows, one per column, in one library: the count is the
      // number of records, not the number of columns or of loop iterations.
      await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt one'));
      await repos.dances.create(sampleDance(id: 'd2', title: 'Corrupt two'));
      await repos.ensureMigrated();
      await _storeRawFigures(db, 'd1', '[{"kind":');
      await _storeRawTunes(db, 'd2', '[1,2,3]');

      final snapshot = await storage.snapshot();

      expect(snapshot.withheld, hasLength(2));
      expect(
        snapshot.withheld.map((report) => report.coalescingKey).toSet(),
        hasLength(2),
        reason: 'two records must not collapse into one notice',
      );
    });
  });
}
