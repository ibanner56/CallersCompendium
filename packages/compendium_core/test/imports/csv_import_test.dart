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

    test(r'tags and tunes honour \, and \\, and read an old export, or a '
        'hand-typed sheet with no backslash, as they always did', () async {
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping(CsvColumnTarget.tags),
        CsvColumnMapping(CsvColumnTarget.tunes),
      ];
      final batch = await plan(
        'Title,Tags,Tunes\r\n'
        '"Old","Jig, Favourite","Reel, Hornpipe; Strathspey"\r\n'
        r'"New","Hey\, Ho, Back\\slash","Say\, What, C:\temp"'
        '\r\n',
        mapping(',', cols: cols),
      );
      expect(batch.errors, isEmpty);
      final old = batch.records[0].draft.dance;
      expect(old.tagIds, [
        '${kCsvTagPlaceholderPrefix}Jig',
        '${kCsvTagPlaceholderPrefix}Favourite',
      ]);
      expect((old.tunesSource as DecodedTunes).tunes, [
        'Reel',
        'Hornpipe',
        'Strathspey',
      ]);
      final escaped = batch.records[1].draft.dance;
      expect(escaped.tagIds, [
        '${kCsvTagPlaceholderPrefix}Hey, Ho',
        '${kCsvTagPlaceholderPrefix}Back\\slash',
      ]);
      expect((escaped.tunesSource as DecodedTunes).tunes, [
        'Say, What',
        r'C:\temp',
      ]);
    });

    test(r'authors honour \, and \\ in the CSV, and an old export or a '
        'hand-typed cell reads as it always did (#2332)', () async {
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping(CsvColumnTarget.authors),
      ];
      Future<List<String>> authors(String cell) async {
        final batch = await plan(
          'Title,Authors\r\n"T","${cell.replaceAll('"', '""')}"\r\n',
          mapping(',', cols: cols),
        );
        expect(batch.errors, isEmpty);
        return batch.records.single.draft.authorNames;
      }

      expect(await authors(r'Smith\, John, Mary Example'), [
        'Smith, John',
        'Mary Example',
      ]);
      expect(await authors(r'Doe\, Jr., Bob'), ['Doe, Jr.', 'Bob']);
      expect(await authors(r'C:\temp\\x, Ann'), [r'C:\temp\x', 'Ann']);
      // No backslash: today's splitting, suffix protection included.
      expect(await authors('Ann Lee, Bob Ray and Cy Day'), [
        'Ann Lee',
        'Bob Ray',
        'Cy Day',
      ]);
      expect(await authors('Jane Doe, Jr., Bob'), ['Jane Doe, Jr.', 'Bob']);
      // The escape protects the comma only: a word delimiter still splits.
      expect(await authors(r'Smith\, John and Jo'), ['Smith, John', 'Jo']);
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

  group('review round 1 (#2329)', () {
    CsvImportMapping m(
      List<CsvColumnMapping> cols, {
      CsvValueVocabulary vocab = const CsvValueVocabulary(),
    }) => CsvImportMapping(
      separator: ',',
      hasHeader: true,
      columns: cols,
      vocabulary: vocab,
    );

    test('a Level column reads a configured level, and keeps an unknown one '
        'in the notes', () async {
      final batch = await plan(
        'Title,Level\r\nA,intermediate\r\nB,Wizard\r\n',
        m(
          const [
            CsvColumnMapping(CsvColumnTarget.title),
            CsvColumnMapping(CsvColumnTarget.level),
          ],
          vocab: const CsvValueVocabulary(levels: {'intermediate': 'lvl-int'}),
        ),
      );
      final a = batch.records[0].draft.dance;
      final b = batch.records[1].draft.dance;
      expect(a.difficultyLevelId, 'lvl-int');
      expect(b.difficultyLevelId, isNull);
      expect(b.callingNotes, 'Level: Wizard');
    });

    test('a trailing bracket that is not a beat or bar count stays in the '
        'figure', () async {
      final batch = await plan(
        'Title,Figures\r\nA,"circle left (3 places)"\r\n',
        m(const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping(CsvColumnTarget.figures),
        ]),
      );
      final figures =
          (batch.records.single.draft.dance.figuresSource as DecodedFigures)
              .figures;
      expect(figures, parseFigureLinesFanOut('circle left (3 places)'));
    });

    test('a second column for a single-valued field keeps its value in the '
        'notes; two columns for one phrase add up', () async {
      final batch = await plan(
        'Title,Hook,Hook,A1,A1\r\n'
        'A,First hook,Second hook,neighbors balance,neighbors swing\r\n',
        m(const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping(CsvColumnTarget.hook),
          CsvColumnMapping(CsvColumnTarget.hook),
          CsvColumnMapping.phrase('A1'),
          CsvColumnMapping.phrase('A1'),
        ]),
      );
      final dance = batch.records.single.draft.dance;
      expect(dance.hook, 'First hook');
      expect(dance.callingNotes, 'Hook: Second hook');
      expect((dance.figuresSource as DecodedFigures).figures, [
        ...parseFigureLinesFanOut('neighbors balance'),
        ...parseFigureLinesFanOut('neighbors swing'),
      ]);
    });
  });

  group('review round 2 (#2329)', () {
    CsvImportMapping m(
      List<CsvColumnMapping> cols, {
      CsvValueVocabulary vocab = const CsvValueVocabulary(),
      Map<String, CustomFieldDef> existingFields = const {},
    }) => CsvImportMapping(
      separator: ',',
      hasHeader: true,
      columns: cols,
      vocabulary: vocab,
      existingFields: existingFields,
    );

    test('the export\'s half-bar counts are read off', () async {
      final batch = await plan(
        'Title,Figures\r\nA,"neighbors balance (1½ bars) ¶\nneighbors swing (½ bar)"\r\n',
        m(const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping(CsvColumnTarget.figures),
        ]),
      );
      expect(
        (batch.records.single.draft.dance.figuresSource as DecodedFigures)
            .figures,
        [
          ...parseFigureLinesFanOut('neighbors balance', progression: true),
          ...parseFigureLinesFanOut('neighbors swing'),
        ],
      );
    });

    test('a first value that does not fit leaves the field to a later '
        'column', () async {
      final batch = await plan(
        'Title,Level,Level\r\nA,Wizard,beginner\r\n',
        m(const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping(CsvColumnTarget.level),
          CsvColumnMapping(CsvColumnTarget.level),
        ], vocab: const CsvValueVocabulary(levels: {'beginner': 'lvl-b'})),
      );
      final dance = batch.records.single.draft.dance;
      expect(dance.difficultyLevelId, 'lvl-b');
      expect(dance.callingNotes, 'Level: Wizard');
    });

    test('a new field named like an existing one of the same type is that '
        'field; two existing fields stay two', () async {
      final story = CustomFieldDef(
        id: 'f-story',
        key: 'story',
        label: 'Story',
        type: CustomFieldType.text,
      );
      final story2 = CustomFieldDef(
        id: 'f-story-2',
        key: 'story_2',
        label: 'story ',
        type: CustomFieldType.text,
      );
      final batch = await plan(
        'Title,S1,S2,S3,S4\r\nA,one,two,three,four\r\n',
        m(
          const [
            CsvColumnMapping(CsvColumnTarget.title),
            CsvColumnMapping.customField('f-story'),
            CsvColumnMapping.customField('f-story-2'),
            CsvColumnMapping.newCustomField('story', CustomFieldType.text),
            CsvColumnMapping.newCustomField('Story', CustomFieldType.number),
          ],
          existingFields: {'f-story': story, 'f-story-2': story2},
        ),
      );
      final dance = batch.records.single.draft.dance;
      expect(dance.customFields.map((v) => (v.fieldId, v.value)), [
        ('f-story', 'one'),
        ('f-story-2', 'two'),
      ]);
      // The number column is another field (another type), but `four` is
      // not a number.
      expect(dance.callingNotes, 'S3: three\n\nS4: four');
    });

    test('two new fields of one name and type are one field', () async {
      final batch = await plan(
        'Title,Story,Story\r\nA,one,two\r\n',
        m(const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping.newCustomField('Story', CustomFieldType.text),
          CsvColumnMapping.newCustomField('story', CustomFieldType.text),
        ]),
      );
      final dance = batch.records.single.draft.dance;
      expect(dance.customFields.map((v) => v.value), ['one']);
      expect(dance.callingNotes, 'Story: two');
    });

    test('a second Title column keeps its value in the notes', () async {
      final batch = await plan(
        'Title,Name\r\nA,Alias\r\n',
        m(const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping(CsvColumnTarget.title),
        ]),
      );
      final dance = batch.records.single.draft.dance;
      expect(dance.title, 'A');
      expect(dance.callingNotes, 'Name: Alias');
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

    test('two new columns of one name and type, filled on different rows, '
        'make one field', () async {
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping.newCustomField('Story', CustomFieldType.text),
        CsvColumnMapping.newCustomField('story', CustomFieldType.text),
      ];
      final batch = await plan(
        'Title,Story,Story\r\nA,one,\r\nB,,two\r\n',
        mapping(',', cols: cols),
      );
      await importer.commit(
        batch,
        mapping: mapping(',', cols: cols),
        now: now,
        newId: _ids(),
      );
      final defs = await fields.listAll();
      expect(defs, hasLength(1));
      final byTitle = {
        for (final d in await dances.listAll())
          d.title: d.customFields.map((v) => (v.fieldId, v.value)).toList(),
      };
      expect(byTitle, {
        'A': [(defs.single.id, 'one')],
        'B': [(defs.single.id, 'two')],
      });
    });

    test('an existing choice field grown by two new columns keeps every '
        'option', () async {
      final _ = await fields.upsert(
        CustomFieldDef(
          id: 'f-mood',
          key: 'mood',
          label: 'Mood',
          type: CustomFieldType.choice,
          choices: const ['x'],
        ),
      );
      final cols = [
        const CsvColumnMapping(CsvColumnTarget.title),
        const CsvColumnMapping.newCustomField('Mood', CustomFieldType.choice),
        const CsvColumnMapping.newCustomField('Mood', CustomFieldType.choice),
        const CsvColumnMapping.newCustomField('Mood', CustomFieldType.choice),
      ];
      final m = CsvImportMapping(
        separator: ',',
        hasHeader: true,
        columns: cols,
        existingFields: {for (final f in await fields.listAll()) f.id: f},
      );
      final batch = await plan(
        'Title,M1,M2,M3\r\nA,a,,\r\nB,,b,\r\nC,,,c\r\n',
        m,
      );
      final result = await importer.commit(
        batch,
        mapping: m,
        now: now,
        newId: _ids(),
      );
      expect(result.session.records.where((r) => r.error != null), isEmpty);
      final defs = await fields.listAll();
      expect(defs.single.choices, ['x', 'a', 'b', 'c']);
      expect((await dances.listAll()).map((d) => d.title).toSet(), {
        'A',
        'B',
        'C',
      });
    });

    test('three new choice columns of one name make one field with every '
        'option', () async {
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping.newCustomField('Mood', CustomFieldType.choice),
        CsvColumnMapping.newCustomField('Mood', CustomFieldType.choice),
        CsvColumnMapping.newCustomField('Mood', CustomFieldType.choice),
      ];
      final batch = await plan(
        'Title,M1,M2,M3\r\nA,a,,\r\nB,,b,\r\nC,,,c\r\n',
        mapping(',', cols: cols),
      );
      final result = await importer.commit(
        batch,
        mapping: mapping(',', cols: cols),
        now: now,
        newId: _ids(),
      );
      expect(result.session.records.where((r) => r.error != null), isEmpty);
      expect((await fields.listAll()).single.choices, ['a', 'b', 'c']);
    });

    test('a choice value in another Unicode form matches the option the '
        'field has', () async {
      const nfc = 'caf\u00e9';
      const nfd = 'cafe\u0301';
      final _ = await fields.upsert(
        CustomFieldDef(
          id: 'f-mood',
          key: 'mood',
          label: 'Mood',
          type: CustomFieldType.choice,
          choices: const [nfc],
        ),
      );
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping.newCustomField('Mood', CustomFieldType.choice),
      ];
      final m = CsvImportMapping(
        separator: ',',
        hasHeader: true,
        columns: cols,
        existingFields: {for (final f in await fields.listAll()) f.id: f},
      );
      final batch = await plan('Title,Mood\r\nA,$nfd\r\n', m);
      final result = await importer.commit(
        batch,
        mapping: m,
        now: now,
        newId: _ids(),
      );
      expect(result.session.records.where((r) => r.error != null), isEmpty);
      expect((await fields.listAll()).single.choices, [nfc]);
      expect((await dances.listAll()).single.customFields.single.value, nfc);
    });

    test('a new text field keeps a long value whole', () async {
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping.newCustomField('Story', CustomFieldType.text),
      ];
      final long = 'x' * 300;
      final batch = await plan(
        'Title,Story\r\nA,$long\r\n',
        mapping(',', cols: cols),
      );
      await importer.commit(
        batch,
        mapping: mapping(',', cols: cols),
        now: now,
        newId: _ids(),
      );
      final dance = (await dances.listAll()).single;
      expect(dance.customFields.single.value, long);
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
  group('numbers and choices a spreadsheet writes its own way', () {
    const numberCols = [
      CsvColumnMapping(CsvColumnTarget.title),
      CsvColumnMapping.newCustomField('Bars', CustomFieldType.number),
    ];

    Future<List<Object?>> barsOf(String separator, List<String> cells) async {
      final body = [
        for (var i = 0; i < cells.length; i++) 'D$i$separator${cells[i]}',
      ];
      final m = mapping(separator, cols: numberCols);
      final batch = await plan(
        'Title${separator}Bars\r\n${body.join('\r\n')}\r\n',
        m,
      );
      return [
        for (final r in batch.records)
          r.draft.dance.customFields.isEmpty
              ? r.draft.dance.callingNotes
              : r.draft.dance.customFields.single.value,
      ];
    }

    test('in a semicolon sheet a comma is the decimal mark and a dot or '
        'space groups thousands', () async {
      expect(
        await barsOf(';', [
          '3,5',
          '1.000',
          '1.234,5',
          '1 000',
          '1\u00a0000,25',
          '-2,5',
          '7',
          '1.5',
        ]),
        [3.5, 1000, 1234.5, 1000, 1000.25, -2.5, 7, 1.5],
      );
    });

    test(
      'in a semicolon sheet a leading zero is never a thousands group',
      () async {
        expect(await barsOf(';', ['0.500', '0.125', '00.500', '-0.500']), [
          0.5,
          0.125,
          0.5,
          -0.5,
        ]);
      },
    );

    test('in a semicolon sheet a value that is neither style stays in the '
        'notes', () async {
      final got = await barsOf(';', ['1,234.5', '1.2.3', '3,', ',5', 'many']);
      expect(got, [
        'Bars: 1,234.5',
        'Bars: 1.2.3',
        'Bars: 3,',
        'Bars: ,5',
        'Bars: many',
      ]);
    });

    test('in a comma sheet numbers read as before', () async {
      expect(await barsOf(',', ['"3,5"', '1.000', '1.5', '"1,000"']), [
        'Bars: 3,5',
        1.0,
        1.5,
        'Bars: 1,000',
      ]);
    });

    test(
      'an existing number field reads a semicolon sheet the same way',
      () async {
        final count = CustomFieldDef(
          id: 'f-count',
          key: 'count',
          label: 'Count',
          type: CustomFieldType.number,
        );
        final m = mapping(
          ';',
          cols: const [
            CsvColumnMapping(CsvColumnTarget.title),
            CsvColumnMapping.customField('f-count'),
          ],
          existing: {count.id: count},
        );
        final batch = await plan('Title;Count\r\nA;2,5\r\n', m);
        expect(batch.records.single.draft.dance.customFields.single.value, 2.5);
      },
    );

    const choiceCols = [
      CsvColumnMapping(CsvColumnTarget.title),
      CsvColumnMapping.newCustomField('Mood', CustomFieldType.choice),
    ];

    Future<List<Object?>> commitMoods(List<String> cells) async {
      final m = mapping(',', cols: choiceCols);
      final batch = await plan(
        'Title,Mood\r\n'
        '${[for (var i = 0; i < cells.length; i++) 'D$i,"${cells[i]}"'].join('\r\n')}\r\n',
        m,
      );
      final result = await importer.commit(
        batch,
        mapping: m,
        now: now,
        newId: _ids(),
      );
      expect(result.session.records.where((r) => r.error != null), isEmpty);
      final all = await dances.listAll();
      return [
        for (final t in [for (var i = 0; i < cells.length; i++) 'D$i'])
          all.firstWhere((d) => d.title == t).customFields.firstOrNull?.value,
      ];
    }

    test(
      'a cell of only invisible characters is no option and no value',
      () async {
        final values = await commitMoods(['a', '\u200b', '\u200b\u2060']);
        expect(values, ['a', null, null]);
        expect((await fields.listAll()).single.choices, ['a']);
      },
    );

    test('an invisible-only choice cell fills nothing and is not kept in the '
        'notes, so a later column fills the field', () async {
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping.newCustomField('Mood', CustomFieldType.choice),
        CsvColumnMapping.newCustomField('Mood', CustomFieldType.choice),
      ];
      final batch = await plan(
        'Title,A,B\r\nD,\u200b,calm\r\n',
        mapping(',', cols: cols),
      );
      final dance = batch.records.single.draft.dance;
      expect(dance.callingNotes, '');
      expect(dance.customFields.single.value, 'calm');
    });

    test('an invisible-only cell for an existing choice field is not kept in '
        'the notes', () async {
      final mood = CustomFieldDef(
        id: 'f-mood',
        key: 'mood',
        label: 'Mood',
        type: CustomFieldType.choice,
        choices: const ['calm'],
      );
      final m = mapping(
        ',',
        cols: const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping.customField('f-mood'),
        ],
        existing: {mood.id: mood},
      );
      final batch = await plan('Title,Mood\r\nA,\u200b\r\n', m);
      final draft = batch.records.single.draft;
      expect(draft.dance.callingNotes, '');
      expect(draft.dance.customFields, isEmpty);
      expect(
        draft.issues.where((i) => i.code == kCsvValueKeptInNotes),
        isEmpty,
      );
    });

    test('a column of only invisible characters makes no field', () async {
      final values = await commitMoods(['\u200b']);
      expect(values, [null]);
      expect(await fields.listAll(), isEmpty);
    });

    test(
      'an option is trimmed again after its invisible characters go',
      () async {
        final values = await commitMoods(['a \u200b', 'a']);
        expect(values, ['a', 'a']);
        expect((await fields.listAll()).single.choices, ['a']);
      },
    );

    test('an option NFC made longer is clamped to the choice length', () async {
      final cell = 'x${'\u0344' * 60}';
      expect(normalizeShareableText(cell).length, greaterThan(100));
      final values = await commitMoods([cell]);
      final choice = (await fields.listAll()).single.choices!.single;
      expect(choice.length, lessThanOrEqualTo(kMaxCustomFieldChoiceLength));
      expect(values.single, choice);
    });

    test('a decomposed cell matches the option an existing choice field '
        'has and is written as that option', () async {
      const nfc = 'caf\u00e9';
      const nfd = 'cafe\u0301';
      final mood = CustomFieldDef(
        id: 'f-mood',
        key: 'mood',
        label: 'Mood',
        type: CustomFieldType.choice,
        choices: const [nfc, 'Plain'],
      );
      final m = mapping(
        ',',
        cols: const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping.customField('f-mood'),
        ],
        existing: {mood.id: mood},
      );
      final batch = await plan('Title,Mood\r\nA,$nfd\r\nB, PLAIN \r\n', m);
      expect(
        [
          for (final r in batch.records)
            r.draft.dance.customFields.single.value,
          for (final r in batch.records) r.draft.dance.callingNotes,
        ],
        [nfc, 'Plain', '', ''],
      );
    });
  });

  // Pre-release audit findings E1-04, SEC-04, TESTS-07 and E1-12.
  group('round trip and hardening (pre-release audit)', () {
    CsvImportMapping m(
      List<CsvColumnMapping> cols, {
      CsvValueVocabulary vocab = const CsvValueVocabulary(),
    }) => CsvImportMapping(
      separator: ',',
      hasHeader: true,
      columns: cols,
      vocabulary: vocab,
    );

    List<Figure> figuresOf(ImportRecordPlan plan) =>
        (plan.draft.dance.figuresSource as DecodedFigures).figures;

    test(
      'a formation with a detail reads back as its shape and detail',
      () async {
        final batch = await plan(
          'Title,Form,Formation\r\n'
          'Hole in the Wall,ecd,"Duple minor, improper — first corners cross"\r\n'
          'Becket Reel,contra,Becket — slide left to start\r\n',
          m(
            const [
              CsvColumnMapping(CsvColumnTarget.title),
              CsvColumnMapping(CsvColumnTarget.form),
              CsvColumnMapping(CsvColumnTarget.formation),
            ],
            vocab: const CsvValueVocabulary(
              formations: {'becket': FormationShape.becketCw},
              improperFormations: {
                'duple minor, improper': FormationShape.dupleMinor,
              },
            ),
          ),
        );
        final [ecd, becket] = [for (final r in batch.records) r.draft.dance];
        expect(ecd.formation.shape, FormationShape.dupleMinor);
        expect(ecd.formation.improper, isTrue);
        expect(ecd.formation.detail, 'first corners cross');
        expect(ecd.callingNotes, isEmpty);
        expect(becket.formation.shape, FormationShape.becketCw);
        expect(becket.formation.detail, 'slide left to start');
        expect(becket.callingNotes, isEmpty);
      },
    );

    test('a row with no readable formation gets the first shape its form '
        'offers, whichever column comes first', () async {
      final batch = await plan(
        'Title,Formation,Form\r\n'
        'Hole in the Wall,,ecd\r\n'
        'Texas Star,,square\r\n'
        'Chorus Jig,,contra\r\n'
        'Odd Set,Hexagon,ecd\r\n',
        m(const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping(CsvColumnTarget.formation),
          CsvColumnMapping(CsvColumnTarget.form),
        ]),
      );
      final got = {
        for (final r in batch.records)
          r.draft.dance.title: r.draft.dance.formation.shape,
      };
      expect(got, {
        'Hole in the Wall': FormationShape.dupleMinor,
        'Texas Star': FormationShape.square,
        'Chorus Jig': FormationShape.dupleImproper,
        'Odd Set': FormationShape.dupleMinor,
      });
      for (final r in batch.records) {
        final d = r.draft.dance;
        expect(
          d.formation.shape,
          offeredFormationShapes(d.form).first,
          reason: d.title,
        );
      }
      expect(batch.records.last.draft.dance.callingNotes, 'Formation: Hexagon');
    });

    test("an indented line under a figure is that figure's note, in a "
        'figures cell and in a phrase column', () async {
      final batch = await plan(
        'Title,Figures,A1\r\n'
        '"Export","A1  neighbors balance and swing (16 beats)\n'
        '    end facing down\n'
        'A2  partners swing (16 beats) ¶",\r\n'
        '"Phrases",,"neighbors balance and swing (16 beats)\n'
        '  end facing down"\r\n',
        m(const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping(CsvColumnTarget.figures),
          CsvColumnMapping.phrase('A1'),
        ]),
      );
      final exported = figuresOf(batch.records[0]);
      expect([for (final f in exported) f.move], ['swing', 'swing']);
      expect(exported.first.note, 'end facing down');
      expect(exported.last.note, isNull);
      expect(exported.last.progression, isTrue);
      final phrase = figuresOf(batch.records[1]);
      expect([for (final f in phrase) f.move], ['swing']);
      expect(phrase.single.note, 'end facing down');
    });

    test('a figure indented under the first of its phrase is a figure, not '
        'a note', () async {
      // A card's layout: the phrase label only on a phrase's first figure.
      final batch = await plan(
        'Title,Figures\r\n'
        '"Card","A1  neighbors balance and swing\n'
        'A2  ladies chain\n'
        'B1  circle left 3/4\n'
        '    pass through\n'
        'B2  partners swing"\r\n'
        '"Counted","B1  circle left 3/4 (8 beats)\n'
        '    pass through (8 beats)"\r\n',
        m(const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping(CsvColumnTarget.figures),
        ]),
      );
      final card = figuresOf(batch.records[0]);
      expect(card, hasLength(5));
      expect([for (final f in card) f.note], everyElement(isNull));
      final counted = figuresOf(batch.records[1]);
      expect(counted, hasLength(2));
      expect([for (final f in counted) f.note], everyElement(isNull));
    });

    test('lines all indented alike are each a figure', () async {
      final batch = await plan(
        'Title,Figures\r\n'
        '"Typed","  neighbors balance and swing\n  partners swing"\r\n',
        m(const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping(CsvColumnTarget.figures),
        ]),
      );
      final figures = figuresOf(batch.records.single);
      expect([for (final f in figures) f.move], ['swing', 'swing']);
      expect([for (final f in figures) f.note], [null, null]);
    });

    test('a figure line longer than typed entry allows is kept as its text '
        'without being parsed', () async {
      // The parser reads this line as a swing at any length, so only a line
      // that never reaches it comes back as text.
      String line(int length) =>
          'partners${' ' * (length - 'partners'.length - 'swing'.length)}'
          'swing';
      final batch = await plan(
        'Title,Figures\r\n'
        'At the cap,${line(maxFreeTextEntryLength)}\r\n'
        'Past the cap,${line(maxFreeTextEntryLength + 1)}\r\n',
        m(const [
          CsvColumnMapping(CsvColumnTarget.title),
          CsvColumnMapping(CsvColumnTarget.figures),
        ]),
      );
      expect(figuresOf(batch.records[0]).single.move, 'swing');
      final kept = figuresOf(batch.records[1]).single;
      expect(kept.isCustom, isTrue);
      expect(kept.params['text'], line(maxFreeTextEntryLength + 1));
      expect(kept.customOrigin, CustomOrigin.importGap);
    });

    test(
      'Progression, Status and Mixer import the value in the cell',
      () async {
        final batch = await plan(
          'Title,Progression,Status,Mixer\r\n'
          'A,none,deprecated,yes\r\n'
          'B,double,broken,no\r\n'
          'C,Triple,draft,Ja\r\n'
          'D,quadruple,variation,Nej\r\n'
          'E,other,Aktiv,x\r\n'
          'F,Einfach,active,0\r\n',
          m(
            const [
              CsvColumnMapping(CsvColumnTarget.title),
              CsvColumnMapping(CsvColumnTarget.progression),
              CsvColumnMapping(CsvColumnTarget.status),
              CsvColumnMapping(CsvColumnTarget.mixer),
            ],
            vocab: const CsvValueVocabulary(
              progressions: {'einfach': Progression.single},
              statuses: {'aktiv': DanceStatus.active},
              yes: {'ja'},
              no: {'nej'},
            ),
          ),
        );
        expect(batch.errors, isEmpty);
        expect(
          [
            for (final r in batch.records)
              (
                r.draft.dance.progression,
                r.draft.dance.status,
                r.draft.dance.mixer,
              ),
          ],
          [
            (Progression.none, DanceStatus.deprecated, true),
            (Progression.double, DanceStatus.broken, false),
            (Progression.triple, DanceStatus.draft, true),
            (Progression.quadruple, DanceStatus.variation, false),
            (Progression.other, DanceStatus.active, true),
            (Progression.single, DanceStatus.active, false),
          ],
        );
        for (final r in batch.records) {
          expect(
            r.draft.dance.callingNotes,
            isEmpty,
            reason: r.draft.dance.title,
          );
        }
      },
    );

    test('a cell that really begins with an apostrophe before a formula '
        'character reads back as written', () {
      for (final value in [
        "'=quoted at start",
        "''=two apostrophes",
        "'''@three",
        "'-dash",
        "'tis",
        "'+1",
        '=SUM(A1:A9)',
        '-3.5',
        "'",
        '',
      ]) {
        expect(unguardCsvFormula(guardCsvFormula(value)), value, reason: value);
      }
    });

    test('a new choice field makes one option of values that differ only by '
        'case, spelled as first met', () async {
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping.newCustomField('Energy', CustomFieldType.choice),
      ];
      final batch = await plan(
        'Title,Energy\r\nA,High\r\nB,high\r\nC, HIGH \r\nD,Low\r\n',
        m(cols),
      );
      await importer.commit(batch, mapping: m(cols), now: now, newId: _ids());
      final field = (await fields.listAll()).single;
      expect(field.choices, ['High', 'Low']);
      expect(
        {
          for (final d in await dances.listAll())
            d.title: d.customFields.single.value,
        },
        {'A': 'High', 'B': 'High', 'C': 'High', 'D': 'Low'},
      );
    });

    test('a new choice column adds no option an existing field of that name '
        'has in another case', () async {
      await fields.upsert(
        CustomFieldDef(
          id: 'f-energy',
          key: 'energy',
          label: 'Energy',
          type: CustomFieldType.choice,
          choices: const ['High'],
        ),
      );
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping.newCustomField('Energy', CustomFieldType.choice),
      ];
      final batch = await plan('Title,Energy\r\nA,high\r\nB,Low\r\n', m(cols));
      await importer.commit(batch, mapping: m(cols), now: now, newId: _ids());
      expect((await fields.listAll()).single.choices, ['High', 'Low']);
      expect(
        {
          for (final d in await dances.listAll())
            d.title: d.customFields.single.value,
        },
        {'A': 'High', 'B': 'Low'},
      );
    });

    group('the columns the export writes and the import once ignored', () {
      const cols = [
        CsvColumnMapping(CsvColumnTarget.title),
        CsvColumnMapping(CsvColumnTarget.form),
        CsvColumnMapping(CsvColumnTarget.composed),
        CsvColumnMapping(CsvColumnTarget.interpreters),
        CsvColumnMapping(CsvColumnTarget.interpreted),
        CsvColumnMapping(CsvColumnTarget.mixedLevel),
        CsvColumnMapping(CsvColumnTarget.rating),
        CsvColumnMapping(CsvColumnTarget.barnesReference),
      ];
      const header =
          'Title,Form,Composed,Interpreted by,Interpreted in,Mixed level,'
          'Rating,Barnes reference\r\n';

      test('read the value in the cell', () async {
        final batch = await plan(
          '${header}Hole in the Wall,ecd,1698,"Ivan Example, Zoë Müller",'
          '1916-03-14,yes,4,BIII p. 92\r\n'
          'Chorus Jig,contra,1987-03,,,no,1,\r\n',
          m(cols),
        );
        expect(batch.errors, isEmpty);
        final [ecd, contra] = [for (final r in batch.records) r.draft];
        expect(ecd.dance.composedOn, PartialDate(1698));
        expect(ecd.interpreterNames, ['Ivan Example', 'Zoë Müller']);
        expect(ecd.dance.interpretedOn, PartialDate(1916, 3, 14));
        expect(ecd.dance.mixedLevel, isTrue);
        expect(ecd.dance.rating, 4);
        expect(ecd.dance.barnesReference, 'BIII p. 92');
        expect(ecd.dance.callingNotes, isEmpty);
        expect(contra.dance.composedOn, PartialDate(1987, 3));
        expect(contra.interpreterNames, isEmpty);
        expect(contra.dance.interpretedOn, isNull);
        expect(contra.dance.mixedLevel, isFalse);
        expect(contra.dance.rating, 1);
        expect(contra.dance.callingNotes, isEmpty);
      });

      test('keep a value that does not fit in the calling notes', () async {
        final batch = await plan(
          '${header}Odd,ecd,March 1987,,1916-02-30,sometimes,4.5,'
          '${'B' * (kMaxBarnesReferenceLength + 1)}\r\n'
          'Contra,contra,,,,,6,BIII p. 92\r\n',
          m(cols),
        );
        final [odd, contra] = [for (final r in batch.records) r.draft.dance];
        expect(
          (odd.composedOn, odd.interpretedOn, odd.mixedLevel, odd.rating),
          (null, null, false, null),
        );
        expect(odd.barnesReference, isEmpty);
        expect(odd.callingNotes.split('\n\n'), [
          'Composed: March 1987',
          'Interpreted in: 1916-02-30',
          'Mixed level: sometimes',
          'Rating: 4.5',
          'Barnes reference: ${'B' * (kMaxBarnesReferenceLength + 1)}',
        ]);
        // A contra has no Barnes reference to keep it in.
        expect(contra.rating, isNull);
        expect(contra.callingNotes.split('\n\n'), [
          'Rating: 6',
          'Barnes reference: BIII p. 92',
        ]);
      });

      test('a Barnes reference waits for a Type column after it', () async {
        final batch = await plan(
          'Title,Barnes reference,Form\r\nA,BIII p. 92,ecd\r\n',
          m(const [
            CsvColumnMapping(CsvColumnTarget.title),
            CsvColumnMapping(CsvColumnTarget.barnesReference),
            CsvColumnMapping(CsvColumnTarget.form),
          ]),
        );
        final dance = batch.records.single.draft.dance;
        expect(dance.barnesReference, 'BIII p. 92');
        expect(dance.callingNotes, isEmpty);
      });

      test(
        'interpreters are matched to your authors, or added, at commit',
        () async {
          final batch = await plan(
            '${header}Hole in the Wall,ecd,,"Ivan Example, Zoë Müller",,,,\r\n',
            m(cols),
          );
          await importer.commit(
            batch,
            mapping: m(cols),
            now: now,
            newId: _ids(),
          );
          final dance = (await dances.listAll()).single;
          final people = {
            for (final c in await choreographers.listAll()) c.id: c.name,
          };
          expect(
            [for (final id in dance.interpreterIds) people[id]],
            ['Ivan Example', 'Zoë Müller'],
          );
        },
      );
    });
  });
}
