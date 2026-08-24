import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// Fixtures + tests for [GenericJsonAdapter]: our own canonical
/// [CompendiumArchive] JSON as a per-dance import source.

final _now = DateTime.utc(2026, 7, 15);

String Function() sequentialIds(String prefix) {
  var n = 0;
  return () => '$prefix-${++n}';
}

Dance _dance(
  String id,
  String title, {
  List<String> authorIds = const [],
  List<Figure> figures = const [],
  List<SourceCitation> sourceCitations = const [],
  List<CustomFieldValue> customFields = const [],
  Provenance? provenance,
  String walkthrough = '',
}) => Dance(
  id: id,
  title: title,
  authorIds: authorIds,
  figures: figures,
  sourceCitations: sourceCitations,
  customFields: customFields,
  provenance: provenance,
  walkthrough: walkthrough,
  createdAt: _now,
  updatedAt: _now,
);

CompendiumArchive _archive(List<Dance> dances) => CompendiumArchive(
  schemaVersion: archiveSchemaVersion,
  exportedAt: _now,
  dances: dances,
  choreographers: [Choreographer(id: 'c1', name: 'Cary Ravitz')],
  publishedSources: [PublishedSource(id: 's1', title: 'Give-and-Take')],
  customFields: [
    CustomFieldDef(
      id: 'f1',
      key: 'difficulty',
      label: 'Difficulty',
      type: CustomFieldType.text,
    ),
  ],
);

Map<String, Object?> _danceContentJson(Dance dance) {
  final root = jsonDecode(
    encodeArchive(CompendiumArchive(exportedAt: _now, dances: [dance])),
  ) as Map<String, Object?>;
  final content = Map<String, Object?>.from(
    (root['dances'] as List).single as Map,
  );
  for (final key in ['id', 'provenance', 'createdAt', 'updatedAt']) {
    content.remove(key);
  }
  return content;
}

/// Runs one dance through the full adapter path and returns the parsed draft.
Future<StructuredDraft> _importOne(
  GenericJsonAdapter adapter,
  DiscoveredRecord record,
) async {
  final raw = await adapter.fetch(record);
  return adapter.parse(raw);
}

