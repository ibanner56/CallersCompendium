import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../storage/test_database.dart';
import '../test_package_root.dart';

/// A text or Markdown file import (#2330): splitting, reading, and planning
/// through the spreadsheet import.
void main() {
  late String fixtures;

  setUpAll(() async {
    fixtures = p.join(
      await packageRootPath(),
      'test',
      'imports',
      'support',
      'text_documents',
    );
  });

  String fixture(String name) =>
      File(p.join(fixtures, name)).readAsStringSync();

  group('splitting into dances', () {
    test(
      'a Markdown file splits at ## headings and leaves out its # title',
      () {
        final dances = readTextDocument(fixture('three_dances.md'));
        expect(
          [for (final d in dances) d.title],
          ["Rory's Reel", 'The Second Dance', 'Third, Title Only'],
        );
      },
    );

    test('a plain-text file splits at a title line after a blank line', () {
      final dances = readTextDocument(fixture('three_dances.txt'));
      expect(
        [for (final d in dances) d.title],
        ["Rory's Reel", 'The Second Dance', 'Third, Title Only'],
      );
      // A blank line before a labelled figure line does not start a dance.
      expect(dances[1].figureLines, [
        'A1 (16) Neighbor swing',
        'A2 (16) Partner swing',
      ]);
    });

    test('both files read the same details and figures', () {
      final md = readTextDocument(fixture('three_dances.md'));
      final txt = readTextDocument(fixture('three_dances.txt'));
      for (var i = 0; i < 3; i++) {
        expect(md[i].labels, txt[i].labels, reason: md[i].title);
        expect(md[i].figureLines, txt[i].figureLines, reason: md[i].title);
      }
      expect(md.first.labels, const [
        ('Authors', 'Pat Example'),
        ('Formation', 'Becket'),
        ('Music', 'Any reel'),
        ('Composed', '2019'),
      ]);
      // List markers are removed; phrase labels and counts are kept.
      expect(md.first.figureLines.first, 'A1 (8) Neighbor balance & swing');
      expect(md.first.figureLines, hasLength(6));
      // A paragraph after the list is a note, as written.
      expect(md.first.notes, ['Watch the **chain** at the top.']);
    });

    test('a # heading with figures under it is a dance', () {
      final dances = readTextDocument('# Solo\n\n(8) Swing\n');
      expect(dances.single.title, 'Solo');
      expect(dances.single.figureLines, ['(8) Swing']);
    });

    test('a lone # title above dances split by blank lines is left out', () {
      final dances = readTextDocument(
        '# My contra dances\n\nChorus Jig\nFormation: Proper\n'
        'A1 (8) balance\n\nPetronella\nA1 (8) balance\n',
      );
      expect([for (final d in dances) d.title], ['Chorus Jig', 'Petronella']);
      expect(dances.first.figureLines, ['A1 (8) balance']);
    });

    test('a # title with a by line, above ## dances, is left out', () {
      final dances = readTextDocument(
        '# My dances\nby Jane Smith\n\n## Dance A\n(8) Swing\n',
      );
      expect([for (final d in dances) d.title], ['Dance A']);
    });

    test('in a file of # dances, each is a dance, figures or not', () {
      final dances = readTextDocument('# One\n(8) Swing\n# Two\n');
      expect([for (final d in dances) d.title], ['One', 'Two']);
    });

    test('a title starting with a number, after a blank line, is a dance', () {
      final dances = readTextDocument(
        'Chorus Jig\nA1 (8) balance\n\n12 Days of Christmas\nA1 (16) swing\n',
      );
      expect(
        [for (final d in dances) d.title],
        ['Chorus Jig', '12 Days of Christmas'],
      );
    });

    test('"by" in a note is not an author', () {
      final dance = readTextDocument(
        '## Dance\nby Pat\n(8) Swing\n\nBy the end everyone is home.\n',
      ).single;
      expect(dance.labels, const [('Authors', 'Pat')]);
      expect(dance.notes, ['By the end everyone is home.']);
    });

    test('a line with a colon straight after a figure is a figure', () {
      final dance = readTextDocument(
        'Dance\n(8) Swing\nCircle left: 3 places\n',
      ).single;
      expect(dance.labels, isEmpty);
      expect(dance.figureLines, ['(8) Swing', 'Circle left: 3 places']);
    });

    test('emphasised and full-width labels are read; a long one is not', () {
      final dance = readTextDocument(
        'Dance\n**Formation:** Becket\n__Music__: Any reel\n'
        '形式：ベケット\n'
        'これはとても長い文章でありラベルではないので注記として残されるべきです：はい\n',
      ).single;
      expect(dance.labels, const [
        ('Formation', 'Becket'),
        ('Music', 'Any reel'),
        ('形式', 'ベケット'),
      ]);
      expect(dance.notes, hasLength(1));
    });

    test('a # inside a heading is kept; a closing sequence is not', () {
      final dances = readTextDocument('## Reel in F#\n\n## Jig ##\n');
      expect([for (final d in dances) d.title], ['Reel in F#', 'Jig']);
    });

    test('Unicode line separators split lines', () {
      final dance = readTextDocument(
        'Dance A\u2028A1 swing\u0085(8) Long lines\u2029(8) Swing',
      ).single;
      expect(dance.title, 'Dance A');
      expect(dance.figureLines, ['A1 swing', '(8) Long lines', '(8) Swing']);
    });

    test('# dances with ## sections under each read as the # dances', () {
      final dances = readTextDocument(
        "# Rory's Reel\nFormation: Becket\n\n## Figures\n- A1 (8) swing\n"
        '\n## Notes\nWatch it.\n\n# Petronella\n## Figures\n- A1 (8) balance\n',
      );
      expect([for (final d in dances) d.title], ["Rory's Reel", 'Petronella']);
      expect(dances.first.labels, const [('Formation', 'Becket')]);
      expect(dances.first.figureLines, ['A1 (8) swing']);
      expect(dances.first.notes, ['Watch it.']);
      expect(dances.last.figureLines, ['A1 (8) balance']);
    });

    test('one # dance with details and ## parts is one dance', () {
      final dance = readTextDocument(
        "# Rory's Reel\nFormation: Becket\n\n## Figures\n- A1 (8) swing\n"
        '\n## Notes\nWatch it.\n',
      ).single;
      expect(dance.title, "Rory's Reel");
      expect(dance.labels, const [('Formation', 'Becket')]);
      expect(dance.figureLines, ['A1 (8) swing']);
      expect(dance.notes, ['Watch it.']);
    });

    test('a # file title with a detail, above ## dances that each have '
        'figures, is left out', () {
      final dances = readTextDocument(
        '# My dances\nAuthor: Jane Smith\n\n## Chorus Jig\n(8) Swing\n\n'
        '## Petronella\nFormation: Improper\n(8) Balance\n',
      );
      expect([for (final d in dances) d.title], ['Chorus Jig', 'Petronella']);
      expect(dances.first.figureLines, ['(8) Swing']);
      expect(dances.last.labels, const [('Formation', 'Improper')]);
      expect(dances.last.figureLines, ['(8) Balance']);
    });

    test('one # dance with a bulleted ## notes part is still one dance', () {
      final dance = readTextDocument(
        "# Rory's Reel\nFormation: Becket\n\n## Figures\n- A1 (8) swing\n"
        '\n## Notes\n- Watch the swing.\n',
      ).single;
      expect(dance.title, "Rory's Reel");
      expect(dance.labels, const [('Formation', 'Becket')]);
      // A list-marked line is a figure line wherever it sits; review shows
      // the note as an unrecognized figure, so nothing is lost.
      expect(dance.figureLines, ['A1 (8) swing', 'Watch the swing.']);
    });

    test('# sections of a file with ## dances are left out', () {
      final dances = readTextDocument(
        '# Contras\n\n## Chorus Jig\n(8) Swing\n\n# Squares\n\n'
        '## Grand Square\n(16) Grand square\n',
      );
      expect([for (final d in dances) d.title], ['Chorus Jig', 'Grand Square']);
    });

    test('a lone # dance with details is kept above blank-split dances', () {
      final dances = readTextDocument(
        '# Solo\nFormation: Proper\n\nOther\n(8) Swing\n',
      );
      expect([for (final d in dances) d.title], ['Solo', 'Other']);
    });

    test('a lone # heading with figures is a dance beside another', () {
      final dances = readTextDocument(
        '# Solo\n(8) Swing\n\nOther\n(8) Swing\n',
      );
      expect([for (final d in dances) d.title], ['Solo', 'Other']);
    });

    test("after a dance's figures, a title with a colon starts a dance", () {
      final dances = readTextDocument(
        'Chorus Jig\nA1 (8) balance\n\nPetronella: Revisited\nA1 (8) swing\n',
      );
      expect(
        [for (final d in dances) d.title],
        ['Chorus Jig', 'Petronella: Revisited'],
      );
      expect(dances.first.labels, isEmpty);
    });

    test('more emphasis forms and a time are read right', () {
      final dance = readTextDocument(
        'Dance\n***Formation:*** Becket\n**Music** : Any reel\n10:30 start\n',
      ).single;
      expect(dance.labels, const [
        ('Formation', 'Becket'),
        ('Music', 'Any reel'),
      ]);
      expect(dance.notes, ['10:30 start']);
    });

    test('a long heading line with spaces before its end is read', () {
      final title = 'a${' ' * 60000}x';
      final dance = readTextDocument('## $title\n(8) Swing').single;
      expect(dance.title, title);
    });

    test('an empty heading is not a dance', () {
      final dances = readTextDocument('## ##\n\n## Real\n(8) Swing\n');
      expect([for (final d in dances) d.title], ['Real']);
    });

    test('a web address is not a label', () {
      final dance = readTextDocument('Dance\nSee https://example.org\n').single;
      expect(dance.labels, isEmpty);
      expect(dance.notes, ['See https://example.org']);
    });
  });

  group('caps', () {
    test('too many dances is refused', () {
      final atCap = List.generate(
        kMaxTextDocumentDances,
        (i) => '## D$i',
      ).join('\n');
      expect(readTextDocument(atCap), hasLength(kMaxTextDocumentDances));
      expect(
        () => readTextDocument('$atCap\n## One more'),
        throwsA(
          isA<TextDocumentReadException>().having(
            (e) => e.reason,
            'reason',
            TextDocumentReadFailure.tooManyDances,
          ),
        ),
      );
    });

    test('a line over the cap is refused', () {
      final atCap = 'x' * kMaxTextDocumentLineChars;
      expect(readTextDocument('T\n$atCap'), hasLength(1));
      expect(
        () => readTextDocument('T\n${atCap}x'),
        throwsA(
          isA<TextDocumentReadException>().having(
            (e) => e.reason,
            'reason',
            TextDocumentReadFailure.lineTooLong,
          ),
        ),
      );
    });

    test('a file at the dance cap is a spreadsheet the reader accepts', () {
      final atCap = List.generate(
        kMaxTextDocumentDances,
        (i) => '## D$i',
      ).join('\n');
      expect(readCsv(textDocumentToCsv(readTextDocument(atCap))), isNotEmpty);
    });

    test('a dance before the first heading counts toward the cap', () {
      final text =
          'Pre\nFormation: X\n${List.generate(kMaxTextDocumentDances, (i) => '## D$i').join('\n')}';
      expect(
        () => readTextDocument(text),
        throwsA(
          isA<TextDocumentReadException>().having(
            (e) => e.reason,
            'reason',
            TextDocumentReadFailure.tooManyDances,
          ),
        ),
      );
    });

    test('a # title left out does not count toward the cap', () {
      final text =
          '# Title\n${List.generate(kMaxTextDocumentDances, (i) => '## D$i').join('\n')}';
      expect(readTextDocument(text), hasLength(kMaxTextDocumentDances));
    });

    test('a cell the formula guard lengthens past the cap is refused', () {
      final atCap = '-${'x' * (kMaxTextDocumentLineChars - 1)}';
      expect(
        () => textDocumentToCsv([
          TextDocumentDance(
            title: 'T',
            labels: const [],
            notes: [atCap],
            figureLines: const [],
          ),
        ]),
        throwsA(
          isA<TextDocumentReadException>().having(
            (e) => e.reason,
            'reason',
            TextDocumentReadFailure.danceTooLong,
          ),
        ),
      );
    });

    test('a dance whose figures come to more than a cell holds is refused', () {
      final line = '(8) ${'x' * 1000}';
      final lines = List.filled(
        kMaxTextDocumentLineChars ~/ line.length + 1,
        line,
      );
      final dances = readTextDocument('T\n${lines.join('\n')}');
      expect(
        () => textDocumentToCsv(dances),
        throwsA(
          isA<TextDocumentReadException>().having(
            (e) => e.reason,
            'reason',
            TextDocumentReadFailure.danceTooLong,
          ),
        ),
      );
    });

    test('too many different labels is refused', () {
      String doc(int n) =>
          'T\n${List.generate(n, (i) => 'Label$i: v').join('\n')}';
      expect(
        textDocumentToCsv(readTextDocument(doc(kMaxTextDocumentLabels))),
        isNotEmpty,
      );
      expect(
        () => textDocumentToCsv(
          readTextDocument(doc(kMaxTextDocumentLabels + 1)),
        ),
        throwsA(
          isA<TextDocumentReadException>().having(
            (e) => e.reason,
            'reason',
            TextDocumentReadFailure.tooManyLabels,
          ),
        ),
      );
    });

    test('bytes that are not UTF-8 are refused', () {
      expect(
        () => decodeTextDocumentBytes([0x63, 0x61, 0x66, 0xE9]),
        throwsA(
          isA<TextDocumentReadException>().having(
            (e) => e.reason,
            'reason',
            TextDocumentReadFailure.notUtf8,
          ),
        ),
      );
    });
  });

  group('planning through the spreadsheet import', () {
    late CompendiumDatabase db;
    late DanceRepository dances;
    late ImportPipeline pipeline;
    late CsvImporter importer;
    String Function() ids() {
      var n = 0;
      return () => 'id-${n++}';
    }

    setUp(() {
      db = openTestDatabase();
      dances = DanceRepository(db, contraTaxonomy);
      pipeline = ImportPipeline(dances, ChoreographerRepository(db));
      importer = CsvImporter(
        pipeline,
        TagRepository(db),
        CustomFieldDefRepository(db),
      );
    });
    tearDown(() => db.close());

    /// The file as a spreadsheet, its columns mapped as the map-columns step
    /// starts them, with `Formation` and `Author` matched by name.
    (String, CsvImportMapping) mapped(String text) {
      final csv = textDocumentToCsv(readTextDocument(text));
      final header = readCsv(csv).first;
      final auto = [
        for (final name in header)
          switch (name) {
            'Formation' => const CsvColumnMapping(CsvColumnTarget.formation),
            'Authors' => const CsvColumnMapping(CsvColumnTarget.authors),
            _ => CsvColumnMapping.ignore,
          },
      ];
      return (
        csv,
        CsvImportMapping(
          separator: ',',
          hasHeader: true,
          columns: textDocumentDefaultColumns(header, auto),
          vocabulary: const CsvValueVocabulary(
            formations: {
              'becket': FormationShape.becketCw,
              'improper': FormationShape.dupleImproper,
            },
          ),
        ),
      );
    }

    Future<ImportBatchResult> plan(String text) {
      final (csv, mapping) = mapped(text);
      return pipeline.plan(
        CsvAdapter(),
        ImportRequest(
          payload: csv,
          options: {CsvAdapter.mappingOption: mapping},
        ),
      );
    }

    test('the Markdown fixture plans three dances', () async {
      final batch = await plan(fixture('three_dances.md'));
      expect(batch.errors, isEmpty);
      expect(batch.records, hasLength(3));
    });

    test('the plain-text fixture plans the same dances', () async {
      final md = await plan(fixture('three_dances.md'));
      final txt = await plan(fixture('three_dances.txt'));
      List<Object?> shape(ImportBatchResult b) => [
        for (final r in b.records)
          [
            r.draft.dance.title,
            r.draft.authorNames,
            r.draft.dance.formation,
            (r.draft.dance.figuresSource as DecodedFigures).figures,
          ],
      ];
      expect(shape(txt), shape(md));
    });

    test('a mapped Formation sets the formation; an unmapped label is kept '
        'in calling notes with its label', () async {
      final batch = await plan(fixture('three_dances.md'));
      final rory = batch.records.first.draft;
      expect(rory.dance.formation.shape, FormationShape.becketCw);
      expect(rory.authorNames, ['Pat Example']);
      expect(rory.dance.callingNotes, contains('Music: Any reel'));
      expect(rory.dance.callingNotes, contains('Composed: 2019'));
      expect(
        rory.dance.callingNotes,
        contains('Watch the **chain** at the top.'),
      );
    });

    test(
      'labelled and list-marked figure lines parse as the bare line',
      () async {
        List<Figure> figuresOf(ImportBatchResult b) =>
            (b.records.single.draft.dance.figuresSource as DecodedFigures)
                .figures;
        final bare = await plan('D\n(8) Neighbor swing\n(8) Long lines\n');
        final marked = await plan(
          'D\n- A1 (8) Neighbor swing\n* (8) Long lines\n',
        );
        final numbered = await plan(
          '# D\n\n1. (8) Neighbor swing\n2) (8) Long lines\n',
        );
        expect(figuresOf(bare), hasLength(2));
        expect(figuresOf(marked), figuresOf(bare));
        expect(figuresOf(numbered), figuresOf(bare));
      },
    );

    test('committed dances have no provenance row', () async {
      final batch = await plan(fixture('three_dances.txt'));
      final session = await importer.commit(
        batch,
        mapping: mapped(fixture('three_dances.txt')).$2,
        now: DateTime.utc(2026, 11, 24),
        newId: ids(),
      );
      expect(session.session.insertedDanceIds, hasLength(3));
      for (final id in session.session.insertedDanceIds) {
        expect((await dances.getById(id))!.provenance, isNull);
      }
    });
  });
}
