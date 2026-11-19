// "Interpreted by" and "Interpreted in" (ADR-006 §9.2): the people who
// reconstructed a dance from its original publication, and when. Drawn from
// the same people list as the authors, stored for every form, and carried by
// storage, backup, sharing and Device Sync. A dance with neither encodes
// exactly as it did before they existed.
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/serialization/archive_entity_codec.dart'
    show archiveDanceToJson, withOmittedDanceDefaults;
import 'package:test/test.dart';

import '../storage/fixtures.dart';
import '../storage/test_database.dart';

final _t0 = DateTime.utc(2026, 11, 19);

String Function() _ids(String prefix) {
  var n = 0;
  return () => '$prefix-${n++}';
}

Dance _interpreted() => sampleDance().copyWith(
  form: DanceForm.ecd,
  formation: const Formation(FormationShape.dupleMinor),
  interpreterIds: const ['pat', 'cecil'],
  interpretedOn: PartialDate.parse('1985'),
);

SyncRecordBlob _blobOf(Dance dance) => syncRecordBlobForEntity(
  SyncRecordKind.dance,
  dance,
  updatedAt: dance.updatedAt,
  existenceAt: dance.updatedAt,
)!;

void main() {
  group('model', () {
    test('copyWith, duplicate and equality carry them', () {
      final dance = _interpreted();
      expect(dance.copyWith(title: 'Other').interpreterIds, ['pat', 'cecil']);
      expect(
        dance.copyWith(title: 'Other').interpretedOn,
        PartialDate.parse('1985'),
      );
      expect(dance.copyWith(clearInterpretedOn: true).interpretedOn, isNull);
      final copy = dance.duplicate(newId: 'copy', now: _t0);
      expect(copy.interpreterIds, ['pat', 'cecil']);
      expect(copy.interpretedOn, PartialDate.parse('1985'));
      expect(
        dance.copyWith(interpreterIds: const ['cecil', 'pat']),
        isNot(dance),
      );
      expect(
        dance.copyWith(interpretedOn: PartialDate.parse('1986')),
        isNot(dance),
      );
    });
  });

  group('storage', () {
    test(
      'a dance round-trips its interpreters, in order, and the date',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);
        for (final (id, name) in [
          ('pat', 'Pat Shaw'),
          ('cecil', 'Cecil Sharp'),
        ]) {
          final _ = await repos.choreographers.upsert(
            Choreographer(id: id, name: name),
            at: _t0,
          );
        }
        final dance = _interpreted();
        await repos.dances.create(dance);
        expect(await repos.dances.getById(dance.id), dance);
        expect((await repos.dances.listAll()).single, dance);

        await repos.dances.update(
          dance.copyWith(
            interpreterIds: const ['cecil'],
            clearInterpretedOn: true,
          ),
        );
        final updated = (await repos.dances.getById(dance.id))!;
        expect(updated.interpreterIds, ['cecil']);
        expect(updated.interpretedOn, isNull);
      },
    );
  });

  group('archive', () {
    test('round-trips them, and stamps the ECD envelope version', () {
      final dance = _interpreted();
      final json = encodeArchive(
        CompendiumArchive(exportedAt: _t0, dances: [dance]),
      );
      final read = decodeArchive(json);
      expect(read.errors, isEmpty);
      expect(read.archive.dances.single, dance);
      expect(
        (jsonDecode(json) as Map)['schemaVersion'],
        archiveSchemaVersionEcdDanceFields,
      );
    });

    test('a dance with neither has no new keys, even in a sync body, and '
        'no stamp', () {
      final dance = sampleDance();
      for (final optional in [false, true]) {
        final body = archiveDanceToJson(
          dance,
          const {},
          includeOptionalFields: optional,
        );
        expect(body.keys, isNot(contains('interpreterIds')));
        expect(body.keys, isNot(contains('interpretedOn')));
      }
      expect(
        requiredSchemaVersion(
          CompendiumArchive(exportedAt: _t0, dances: [dance]),
        ),
        lessThan(archiveSchemaVersionEcdDanceFields),
      );
    });

    for (final (name, dance) in [
      ('an interpreter', sampleDance().copyWith(interpreterIds: const ['p'])),
      (
        'an interpretation date',
        sampleDance().copyWith(interpretedOn: PartialDate.parse('1990-05')),
      ),
    ]) {
      test('$name alone stamps v8', () {
        expect(
          requiredSchemaVersion(
            CompendiumArchive(exportedAt: _t0, dances: [dance]),
          ),
          archiveSchemaVersionEcdDanceFields,
        );
      });
    }
  });

  group('sync', () {
    test('a body that leaves them out clears them when applied', () {
      final blob = _blobOf(
        _interpreted().copyWith(
          interpreterIds: const [],
          clearInterpretedOn: true,
        ),
      );
      expect(blob.body.keys, isNot(contains('interpreterIds')));
      final known = syncInboundKnownBody(blob);
      expect(known['interpreterIds'], isEmpty);
      expect(known.containsKey('interpretedOn'), isTrue);
      expect(known['interpretedOn'], isNull);
      expect(withOmittedDanceDefaults(blob.body)['interpreterIds'], isEmpty);
    });

    test('a body that carries them keeps them', () {
      final known = syncInboundKnownBody(_blobOf(_interpreted()));
      expect(known['interpreterIds'], ['pat', 'cecil']);
      expect(known['interpretedOn'], '1985');
    });

    test('identity reconciliation rewrites an interpreter id as it does an '
        'author id', () {
      final rewritten = rewriteSyncInboundReferences(
        _blobOf(_interpreted()).body,
        {
          SyncRecordKind.choreographer: {'pat': 'pat-local'},
        },
      );
      expect(rewritten['interpreterIds'], ['pat-local', 'cecil']);
    });

    test('the choreography fingerprint ignores them', () {
      expect(
        choreographyFingerprintForDance(_interpreted()),
        choreographyFingerprintForDance(
          _interpreted().copyWith(
            interpreterIds: const [],
            clearInterpretedOn: true,
          ),
        ),
      );
    });

    test('an inbound dance whose interpreter this device lacks is held back '
        'as an unresolved reference', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repositories = CompendiumRepositories(db, contraTaxonomy);
      final storage = CompendiumSyncStorage(repositories);
      final dance = sampleDance().copyWith(
        interpreterIds: const ['nobody'],
        updatedAt: _t0,
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [SyncMergeCandidate(blob: _blobOf(dance))],
        storage: storage,
      );
      expect(result.reports.single.code, SyncReportCode.unresolvedReference);
      expect(await repositories.dances.getById(dance.id), isNull);

      final interpreter = Choreographer(id: 'nobody', name: 'Somebody');
      final accepted = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: interpreter.id,
              updatedAt: _t0,
              deletedAt: null,
              existenceAt: _t0,
              body: syncBodyForEntity(
                SyncRecordKind.choreographer,
                interpreter,
              ),
            ),
          ),
          SyncMergeCandidate(blob: _blobOf(dance)),
        ],
        storage: storage,
      );
      expect(accepted.reports, isEmpty);
      expect((await repositories.dances.getById(dance.id))!.interpreterIds, [
        'nobody',
      ]);
    });
  });

  group('import of a shared dance', () {
    String sharedJson() => encodeArchive(
      CompendiumArchive(
        exportedAt: _t0,
        dances: [
          _interpreted().copyWith(
            authorIds: const ['playford'],
            interpreterIds: const ['pat', 'ghost'],
          ),
        ],
        choreographers: [
          Choreographer(id: 'playford', name: 'John Playford'),
          Choreographer(id: 'pat', name: 'Pat Shaw'),
        ],
      ),
    );

    test(
      'the draft names the interpreters it can, never the sender\'s ids',
      () async {
        final adapter = GenericJsonAdapter();
        final discovered = await adapter.discover(
          ImportRequest(payload: sharedJson()),
        );
        final draft = adapter.parse(await adapter.fetch(discovered.single));
        expect(draft.authorNames, ['John Playford']);
        expect(draft.interpreterNames, ['Pat Shaw']);
      },
    );

    test('committing resolves them to this library\'s people, creating a '
        'missing one and reusing one it has', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dances = DanceRepository(db, contraTaxonomy);
      final choreographers = ChoreographerRepository(db);
      final pipeline = ImportPipeline(dances, choreographers);
      // The receiver already has the author, under its own id.
      final _ = await choreographers.upsert(
        Choreographer(id: 'local-playford', name: 'John Playford'),
      );

      final batch = await pipeline.plan(
        GenericJsonAdapter(),
        ImportRequest(payload: sharedJson()),
      );
      final session = await pipeline.commit(
        batch,
        now: _t0,
        newId: _ids('new'),
      );

      expect(session.committedCount, 1);
      final imported = (await dances.getById(session.insertedDanceIds.single))!;
      expect(imported.authorIds, ['local-playford']);
      expect(imported.interpreterIds, hasLength(1));
      expect(imported.interpreterIds, isNot(contains('pat')));
      expect(
        (await choreographers.getById(imported.interpreterIds.single))!.name,
        'Pat Shaw',
      );
      expect(imported.interpretedOn, PartialDate.parse('1985'));

      // Undo takes back the person the import created for the credit.
      final createdId = imported.interpreterIds.single;
      await pipeline.undo(session);
      expect(await choreographers.getById(createdId), isNull);
      expect(await choreographers.getById('local-playford'), isNotNull);
    });
  });
}
