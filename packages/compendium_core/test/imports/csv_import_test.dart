import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

String Function() _ids() {
  var n = 0;
  return () => 'id-${n++}';
}

/// A spreadsheet import (#2329): reading, mapping and committing.
void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ChoreographerRepository choreographers;
  late TagRepository tags;
  late CustomFieldDefRepository fields;
  late ImportPipeline pipeline;
  late CsvImporter importer;
  final now = DateTime.utc(2026, 11, 23);

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    tags = TagRepository(db);
    fields = CustomFieldDefRepository(db);
    pipeline = ImportPipeline(dances, choreographers);
    importer = CsvImporter(pipeline, tags, fields);
  });
  tearDown(() => db.close());

  const columns = [
    CsvColumnMapping(CsvColumnTarget.title),
    CsvColumnMapping(CsvColumnTarget.authors),
    CsvColumnMapping(CsvColumnTarget.tags),
    CsvColumnMapping(CsvColumnTarget.figures),
    CsvColumnMapping(CsvColumnTarget.callingNotes),
  ];

  CsvImportMapping mapping(
    String separator, {
    List<CsvColumnMapping> cols = columns,
    Map<String, CustomFieldDef> existing = const {},
  }) => CsvImportMapping(
    separator: separator,
    hasHeader: true,
    columns: cols,
    existingFields: existing,
  );

  Future<ImportBatchResult> plan(String text, CsvImportMapping m) =>
      pipeline.plan(
        CsvAdapter(),
        ImportRequest(payload: text, options: {CsvAdapter.mappingOption: m}),
      );

  String sheet(String s) =>
      '\uFEFF'
      'Title${s}Authors${s}Tags${s}Figures${s}Notes\r\n'
      '"Rory O\'More"$s"Pat Shaw & Mary Example"$s"Jig, Favourite"$s'
      '"neighbors balance and swing\npartners swing"$s"Say ""slide"" early"\r\n'
      'Petronella$s$s$s"A1 petronella; partners swing"$s\r\n';

  group('reading', () {
    test('comma, semicolon and tab sheets plan the same dances', () async {
      final planned = <List<Object?>>[];
      for (final s in [',', ';', '\t']) {
        final batch = await plan(sheet(s), mapping(s));
        expect(batch.errors, isEmpty, reason: 'separator ${s.codeUnits}');
        planned.add([
          for (final r in batch.records)
            [
              r.draft.dance.title,
              r.draft.authorNames,
              r.draft.dance.tagIds,
              r.draft.dance.callingNotes,
              (r.draft.dance.figuresSource as DecodedFigures).figures,
            ],
        ]);
      }
      expect(planned[1], planned[0]);
      expect(planned[2], planned[0]);
      final first = planned[0].first as List<Object?>;
      expect(first[0], "Rory O'More");
      expect(first[1], ['Pat Shaw', 'Mary Example']);
      expect(first[2], [
        '${kCsvTagPlaceholderPrefix}Jig',
        '${kCsvTagPlaceholderPrefix}Favourite',
      ]);
      expect(first[3], 'Say "slide" early');
      expect(first[4], hasLength(2));
    });

    test('a figures cell, a ;-separated cell and per-phrase columns give '
        'the figures the fan-out gives for the same lines', () async {
      const lines = ['neighbors balance and swing', 'partners swing'];
      final expected = [for (final l in lines) ...parseFigureLinesFanOut(l)];
      List<Figure> figuresOf(StructuredDraft d) =>
          (d.dance.figuresSource as DecodedFigures).figures;

      final perLine = await plan(
        'Title,Figures\r\nA,"${lines.join('\n')}"\r\n',
        mapping(
          ',',
          cols: const [
            CsvColumnMapping(CsvColumnTarget.title),
            CsvColumnMapping(CsvColumnTarget.figures),
          ],
        ),
      );
      final semicolons = await plan(
        'Title,Figures\r\nA,"${lines.join('; ')}"\r\n',
        mapping(
          ',',
          cols: const [
            CsvColumnMapping(CsvColumnTarget.title),
            CsvColumnMapping(CsvColumnTarget.figures),
          ],
        ),
      );
      final phrases = await plan(
        'Title,B1,A1\r\nA,${lines[1]},${lines[0]}\r\n',
        mapping(
          ',',
          cols: const [
            CsvColumnMapping(CsvColumnTarget.title),
            CsvColumnMapping.phrase('B1'),
            CsvColumnMapping.phrase('A1'),
          ],
        ),
      );
      for (final batch in [perLine, semicolons, phrases]) {
        expect(figuresOf(batch.records.single.draft), expected);
      }
    });

    test(
      'an unreadable line becomes an unrecognized figure with its text',
      () async {
        final batch = await plan(
          'Title,Figures\r\nA,zorbulate the gizmo\r\n',
          mapping(
            ',',
            cols: const [
              CsvColumnMapping(CsvColumnTarget.title),
              CsvColumnMapping(CsvColumnTarget.figures),
            ],
          ),
        );
        final figure =
            (batch.records.single.draft.dance.figuresSource as DecodedFigures)
                .figures
                .single;
        expect(figure.isCustom, isTrue);
        expect(figure.params['text'], 'zorbulate the gizmo');
      },
    );

    test('a value that does not fit its field is kept in the calling notes '
        'with a note, never dropped', () async {
      final count = CustomFieldDef(
        id: 'f-count',
        key: 'count',
        label: 'Count',
        type: CustomFieldType.number,
      );
      final batch = await plan(
        'Title,Formation,Count\r\nA,Hexagonal,many\r\n',
        mapping(
          ',',
          cols: const [
            CsvColumnMapping(CsvColumnTarget.title),
            CsvColumnMapping(CsvColumnTarget.formation),
            CsvColumnMapping.customField('f-count'),
          ],
          existing: {count.id: count},
        ),
      );
      final draft = batch.records.single.draft;
      expect(draft.dance.callingNotes, 'Formation: Hexagonal\n\nCount: many');
      expect(
        draft.issues.where((i) => i.code == kCsvValueKeptInNotes),
        hasLength(2),
      );
      expect(draft.dance.customFields, isEmpty);
    });

    test('a row without a title is an error and plans nothing', () async {
      final batch = await plan(
        'Title,Notes\r\n,just notes\r\nB,x\r\n',
        mapping(
          ',',
          cols: const [
            CsvColumnMapping(CsvColumnTarget.title),
            CsvColumnMapping(CsvColumnTarget.callingNotes),
          ],
        ),
      );
      expect(batch.records.map((r) => r.draft.dance.title), ['B']);
      expect(batch.errors, hasLength(1));
    });
  });

  group('reading this app\'s own export back', () {
    test(
      'a localized beat count, the progression mark, the formula guard, '
      'an improper formation and a choice in another case read back',
      () async {
        final season = CustomFieldDef(
          id: 'f-season',
          key: 'season',
          label: 'Season',
          type: CustomFieldType.choice,
          choices: ['Winter', 'Summer'],
        );
        final m = CsvImportMapping(
          separator: ',',
          hasHeader: true,
          columns: const [
            CsvColumnMapping(CsvColumnTarget.title),
            CsvColumnMapping(CsvColumnTarget.form),
            CsvColumnMapping(CsvColumnTarget.formation),
            CsvColumnMapping(CsvColumnTarget.figures),
            CsvColumnMapping.customField('f-season'),
          ],
          vocabulary: const CsvValueVocabulary(
            improperFormations: {'longways improper': FormationShape.longways},
            beatWords: {'schläge'},
          ),
          existingFields: {season.id: season},
        );
        final batch = await plan(
          'Titel,Typ,Formation,Figuren,Season\r\n'
          "'=Odd title,ecd,Longways improper,"
          '"A1  partners swing (16 Schläge) ¶",winter\r\n',
          m,
        );
        final draft = batch.records.single.draft;
        expect(draft.dance.title, '=Odd title');
        expect(draft.dance.formation.shape, FormationShape.longways);
        expect(draft.dance.formation.improper, isTrue);
        final figure =
            (draft.dance.figuresSource as DecodedFigures).figures.single;
        expect(figure.beats, 16);
        expect(figure.progression, isTrue);
        expect(draft.dance.customFields.single.value, 'Winter');
        expect(draft.dance.callingNotes, isEmpty);
      },
    );

    test('an apostrophe before an ordinary word is kept', () {
      expect(unguardCsvFormula("'tis"), "'tis");
      expect(unguardCsvFormula("'=1+1"), '=1+1');
    });
  });

  group('committing', () {
    test('records no provenance, and adds no provenance source', () async {
      final batch = await plan(sheet(','), mapping(','));
      final session = await importer.commit(
        batch,
        mapping: mapping(','),
        now: now,
        newId: _ids(),
      );
      expect(session.session.insertedDanceIds, hasLength(2));
      for (final id in session.session.insertedDanceIds) {
        expect((await dances.getById(id))!.provenance, isNull);
      }
      expect(ProvenanceSource.values.map((s) => s.name), [
        'callersbox',
        'contradb',
        'callersCompanion',
        'manual',
        'json',
        'publishedCollection',
      ], reason: 'no ProvenanceSource value is added for a spreadsheet');
    });

    test('resolves tags by name, creating the missing ones once, and undo '
        'removes what it created', () async {
      final _ = await tags.upsert(Tag(id: 'existing-jig', name: 'jig'));
      final batch = await plan(sheet(','), mapping(','));
      final session = await importer.commit(
        batch,
        mapping: mapping(','),
        now: now,
        newId: _ids(),
      );
      final rory = (await dances.listAll()).firstWhere(
        (d) => d.title == "Rory O'More",
      );
      expect(rory.tagIds, contains('existing-jig'));
      expect(session.createdTagIds, hasLength(1));
      expect((await tags.listAll()).map((t) => t.name).toSet(), {
        'jig',
        'Favourite',
      });

      await importer.undo(session);
      expect(await dances.listAll(), isEmpty);
      expect((await tags.listAll()).map((t) => t.id), ['existing-jig']);
    });

    test('a tag waiting in Recently deleted is reused, and Undo leaves it '
        'alone', () async {
      final _ = await tags.upsert(Tag(id: 't-old', name: 'Jig'));
      await dances.create(
        Dance(
          id: 'keeps-jig',
          title: 'Keeps the tag referenced',
          tagIds: const ['t-old'],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await tags.delete('t-old', at: now);
      expect((await tags.listAll()).map((t) => t.id), isNot(contains('t-old')));

      final batch = await plan(sheet(','), mapping(','));
      final session = await importer.commit(
        batch,
        mapping: mapping(','),
        now: now,
        newId: _ids(),
      );
      expect(session.createdTagIds, isNot(contains('t-old')));
      await importer.undo(session);
      final row = await (db.select(
        db.tags,
      )..where((t) => t.id.equals('t-old'))).getSingleOrNull();
      expect(
        row,
        isNotNull,
        reason: 'Undo must not erase a tag it did not make',
      );
    });

    test('a later commit reuses the field an earlier one made from the same '
        'column', () async {
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping.newCustomField('Season', CustomFieldType.choice),
      ];
      final batch = await plan(
        'Title,Season\r\nA,Winter\r\nB,Summer\r\n',
        mapping(',', cols: cols),
      );
      // Row A alone first (as Import and edit does), then the rest.
      await importer.commit(
        ImportBatchResult(records: [batch.records[0]]),
        mapping: mapping(',', cols: cols),
        now: now,
        newId: _ids(),
      );
      await importer.commit(
        ImportBatchResult(records: [batch.records[1]]),
        mapping: mapping(',', cols: cols),
        now: now,
        newId: () => 'second-${DateTime.now().microsecondsSinceEpoch}',
      );
      final defs = await fields.listAll();
      expect(defs, hasLength(1));
      expect(defs.single.choices!.toSet(), {'Winter', 'Summer'});
    });

    test('a new number or choice field is created once and holds typed '
        'values', () async {
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping.newCustomField('Bars', CustomFieldType.number),
        CsvColumnMapping.newCustomField('Season', CustomFieldType.choice),
      ];
      final batch = await plan(
        'Title,Bars,Season\r\nA,32,Winter\r\nB,48,Summer\r\nC,64,Winter\r\n',
        mapping(',', cols: cols),
      );
      final session = await importer.commit(
        batch,
        mapping: mapping(',', cols: cols),
        now: now,
        newId: _ids(),
      );
      final defs = await fields.listAll();
      expect(defs, hasLength(2));
      final bars = defs.firstWhere((d) => d.label == 'Bars');
      final season = defs.firstWhere((d) => d.label == 'Season');
      expect(bars.type, CustomFieldType.number);
      expect(season.choices!.toSet(), {'Winter', 'Summer'});
      final a = (await dances.listAll()).firstWhere((d) => d.title == 'A');
      expect(
        {for (final v in a.customFields) v.fieldId: v.value},
        {bars.id: 32, season.id: 'Winter'},
      );
      await importer.undo(session);
      expect(await fields.listAll(), isEmpty);
    });

    test('a row matching a dance you have by title and author is a possible '
        'match, not new', () async {
      final first = await plan(sheet(','), mapping(','));
      await importer.commit(
        first,
        mapping: mapping(','),
        now: now,
        newId: _ids(),
      );
      final again = await plan(sheet(','), mapping(','));
      final rory = again.records.firstWhere(
        (r) => r.draft.dance.title == "Rory O'More",
      );
      expect(rory.verdict.kind, DedupeKind.ambiguous);
    });
  });
}