void main() {
  group('GenericJsonAdapter', () {
    test('source is ProvenanceSource.json', () {
      expect(GenericJsonAdapter().source, ProvenanceSource.json);
    });

    test('round-trip preserves dance content through the codec', () async {
      final structured = _dance(
        'd1',
        'Give and Take',
        authorIds: ['c1'],
        figures: [
          Figure(move: 'swing', params: {'beats': 16, 'who': 'partners'}),
          customFigure('scoop them up', beats: 8),
        ],
        sourceCitations: [SourceCitation(sourceId: 's1', page: '42')],
        customFields: [CustomFieldValue(fieldId: 'f1', value: 'medium')],
        walkthrough: 'Walk forward, turn, and return.',
      );
      final custom = _dance(
        'd2',
        'All Custom',
        figures: [customFigure('do the thing', beats: 16)],
      );

      final json = encodeArchive(_archive([structured, custom]));
      final adapter = GenericJsonAdapter();
      final discovered = await adapter.discover(ImportRequest(payload: json));

      final byId = {
        for (final r in discovered)
          (r.locator['danceId'] as String): await _importOne(adapter, r),
      };

      final d1 = byId['d1']!.dance;
      expect(d1.title, 'Give and Take');
      expect(d1.authorIds, ['c1']);
      expect(d1.figures, structured.figures);
      expect(d1.sourceCitations, structured.sourceCitations);
      expect(d1.customFields, structured.customFields);
      expect(d1.walkthrough, structured.walkthrough);
      expect(d1.provenance, isNull, reason: 'pipeline attaches provenance');

      final d2 = byId['d2']!.dance;
      expect(d2.figures.single.isCustom, isTrue);
      expect(byId['d2']!.quality.isFullyCustom, isTrue);
    });

    test('pipeline preserves every archive dance content field', () async {
      final source = Dance(
        id: 'parity',
        title: 'Parity Dance',
        formation: const Formation(
          FormationShape.becketCw,
          detail: 'double progression',
        ),
        progression: Progression.double,
        phraseStructure: '4*8*4',
        figures: [customFigure('balance, swing')],
        hook: 'A memorable hook',
        callingNotes: 'Keep the transitions crisp.',
        walkthrough: 'Walk forward, turn, and return.',
        status: DanceStatus.deprecated,
        level: DanceLevel.advanced,
        mixedLevel: true,
        mixer: true,
        rating: 4,
        tunes: ['Parity Reel'],
        links: [
          DanceLink(
            id: 'link-1',
            kind: LinkKind.video,
            url: 'https://example.com/parity',
            label: 'Demo',
          ),
        ],
        composedOn: PartialDate(1998),
        revisedOn: PartialDate(2025, 4),
        createdAt: _now,
        updatedAt: _now,
      );
      final db = openTestDatabase();
      addTearDown(db.close);
      final dances = DanceRepository(db, contraTaxonomy);
      final pipeline = ImportPipeline(dances, ChoreographerRepository(db));
      final session = await pipeline.commit(
        await pipeline.plan(
          GenericJsonAdapter(),
          ImportRequest(payload: encodeArchive(_archive([source]))),
        ),
        now: _now,
        newId: sequentialIds('parity'),
      );

      final imported = await dances.getById(session.insertedDanceIds.single);
      expect(imported, isNotNull);
      expect(_danceContentJson(imported!), _danceContentJson(source));
    });

    test('enumerates one record per dance with correct labels/ids', () async {
      final json = encodeArchive(
        _archive([_dance('a', 'Alpha'), _dance('b', 'Beta')]),
      );
      final discovered = await GenericJsonAdapter().discover(
        ImportRequest(payload: json),
      );

      expect(discovered.map((r) => r.label), ['Alpha', 'Beta']);
      expect(discovered.map((r) => r.externalId), ['a', 'b']);
      expect(discovered.every((r) => r.source == ProvenanceSource.json), true);
    });

    test('externalId uses provenance.externalId when present', () async {
      final withProv = _dance(
        'internal-id',
        'Shared',
        provenance: Provenance(
          source: ProvenanceSource.json,
          externalId: 'shared-external-1',
          importedAt: _now,
        ),
      );
      final json = encodeArchive(_archive([withProv]));
      final adapter = GenericJsonAdapter();
      final discovered = await adapter.discover(ImportRequest(payload: json));

      expect(discovered.single.externalId, 'shared-external-1');
      final draft = await _importOne(adapter, discovered.single);
      expect(draft.raw.externalId, 'shared-external-1');
      // Provenance is stripped from the draft; pipeline re-derives it.
      expect(draft.dance.provenance, isNull);
    });

    group('parse-never-fails', () {
      test('a fully-custom dance parses without error', () async {
        final json = encodeArchive(
          _archive([
            _dance(
              'c',
              'Custom Only',
              figures: [customFigure('a'), customFigure('b')],
            ),
          ]),
        );
        final adapter = GenericJsonAdapter();
        final discovered = await adapter.discover(ImportRequest(payload: json));
        final draft = await _importOne(adapter, discovered.single);

        expect(draft.quality.isFullyCustom, isTrue);
        expect(draft.dance.figures.every((f) => f.isCustom), isTrue);
      });
    });

    group('malformed input', () {
      test('non-JSON payload fails discover with a structured error', () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final pipeline = ImportPipeline(
          DanceRepository(db, contraTaxonomy),
          ChoreographerRepository(db),
        );
        final result = await pipeline.plan(
          GenericJsonAdapter(),
          const ImportRequest(payload: 'not json {'),
        );
        expect(result.errors, hasLength(1));
        expect(result.errors.single.stage, ImportStage.discover);
        expect(result.plannedCount, 0);
      });

      test('non-object root fails discover', () async {
        final adapter = GenericJsonAdapter();
        expect(
          () => adapter.discover(const ImportRequest(payload: '[1,2,3]')),
          throwsA(isA<ImportError>()),
        );
      });

      test('missing payload fails discover', () async {
        final adapter = GenericJsonAdapter();
        expect(
          () => adapter.discover(const ImportRequest()),
          throwsA(isA<ImportError>()),
        );
      });

      test('a valid archive with zero dances yields no records', () async {
        final json = encodeArchive(_archive(const []));
        final discovered = await GenericJsonAdapter().discover(
          ImportRequest(payload: json),
        );
        expect(discovered, isEmpty);
      });

      test('unknown/extra fields on a dance are tolerated', () async {
        final json = encodeArchive(_archive([_dance('d', 'Forward Compat')]));
        final map = jsonDecode(json) as Map<String, Object?>;
        (((map['dances'] as List).first) as Map<String, Object?>)['futureKey'] =
            {'anything': true};
        final adapter = GenericJsonAdapter();
        final discovered = await adapter.discover(
          ImportRequest(payload: jsonEncode(map)),
        );
        expect(discovered.single.label, 'Forward Compat');
        final draft = await _importOne(adapter, discovered.single);
        expect(draft.dance.title, 'Forward Compat');
      });

      test('a structurally broken dance is skipped, not crashed', () async {
        final json = encodeArchive(
          _archive([_dance('ok', 'Good'), _dance('bad', 'Bad')]),
        );
        final map = jsonDecode(json) as Map<String, Object?>;
        final dances = (map['dances'] as List).cast<Map<String, Object?>>();
        // Corrupt the "Bad" dance: title must be a string (a non-string raises
        // a FormatException the codec skips, not a crash).
        dances.firstWhere((d) => d['id'] == 'bad')['title'] = 42;
        final adapter = GenericJsonAdapter();
        final discovered = await adapter.discover(
          ImportRequest(payload: jsonEncode(map)),
        );
        // The broken dance is skipped by the codec; enumeration survives.
        expect(discovered.map((r) => r.label), ['Good']);
      });
    });

    test('fetch rejects a record with an invalid locator', () async {
      final adapter = GenericJsonAdapter();
      expect(
        () => adapter.fetch(
          const DiscoveredRecord(source: ProvenanceSource.json),
        ),
        throwsA(
          isA<ImportError>().having((e) => e.stage, 'stage', ImportStage.fetch),
        ),
      );
    });

    test('a failed discover clears stale records from a prior run', () async {
      final adapter = GenericJsonAdapter();
      final good = encodeArchive(_archive([_dance('keep', 'Keep')]));
      final firstRecord = (await adapter.discover(
        ImportRequest(payload: good),
      )).single;

      await expectLater(
        adapter.discover(const ImportRequest(payload: 'not json {')),
        throwsA(isA<ImportError>()),
      );
      expect(() => adapter.fetch(firstRecord), throwsA(isA<ImportError>()));
    });

    test('exact (json, externalId) re-import resolves to reimport', () async {
      final dance = _dance('x1', 'Reimport Me', authorIds: ['c1']);
      final json = encodeArchive(_archive([dance]));
      final adapter = GenericJsonAdapter();
      final discovered = await adapter.discover(ImportRequest(payload: json));
      final draft = await _importOne(adapter, discovered.single);

      // An index that already contains this (source, externalId).
      final index = DedupeIndex([
        DedupeEntry(
          danceId: 'existing-99',
          title: 'Reimport Me',
          source: ProvenanceSource.json,
          externalId: 'x1',
        ),
      ]);
      final verdict = index.verdictFor(
        source: draft.raw.source,
        externalId: draft.raw.externalId,
        title: draft.dance.title,
      );
      expect(verdict.kind, DedupeKind.reimport);
      expect(verdict.targetDanceId, 'existing-99');
    });

    test('re-import updates the persisted walkthrough', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dances = DanceRepository(db, contraTaxonomy);
      final pipeline = ImportPipeline(dances, ChoreographerRepository(db));

      Future<ImportSession> commit(Dance dance) async => pipeline.commit(
        // A new adapter instance mirrors the independent source fetches used by
        // a real re-import.
        await pipeline.plan(
          GenericJsonAdapter(),
          ImportRequest(payload: encodeArchive(_archive([dance]))),
        ),
        now: _now,
        newId: sequentialIds('reimport'),
      );

      final first = await commit(
        _dance(
          'reimport-1',
          'Reimport Walkthrough',
          walkthrough: 'The original walkthrough.',
        ),
      );
      final id = first.insertedDanceIds.single;

      final second = await commit(
        _dance(
          'reimport-1',
          'Reimport Walkthrough',
          walkthrough: 'The revised walkthrough.',
        ),
      );

      expect(second.records.single.action, CommitAction.reimport);
      expect(
        (await dances.getById(id))!.walkthrough,
        'The revised walkthrough.',
      );
    });

    // #412: the adapter must carry the referenced choreographers' display names
    // through parse so the pipeline can resolve/create author rows on commit.
    // Without this, a received authored dance's raw authorIds reference
    // choreographer rows the receiver never creates -> FK 787 -> dance dropped.
    group('author attribution round-trip (#412)', () {
      test(
        'parse recovers author names from the payload choreographers',
        () async {
          final json = encodeArchive(
            _archive([
              _dance('d1', 'Give and Take', authorIds: ['c1']),
            ]),
          );
          final adapter = GenericJsonAdapter();
          final discovered = await adapter.discover(
            ImportRequest(payload: json),
          );
          final draft = await _importOne(adapter, discovered.single);

          // The draft credits by NAME (resolvable on any receiver), not the
          // sender's opaque id; dance.authorIds is left untouched.
          expect(draft.authorNames, ['Cary Ravitz']);
          expect(draft.dance.authorIds, ['c1']);
        },
      );

      test(
        'an author id with no matching choreographer yields no name',
        () async {
          // authorIds references 'ghost', absent from the archive's choreographers.
          final json = encodeArchive(
            _archive([
              _dance('d1', 'Orphaned', authorIds: ['ghost']),
            ]),
          );
          final adapter = GenericJsonAdapter();
          final discovered = await adapter.discover(
            ImportRequest(payload: json),
          );
          final draft = await _importOne(adapter, discovered.single);

          expect(draft.authorNames, isEmpty);
          expect(
            draft.dance.title,
            'Orphaned',
            reason: 'still parses, never fatal',
          );
        },
      );

      test('committing creates the choreographer row and points authorIds at it '
          'with no FK failure', () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final dances = DanceRepository(db, contraTaxonomy);
        final choreographers = ChoreographerRepository(db);
        final pipeline = ImportPipeline(dances, choreographers);

        final json = encodeArchive(
          _archive([
            _dance('d1', 'Give and Take', authorIds: ['c1']),
          ]),
        );
        final batch = await pipeline.plan(
          GenericJsonAdapter(),
          ImportRequest(payload: json),
        );
        final session = await pipeline.commit(
          batch,
          now: _now,
          newId: sequentialIds('new'),
        );

        expect(session.committedCount, 1);
        final imported = await dances.getById(session.insertedDanceIds.single);
        // authorIds now reference the RECEIVER's own row (not the sender's 'c1').
        expect(imported!.authorIds, isNot(contains('c1')));
        expect(imported.authorIds, hasLength(1));
        final author = await choreographers.getById(imported.authorIds.single);
        expect(author!.name, 'Cary Ravitz');
      });

      test(
        'reuses a choreographer the receiver already has, matched by name',
        () async {
          final db = openTestDatabase();
          addTearDown(db.close);
          final dances = DanceRepository(db, contraTaxonomy);
          final choreographers = ChoreographerRepository(db);
          final pipeline = ImportPipeline(dances, choreographers);
          // Receiver knows this author under a DIFFERENT id than the sender.
          // ignore: unused_result
          await choreographers.upsert(
            Choreographer(id: 'local-cary', name: 'Cary Ravitz'),
          );

          final json = encodeArchive(
            _archive([
              _dance('d1', 'Give and Take', authorIds: ['c1']),
            ]),
          );
          final batch = await pipeline.plan(
            GenericJsonAdapter(),
            ImportRequest(payload: json),
          );
          final session = await pipeline.commit(
            batch,
            now: _now,
            newId: sequentialIds('new'),
          );

          final imported = await dances.getById(
            session.insertedDanceIds.single,
          );
          expect(imported!.authorIds, [
            'local-cary',
          ], reason: 'matched by name');
          expect(
            await choreographers.listAll(),
            hasLength(1),
            reason: 'no duplicate',
          );
        },
      );
    });
  });
}
