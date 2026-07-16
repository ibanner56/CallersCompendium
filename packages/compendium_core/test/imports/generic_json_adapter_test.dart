import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// Fixtures + tests for [GenericJsonAdapter]: our own canonical
/// [CompendiumArchive] JSON as a per-dance import source.

final _now = DateTime.utc(2026, 7, 15);

Dance _dance(
  String id,
  String title, {
  List<String> authorIds = const [],
  List<Figure> figures = const [],
  List<SourceCitation> sourceCitations = const [],
  List<CustomFieldValue> customFields = const [],
  Provenance? provenance,
}) => Dance(
  id: id,
  title: title,
  authorIds: authorIds,
  figures: figures,
  sourceCitations: sourceCitations,
  customFields: customFields,
  provenance: provenance,
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
      expect(d1.provenance, isNull, reason: 'pipeline attaches provenance');

      final d2 = byId['d2']!.dance;
      expect(d2.figures.single.isCustom, isTrue);
      expect(byId['d2']!.quality.isFullyCustom, isTrue);
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
  });
}
