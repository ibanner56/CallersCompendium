import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// Writes [raw] straight into `dances.figures_json`, bypassing the repository.
///
/// The write path canonicalizes and re-encodes, so it cannot produce any of
/// these values; a raw UPDATE is how they actually arise (a pre-fix build, an
/// external tool, disk corruption).
Future<void> _storeRawFigures(
  CompendiumDatabase db,
  String danceId,
  String raw,
) => db.customStatement('UPDATE dances SET figures_json = ? WHERE id = ?', [
  raw,
  danceId,
]);

Future<String> _storedFigures(CompendiumDatabase db, String danceId) async =>
    (await db
            .customSelect(
              'SELECT figures_json FROM dances WHERE id = ?',
              variables: [Variable<String>(danceId)],
            )
            .getSingle())
        .read<String>('figures_json');

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  // Each of these raised out of `getById`/`listAll` before this fix, which meant
  // out of `ensureMigrated()` at startup. The two ArgumentError cases are the
  // ones a sentinel catching only FormatException would still have died on —
  // `decodeFigures`'s own doc claimed FormatException alone.
  const undecodable = <String, String>{
    'not JSON at all': '[{"kind":',
    'root is not an array': '{"a":1}',
    'entry is not an object': '[1,2,3]',
    'empty move (ArgumentError)': '[{"move":""}]',
    'non-integer beats (ArgumentError)':
        '[{"move":"swing","params":{"beats":1e999}}]',
  };

  group('an undecodable transcription does not take down the load path', () {
    undecodable.forEach((label, raw) {
      test('$label: startup completes and the dance still loads', () async {
        await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
        await repos.ensureMigrated();
        await _storeRawFigures(db, 'd1', raw);

        // The assertion that matters: this raised before the fix.
        await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

        final dance = await repos.dances.getById('d1');
        expect(dance, isNotNull);
        expect(
          dance!.figuresSource,
          isA<UnreadableFigures>().having(
            (s) => s.storedJson,
            'storedJson',
            raw,
          ),
          reason: 'the stored text must be carried verbatim, not replaced',
        );
        expect(await repos.dances.listAll(), hasLength(1));
      });
    });
  });

  test(
    'the rebuild completes for an undecodable row with NO skip recorded',
    () async {
      // `[1,2,3]` normalises perfectly — it is valid JSON — so the normalisation
      // pass records nothing for it. Any gate keyed on `normalisation_skips` is
      // therefore blind to this row while the rebuild still has to read it. That
      // asymmetry is why tolerance belongs at the decode site and not behind a
      // skip-table check.
      await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
      await repos.ensureMigrated();
      await _storeRawFigures(db, 'd1', '[1,2,3]');

      expect(
        await db.customSelect('SELECT 1 FROM normalisation_skips').get(),
        isEmpty,
        reason:
            'precondition: this value is normalisable, so nothing is recorded',
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
        reason: 'the dance keeps its title/FTS row so it stays findable',
      );
      expect(
        await db
            .customSelect(
              'SELECT 1 FROM dance_figures WHERE dance_id = ?',
              variables: [const Variable<String>('d1')],
            )
            .get(),
        isEmpty,
        reason: 'there are no figures to index',
      );
    },
  );

  test(
    'an ordinary edit leaves an unreadable transcription untouched',
    () async {
      const raw = '[{"kind":';
      await repos.dances.create(sampleDance(id: 'd1', title: 'Before'));
      await repos.ensureMigrated();
      await _storeRawFigures(db, 'd1', raw);

      final loaded = await repos.dances.getById('d1');
      await repos.dances.update(loaded!.copyWith(title: 'After'));

      expect(await _storedFigures(db, 'd1'), raw);
      final reloaded = await repos.dances.getById('d1');
      expect(reloaded!.title, 'After');
      expect(reloaded.figuresSource, isA<UnreadableFigures>());
    },
  );

  test('a duplicate carries the stored transcription through', () async {
    const raw = '[1,2,3]';
    await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
    await repos.ensureMigrated();
    await _storeRawFigures(db, 'd1', raw);

    final loaded = await repos.dances.getById('d1');
    await repos.dances.create(
      loaded!.duplicate(newId: 'd2', now: DateTime.utc(2026, 5, 1)),
    );

    expect(await _storedFigures(db, 'd2'), raw);
  });

  group('archive', () {
    test('a healthy library is unaffected by the new key or version', () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Fine'));
      await repos.ensureMigrated();

      final archive = await ArchiveExporter(repos).export();
      final encoded = encodeArchive(archive);

      expect(
        encoded.contains('figuresRaw'),
        isFalse,
        reason: 'the quarantine key is emitted only when it is needed',
      );
      expect(
        requiredSchemaVersion(archive),
        lessThan(archiveSchemaVersionUnreadableFigures),
        reason:
            'a library with nothing undecodable must not be pushed to v5 — '
            'this is what keeps the stamp conditional rather than universal',
      );
    });

    test('an undecodable transcription round-trips verbatim at v5', () async {
      const raw = '[{"move":""}]';
      await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
      await repos.ensureMigrated();
      await _storeRawFigures(db, 'd1', raw);

      final archive = await ArchiveExporter(repos).export();
      expect(
        requiredSchemaVersion(archive),
        archiveSchemaVersionUnreadableFigures,
      );

      final encoded = encodeArchive(archive);
      final decoded = decodeArchive(encoded);
      final dance = decoded.archive.dances.singleWhere((d) => d.id == 'd1');
      expect(
        dance.figuresSource,
        isA<UnreadableFigures>().having((s) => s.storedJson, 'storedJson', raw),
      );

      // The identity property this codec states: re-encoding what was decoded
      // reproduces the same string, so the new key does not break it.
      expect(encodeArchive(decoded.archive), encoded);
    });
  });

  group('sync never publishes a body for an undecodable transcription', () {
    // The property a later refactor would break: no body produced by ANY
    // publish path may carry `figuresRaw`. A peer that does not understand the
    // key applies the empty `figures` array beside it over its own readable
    // copy, turning a row this device merely cannot read into cross-device
    // data loss.
    //
    // These paths became reachable only because this change made
    // `listAll`/`getById` return such a dance instead of raising, so the guard
    // belongs with the change that created them.
    late CompendiumSyncStorage storage;

    setUp(() => storage = CompendiumSyncStorage(repos));

    Future<void> seedUndecodable() async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
      await repos.ensureMigrated();
      await _storeRawFigures(db, 'd1', '[{"kind":');
    }

    test('snapshot publishes no dance body at all', () async {
      await seedUndecodable();
      final snapshot = await storage.snapshot();
      final bodies = [
        for (final c in snapshot.local.values) c?.blob.body,
        for (final c in snapshot.publication.values) c?.blob.body,
      ].whereType<Map<String, Object?>>();
      for (final body in bodies) {
        expect(
          body.containsKey('figuresRaw'),
          isFalse,
          reason: 'no published body may carry the quarantine key',
        );
      }
      expect(
        snapshot.local[(kind: SyncRecordKind.dance, recordId: 'd1')],
        isNull,
        reason: 'the record is withheld, not published empty',
      );
    });

    test('fresh-attach dedupe does not offer it as a match', () async {
      // Reaches `_danceDedupePlan`, which builds blobs straight from `listAll`
      // and never consults the record-body read.
      //
      // The pairing is deliberate: dedupe groups by normalised title AND by
      // choreography key, so the partner must have an EMPTY figure list to
      // share a key with the undecodable row's body (which serialises as an
      // empty `figures` array beside `figuresRaw`). A partner with real figures
      // groups separately and the test would pass whether or not the withhold
      // exists — which is exactly what the first version of this test did.
      await seedUndecodable();
      await repos.dances.create(
        sampleDance(id: 'd2', title: 'Corrupt', figures: const []),
      );

      final result = await storage.deduplicateFreshAttach();

      expect(
        result.duplicateCount,
        0,
        reason:
            'the undecodable row is not offered as a dedupe match, so no '
            'duplicate pair is seen',
      );
    });

    test('merge candidates omit it', () async {
      await seedUndecodable();
      final candidates = await storage.snapshotCandidates();
      expect(candidates[(kind: SyncRecordKind.dance, recordId: 'd1')], isNull);
      for (final c in candidates.values) {
        expect(c?.blob.body.containsKey('figuresRaw') ?? false, isFalse);
      }
    });
  });
}
