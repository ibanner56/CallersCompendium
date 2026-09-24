import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

Future<void> _storeRawTunes(CompendiumDatabase db, String id, String raw) =>
    db.customStatement('UPDATE dances SET tunes_json = ? WHERE id = ?', [
      raw,
      id,
    ]);

Future<String> _storedTunes(CompendiumDatabase db, String id) async =>
    (await db
            .customSelect(
              'SELECT tunes_json FROM dances WHERE id = ?',
              variables: [Variable<String>(id)],
            )
            .getSingle())
        .read<String>('tunes_json');

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  // Measured, not inferred. Three of the four are TypeError rather than
  // FormatException, and the element failures are lazy — `cast<String>()` did
  // not throw at the cast, it threw when `List.unmodifiable` iterated it inside
  // the Dance constructor.
  const undecodable = <String, String>{
    'not JSON at all': '[{"a":',
    'root is not a list': '{"a":1}',
    'element is not a string (TypeError)': '[1,2,3]',
    'null element (TypeError)': '[null]',
  };

  group('an undecodable tune list does not take down the load path', () {
    undecodable.forEach((label, raw) {
      test('$label: the dance still loads and keeps its text', () async {
        await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
        await repos.ensureMigrated();
        await _storeRawTunes(db, 'd1', raw);

        await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

        final dance = await repos.dances.getById('d1');
        expect(dance, isNotNull);
        expect(
          dance!.tunesSource,
          isA<UnreadableTunes>().having((s) => s.storedJson, 'storedJson', raw),
        );
        expect(await repos.dances.listAll(), hasLength(1));
      });
    });
  });

  test(
    'a pending one-time sweep completes with an undecodable tune list',
    () async {
      // The case that reopened after the rebuild gate was removed: with a repair
      // owed, the sweep loads every dance. A guard that runs after
      // `ensureMigrated()` has written the markers cannot see this, so the marker
      // is cleared first.
      await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
      await repos.ensureMigrated();
      await _storeRawTunes(db, 'd1', '[1,2,3]');
      await db.customStatement('DELETE FROM settings WHERE key = ?', [
        normalisationDerivedIndexRepairDoneKey,
      ]);

      await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

      expect(await _storedTunes(db, 'd1'), '[1,2,3]');
    },
  );

  test('an ordinary edit leaves an unreadable tune list untouched', () async {
    const raw = '[{"a":';
    await repos.dances.create(sampleDance(id: 'd1', title: 'Before'));
    await repos.ensureMigrated();
    await _storeRawTunes(db, 'd1', raw);

    final loaded = await repos.dances.getById('d1');
    await repos.dances.update(loaded!.copyWith(title: 'After'));

    expect(await _storedTunes(db, 'd1'), raw);
    expect((await repos.dances.getById('d1'))!.title, 'After');
  });

  test('a duplicate carries the stored tune text through', () async {
    const raw = '[1,2,3]';
    await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
    await repos.ensureMigrated();
    await _storeRawTunes(db, 'd1', raw);

    final loaded = await repos.dances.getById('d1');
    await repos.dances.create(
      loaded!.duplicate(newId: 'd2', now: DateTime.utc(2026, 5, 1)),
    );

    expect(await _storedTunes(db, 'd2'), raw);
  });

  group('batch tune edits skip a row they cannot read', () {
    setUp(() async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
      await repos.ensureMigrated();
      await _storeRawTunes(db, 'd1', '[1,2,3]');
    });

    test('adding tunes does not rewrite it', () async {
      await repos.dances.addTunesForMany(
        const ['d1'],
        tunes: const ['Reel'],
        now: DateTime.utc(2026, 5, 1),
      );
      expect(await _storedTunes(db, 'd1'), '[1,2,3]');
    });

    test('clearing tunes does not rewrite it', () async {
      // Clearing is the user's intent, but a BATCH clear would destroy text the
      // undo snapshot cannot restore: the snapshot is a `List<String>`.
      await repos.dances.clearTunesForMany(const [
        'd1',
      ], now: DateTime.utc(2026, 5, 1));
      expect(await _storedTunes(db, 'd1'), '[1,2,3]');
    });
  });

  // Four guards, four tests, and one test per guard is not pedantry:
  // `snapshotCandidates()` delegates straight to `snapshot()`, so asserting on
  // both only ever exercised the `snapshot()` guard and the other three could
  // be deleted with the suite still green. Each test below drives its own path
  // through a public entry point that reaches that guard and no other, so
  // removing one guard reds exactly one named test.
  //
  // Three of the four are outbound publication: `snapshot()`, `_danceDedupePlan`
  // and `_danceCandidate`. Their shared hazard is that `tunesRaw` is dropped by
  // the shareable wire allow-list, so a peer receives `tunes: []` with no marker
  // and applies it over its own readable list.
  //
  // `_readDanceBody` is NOT a publication path and must not be described as one:
  // its only caller is `read(address)`, which `sync_apply.dart` uses twice as
  // `await storage.read(...) ?? const {}` to fetch the CURRENT LOCAL body an
  // INBOUND record is overlaid onto. Its guard is still right, for a different
  // reason — it stops an inbound update merging onto a body this device built
  // from text it could not read.
  group('sync withholds an undecodable tune list', () {
    test('snapshot() withholds the record', () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
      await repos.ensureMigrated();
      await _storeRawTunes(db, 'd1', '[1,2,3]');

      final snapshot = await CompendiumSyncStorage(repos).snapshot();

      expect(
        snapshot.local[(kind: SyncRecordKind.dance, recordId: 'd1')],
        isNull,
        reason: 'withheld, not published with an empty tune list',
      );
    });

    test('read() withholds the inbound overlay base [_readDanceBody]', () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
      await repos.ensureMigrated();
      await _storeRawTunes(db, 'd1', '[1,2,3]');

      expect(
        await CompendiumSyncStorage(
          repos,
        ).read((kind: SyncRecordKind.dance, recordId: 'd1')),
        isNull,
      );
    });

    test(
      'deduplicateFreshAttach() does not merge it away [_danceDedupePlan]',
      () async {
        // Both dances carry the default fixture choreography and an empty tune
        // list, so on the wire — where `tunesRaw` is stripped — their bodies are
        // identical and the planner would merge them. Losing the undecodable row
        // to a merge destroys the only copy of the stored text.
        await repos.dances.create(sampleDance(id: 'd1', title: 'Same Title'));
        await repos.dances.create(sampleDance(id: 'd2', title: 'Same Title'));
        await repos.ensureMigrated();
        await _storeRawTunes(db, 'd1', '[1,2,3]');

        final result = await CompendiumSyncStorage(
          repos,
        ).deduplicateFreshAttach();

        expect(
          result.duplicateCount,
          0,
          reason: 'an undecodable dance is not offered as a dedupe candidate',
        );
        expect(await repos.dances.getById('d1'), isNotNull);
        expect(await repos.dances.getById('d2'), isNotNull);
        expect(await _storedTunes(db, 'd1'), '[1,2,3]');
      },
    );

    test(
      'refreshDanceAmbiguityReviews() does not pair it [_danceCandidate]',
      () async {
        // Same normalised title, different choreography, equal `updatedAt` — the
        // shape that produces an `equalUpdatedAt` ambiguity report. With the
        // guard the candidate is null and the pair never forms.
        await repos.dances.create(sampleDance(id: 'd1', title: 'Same Title'));
        await repos.dances.create(
          sampleDance(
            id: 'd2',
            title: 'Same Title',
            figures: [Figure(move: 'circle', params: const {'beats': 8})],
          ),
        );
        await repos.ensureMigrated();
        await _storeRawTunes(db, 'd1', '[1,2,3]');
        await repos.syncLocal.enqueueReview(
          kind: SyncRecordKind.dance,
          recordId: 'd1',
          counterpartId: 'd2',
          reason: syncDanceChoreographyAmbiguityReason,
          candidateBlob: '{}',
          candidateHash: 'hash',
          queuedAt: DateTime.utc(2026, 5, 1),
        );

        final result = await CompendiumSyncStorage(
          repos,
        ).refreshDanceAmbiguityReviews();

        expect(
          result.reports,
          isEmpty,
          reason: 'an undecodable dance is not offered as a merge candidate',
        );
      },
    );
  });

  test(
    'an undecodable tune list is not a choreography match for an empty one',
    () async {
      // `choreographyFingerprintForDance` reads the archive body, where an
      // undecodable list serialises as `tunes: []`. Without `tunesRaw` in the
      // fingerprint fields, this dance would fingerprint identically to one that
      // genuinely has no tunes — and `autoResolveAmbiguous` links equal
      // fingerprints confidently, with no user present.
      await repos.dances.create(sampleDance(id: 'd1', title: 'Same'));
      await repos.dances.create(sampleDance(id: 'd2', title: 'Same'));
      await repos.ensureMigrated();
      await _storeRawTunes(db, 'd1', '[1,2,3]');
      await _storeRawTunes(db, 'd2', '[]');

      final a = await repos.dances.getById('d1');
      final b = await repos.dances.getById('d2');

      expect(
        choreographyFingerprintForDance(a!),
        isNot(equals(choreographyFingerprintForDance(b!))),
        reason: 'unreadable must not fingerprint the same as genuinely empty',
      );
    },
  );

  group('archive', () {
    test('a healthy library is not pushed to v6', () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Fine'));
      await repos.ensureMigrated();

      final archive = await ArchiveExporter(repos).export();
      expect(encodeArchive(archive).contains('tunesRaw'), isFalse);
      expect(
        requiredSchemaVersion(archive),
        lessThan(archiveSchemaVersionUnreadableTunes),
      );
    });

    test('an undecodable tune list round-trips verbatim at v6', () async {
      const raw = '[1,2,3]';
      await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
      await repos.ensureMigrated();
      await _storeRawTunes(db, 'd1', raw);

      final archive = await ArchiveExporter(repos).export();
      expect(
        requiredSchemaVersion(archive),
        archiveSchemaVersionUnreadableTunes,
      );

      final encoded = encodeArchive(archive);
      final decoded = decodeArchive(encoded);
      expect(
        decoded.archive.dances.singleWhere((d) => d.id == 'd1').tunesSource,
        isA<UnreadableTunes>().having((s) => s.storedJson, 'storedJson', raw),
      );
      expect(encodeArchive(decoded.archive), encoded);
    });
  });
}
