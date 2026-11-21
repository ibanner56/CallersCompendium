import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Reading a Caller's Companion file's `Term` table as glossary terms (#1023,
/// maintainer decision 7).
///
/// Provenance: the table and column names are those of a real
/// `CallersCompanion2.USR` the maintainer supplied (`Term`, `Definition`,
/// `Source`, `Notes`, among CC's own bookkeeping columns), and so are the
/// rows' shapes: one term with a definition and a source citation, one with
/// only a teaching note. The text is illustrative.
void main() {
  final columns = [
    FmpColumn(1, 'Term'),
    FmpColumn(2, 'Definition'),
    FmpColumn(3, 'Source'),
    FmpColumn(4, 'zc_CreatedTimeStamp'),
    FmpColumn(5, 'zk_Constant'),
    FmpColumn(6, 'Notes'),
  ];

  FmpDatabase database(List<FmpRecord> rows, {List<FmpColumn>? cols}) =>
      FmpDatabase(
        versionNum: 12,
        creator: 'Pro 12.0',
        tables: [FmpTable(1, 'Term', cols ?? columns, rows)],
        warnings: const [],
      );

  test('reads each term with its definition, source and notes', () {
    final archive = extractCcUsrArchive(
      database([
        FmpRecord(10, {
          1: 'Dixie Twirl',
          2: 'The left-most pair go under an arch.',
          3: 'Give and Take - Larry Jennings',
          4: '10/16/2010 3:14:02 PM',
          5: '1',
        }),
        FmpRecord(11, {
          1: 'Contra Corners',
          5: '1',
          6: 'Teaching note: free your right hand first.',
        }),
      ]),
    );
    expect(archive.terms, hasLength(2));
    final twirl = archive.terms.first;
    expect(twirl.name, 'Dixie Twirl');
    expect(twirl.definition, 'The left-most pair go under an arch.');
    expect(twirl.source, 'Give and Take - Larry Jennings');
    expect(twirl.notes, isNull);
    final corners = archive.terms.last;
    expect(corners.name, 'Contra Corners');
    expect(corners.definition, isNull);
    expect(corners.source, isNull);
    expect(corners.notes, 'Teaching note: free your right hand first.');
    expect(
      archive.warnings.where((w) => w.toLowerCase().contains('term')),
      isEmpty,
    );
  });

  test('sanitizes every field, the name to one line', () {
    final term = extractCcUsrArchive(
      database([
        FmpRecord(1, {
          1: 'Dixie\nTwirl\u202e',
          2: 'Under\u202e the arch.\nThen out.',
          3: 'Give\u200f and Take',
          6: '  ',
        }),
      ]),
    ).terms.single;
    expect(term.name, 'Dixie Twirl', reason: 'a break reads as a space');
    expect(term.name.contains('\u202e'), isFalse);
    expect(term.definition, contains('\n'), reason: 'prose keeps its lines');
    expect(term.definition!.contains('\u202e'), isFalse);
    expect(term.source!.contains('\u200f'), isFalse);
    expect(term.notes, isNull, reason: 'blank is none');
  });

  test('a row with no name is skipped', () {
    final archive = extractCcUsrArchive(
      database([
        FmpRecord(1, {1: '   ', 2: 'Orphaned definition.'}),
        FmpRecord(2, {2: 'No name at all.'}),
        FmpRecord(3, {1: 'Kept'}),
      ]),
    );
    expect(archive.terms.map((t) => t.name), ['Kept']);
  });

  test('a row longer than a glossary entry can be is skipped, with a '
      'warning', () {
    final archive = extractCcUsrArchive(
      database([
        FmpRecord(1, {1: 'x' * (maxUserGlossaryNameLength + 1)}),
        FmpRecord(2, {1: 'Long', 2: 'y' * (maxUserGlossaryTextLength + 1)}),
        FmpRecord(3, {
          1: 'Long source',
          3: 'z' * (maxUserGlossaryTextLength + 1),
        }),
        FmpRecord(4, {
          1: 'Long notes',
          6: 'w' * (maxUserGlossaryTextLength + 1),
        }),
        FmpRecord(5, {
          1: 'n' * maxUserGlossaryNameLength,
          2: 'd' * maxUserGlossaryTextLength,
        }),
      ]),
    );
    expect(archive.terms, hasLength(1), reason: 'at the bounds is kept');
    expect(archive.warningCodes, contains(CcUsrWarningCodes.termsSkipped));
    expect(archive.warnings.where((w) => w.contains('term')), [
      '4 Caller\'s Companion term(s) were longer than a glossary entry can '
          'be and were skipped.',
    ]);
  });

  test('a field is measured as the glossary stores it, after '
      'normalization', () {
    // U+FB2A becomes two code units under NFC: 200 of them fit as typed, but
    // not as stored.
    final archive = extractCcUsrArchive(
      database([
        FmpRecord(1, {1: '\ufb2a' * maxUserGlossaryNameLength}),
        FmpRecord(2, {1: 'Kept'}),
      ]),
    );
    expect(archive.terms.map((t) => t.name), ['Kept']);
  });

  test('a FileMaker line break in a name reads as a space', () {
    final term = extractCcUsrArchive(
      database([
        FmpRecord(1, {1: 'Contra\rCorners'}),
      ]),
    ).terms.single;
    expect(term.name, 'Contra Corners');
  });

  test('columns are found by a tolerant name too', () {
    final term = extractCcUsrArchive(
      database(
        [
          FmpRecord(1, {1: 'Gypsy', 2: 'Walk around.', 3: 'Book'}),
        ],
        cols: [
          FmpColumn(1, 'TermName'),
          FmpColumn(2, 'definition'),
          FmpColumn(3, 'SOURCE'),
        ],
      ),
    ).terms.single;
    expect(term.name, 'Gypsy');
    expect(term.definition, 'Walk around.');
    expect(term.source, 'Book');
  });

  test('no Term table reads no terms, silently; one with no term column '
      'says so', () {
    final none = extractCcUsrArchive(
      FmpDatabase(
        versionNum: 12,
        creator: 'Pro 12.0',
        tables: [
          FmpTable(1, 'Dance', [FmpColumn(1, 'Name')], const []),
        ],
        warnings: const [],
      ),
    );
    expect(none.terms, isEmpty);
    expect(none.warnings.where((w) => w.contains('"Term"')), isEmpty);

    final unresolved = extractCcUsrArchive(
      database(
        [
          FmpRecord(1, {1: 'x'}),
        ],
        cols: [FmpColumn(1, 'Word')],
      ),
    );
    expect(unresolved.terms, isEmpty);
    expect(
      unresolved.warnings.where((w) => w.contains('"Term"')),
      hasLength(1),
    );
    expect(unresolved.warningCodes, contains(CcUsrWarningCodes.termsSkipped));
  });

  test('too many Term rows fails closed', () {
    expect(
      () => extractCcUsrArchive(
        database([
          for (var i = 0; i < 5; i++) FmpRecord(i, {1: 'Term $i'}),
        ]),
        limits: const FmpReadLimits(maxTermRows: 3),
      ),
      throwsA(isA<FmpResourceLimitException>()),
    );
  });

  test('the terms outlive the dances at commit time', () {
    final archive = extractCcUsrArchive(
      database([
        FmpRecord(1, {1: 'Kept'}),
      ]),
    );
    expect(archive.withoutDances().terms.single.name, 'Kept');
  });

  test('the reader is asked for the Term table', () {
    expect(ccUsrArchiveTableNames, contains('Term'));
  });
}
