import 'package:compendium_core/src/imports/callers_companion_usr_archive.dart';
import 'package:compendium_core/src/imports/fmp/fmp_reader.dart';
import 'package:test/test.dart';

/// Tests for the CC-schema extraction layer ([extractCcUsrArchive] /
/// [ccDanceRecordFromColumns]).
///
/// The raw FileMaker container reader ([readFmp12]) is validated separately
/// against real files; here we feed a **hand-built** [FmpDatabase] shaped like
/// the **real** CC schema so the CC-specific mapping is tested hermetically and
/// Flutter-free. Crucially the fixture mirrors the real file's identity model —
/// FileMaker record ids differ from CC's own `zk_Dance_ID`/`zk_Set_ID` fields,
/// and `SetItem` foreign keys reference the *field* values (in the real file,
/// Dance record 5430 carries `zk_Dance_ID=4`, and `SetItem.zk_Dance_ID=4` points
/// at it) — so the join logic must key on the CC ids, not the record ids.
///
/// Provenance: the table names, column names and the `record id ≠ zk_*_ID`
/// relationship are copied from the schema observed in the real
/// `CallersCompanion2.USR` (FileMaker Pro 12); the values are illustrative.
FmpDatabase _ccDatabase() {
  final dance = FmpTable(
    1,
    'Dance',
    [
      FmpColumn(3, 'zk_Dance_ID'),
      FmpColumn(1, 'Name'),
      FmpColumn(2, 'Author1'),
      FmpColumn(4, 'Type'),
      FmpColumn(5, 'ContraForm'),
      FmpColumn(6, 'Level'),
      FmpColumn(7, 'A1'),
      FmpColumn(8, 'Rating'),
      FmpColumn(9, 'DateComposed'),
      FmpColumn(10, 'UserDefined_1'),
      FmpColumn(11, 'UserDefined_1_Name'),
      FmpColumn(12, 'Music'),
    ],
    [
      // Record id 5430 but CC dance id 4 — deliberately different id spaces.
      FmpRecord(5430, {
        3: '4',
        1: 'Simplicity Swing',
        2: 'Becky Hill',
        4: 'Contra',
        5: 'Improper',
        6: 'Intermediate',
        7: '(8) gypsy your partner',
        8: '3',
        9: '2016',
        10: 'blue',
        11: 'Card colour',
        12: 'a lovely reel',
      }),
    ],
  );

  final set = FmpTable(
    2,
    'Set',
    [
      FmpColumn(4, 'zk_Set_ID'),
      FmpColumn(1, 'Date'),
      FmpColumn(2, 'Location'),
      FmpColumn(3, 'Notes'),
      FmpColumn(5, 'Band'),
      FmpColumn(23, 'Caller'),
    ],
    [
      // Record id 6156 but CC set id 1.
      FmpRecord(6156, {
        4: '1',
        1: '3/14/2020',
        2: 'Grange Hall',
        3: 'a good night',
        5: 'The Band',
        23: 'Jane',
      }),
    ],
  );

  final setItem = FmpTable(
    3,
    'SetItem',
    [
      FmpColumn(1, 'zk_Set_ID'),
      FmpColumn(2, 'zk_SetItem_ID'),
      FmpColumn(4, 'zk_Dance_ID'),
      FmpColumn(3, 'Order'),
      FmpColumn(19, 'Time'),
      FmpColumn(10, 'Break'),
    ],
    [
      // Item references the set/dance by CC *field* ids (1 and 4), not record
      // ids (6156 and 5430).
      FmpRecord(200, {1: '1', 2: '11', 4: '4', 3: '1', 19: '8'}),
      FmpRecord(201, {1: '1', 2: '12', 3: '2', 10: 'Waltz break'}),
    ],
  );

  // The real figure transcription lives in the separate `Phrase` table, keyed by
  // `zk_Dance_ID` + `PhraseNumber` (A1..C2). Rows are deliberately supplied
  // out of section order (B1 before A1/A2) so the ordering logic is exercised;
  // one `PhraseText` is multi-line to prove the newline split; and a
  // `PhraseText_GenderSwap_LR` variant is present to prove the resolver picks
  // the primary `PhraseText`, never a gender-swapped column. Provenance: the
  // table/column names and the gender-swap variants are copied from the real
  // `CallersCompanion2.USR` schema (see docs/research/callers-companion.md);
  // the values are illustrative.
  final phrase = FmpTable(
    4,
    'Phrase',
    [
      FmpColumn(1, 'zk_Dance_ID'),
      FmpColumn(2, 'PhraseNumber'),
      FmpColumn(3, 'PhraseText'),
      FmpColumn(4, 'PhraseText_GenderSwap_LR'),
    ],
    [
      FmpRecord(700, {1: '4', 2: 'B1', 3: '(8) circle left three places'}),
      FmpRecord(701, {
        1: '4',
        2: 'A1',
        3: '(16) neighbors balance and swing\n(8) partner do si do',
        4: 'GENDER SWAPPED - must be ignored',
      }),
      FmpRecord(702, {1: '4', 2: 'A2', 3: '(8) long lines forward and back'}),
    ],
  );

  return FmpDatabase(
    versionNum: 12,
    creator: 'Pro 12.0',
    tables: [dance, set, setItem, phrase],
    warnings: const [],
  );
}

void main() {
  group('ccDanceRecordFromColumns', () {
    test('maps the CC Dance columns onto a CcDanceRecord', () {
      final record = ccDanceRecordFromColumns({
        'Name': 'Simplicity Swing',
        'Author1': 'Becky Hill',
        'Author2': '',
        'Type': 'Contra',
        'ContraForm': 'Improper',
        'Level': 'Intermediate',
        'Rating': '3',
        'DateComposed': '2016',
        'Music': 'a lovely reel',
        'A1': '(8) gypsy your partner',
      });

      expect(record.name, 'Simplicity Swing');
      expect(record.authors, ['Becky Hill']);
      expect(record.type, 'Contra');
      expect(record.formation, 'Improper');
      expect(record.level, 'Intermediate');
      expect(record.rating, '3');
      expect(record.composed, '2016');
      expect(record.body.single.label, 'A1');
    });

    test('collects UserDefined_N into user fields with their labels', () {
      final record = ccDanceRecordFromColumns({
        'Name': 'X',
        'UserDefined_1': 'blue',
        'UserDefined_1_Name': 'Card colour',
        'UserDefined_2': 'loud',
      });
      expect(record.userFields, hasLength(2));
      expect(record.userFields[0].label, 'Card colour');
      expect(record.userFields[0].value, 'blue');
      // Missing *_Name falls back to a synthesised label.
      expect(record.userFields[1].label, 'User field 2');
      expect(record.userFields[1].value, 'loud');
    });

    test('"Mixed Level" flag promotes an empty Level to Mixed', () {
      final record = ccDanceRecordFromColumns({
        'Name': 'X',
        'Mixed Level': 'true',
      });
      expect(record.level, 'Mixed');
    });
  });

  group('extractCcUsrArchive', () {
    test('keys dances by CC zk_Dance_ID, not the FileMaker record id', () {
      final archive = extractCcUsrArchive(_ccDatabase());

      expect(archive.dances, hasLength(1));
      final dance = archive.dances.single;
      // The join identity is CC's zk_Dance_ID (4), not the record id (5430).
      expect(dance.recordId, '4');
      expect(dance.record.name, 'Simplicity Swing');
      // Raw columns are preserved verbatim (nothing dropped).
      expect(dance.rawColumns['Music'], 'a lovely reel');
      expect(dance.rawColumns['UserDefined_1_Name'], 'Card colour');
    });

    test('keys sets by zk_Set_ID and links items by CC field ids', () {
      final archive = extractCcUsrArchive(_ccDatabase());

      expect(archive.sets, hasLength(1));
      final set = archive.sets.single;
      // Keyed by CC set id (1), not the record id (6156).
      expect(set.recordId, '1');
      // CC Sets have no title column; the title is derived downstream.
      expect(set.title, isNull);
      expect(set.location, 'Grange Hall');
      expect(set.band, 'The Band');

      expect(set.items, hasLength(2));
      expect(set.items[0].order, 1);
      // Item links to the dance by its CC id (4) — matching dance.recordId.
      expect(set.items[0].danceRecordId, '4');
      expect(set.items[0].danceRecordId, archive.dances.single.recordId);
      expect(set.items[0].minutes, 8);
      expect(set.items[1].order, 2);
      expect(set.items[1].danceRecordId, isNull);
      expect(set.items[1].breakText, 'Waltz break');
    });

    test('does not emit "guess" warnings for the confirmed CC schema', () {
      final archive = extractCcUsrArchive(_ccDatabase());
      expect(archive.warnings.any((w) => w.contains('guessed')), isFalse);
      expect(
        archive.warnings.any((w) => w.contains('confirm against a real')),
        isFalse,
      );
    });

    test('populates the dance body from the Phrase table, ordered by '
        'PhraseNumber, splitting multi-line PhraseText', () {
      final archive = extractCcUsrArchive(_ccDatabase());
      final body = archive.dances.single.record.body;

      // Sections are ordered A1 → A2 → B1 even though the rows were supplied
      // B1, A1, A2 in the fixture.
      expect(body.map((s) => s.label), ['A1', 'A2', 'B1']);
      // The multi-line A1 PhraseText split into two lines on the newline.
      expect(body.first.lines, [
        '(16) neighbors balance and swing',
        '(8) partner do si do',
      ]);
      // The Phrase body — NOT the Dance-row A1 column ('(8) gypsy your
      // partner') — is the figure source when Phrase rows exist.
      final allLines = [for (final s in body) ...s.lines];
      expect(allLines.any((l) => l.contains('gypsy')), isFalse);
      // The gender-swapped variant column is never read into the body.
      expect(
        allLines.any((l) => l.toUpperCase().contains('GENDER SWAPPED')),
        isFalse,
      );
    });

    test('falls back to the Dance-row A1..C2 body when no Phrase rows exist', () {
      // Same schema, but the Phrase table carries no row for this dance — the
      // Dance-row A1 column must still supply the body (exports that carry it +
      // the CC text adapter path).
      final dance = FmpTable(
        1,
        'Dance',
        [FmpColumn(3, 'zk_Dance_ID'), FmpColumn(1, 'Name'), FmpColumn(7, 'A1')],
        [
          FmpRecord(5430, {3: '9', 1: 'Fallback Dance', 7: '(8) petronella'}),
        ],
      );
      final emptyPhrase = FmpTable(4, 'Phrase', [
        FmpColumn(1, 'zk_Dance_ID'),
        FmpColumn(3, 'PhraseText'),
      ], const []);
      final archive = extractCcUsrArchive(
        FmpDatabase(
          versionNum: 12,
          creator: 'Pro 12.0',
          tables: [dance, emptyPhrase],
          warnings: const [],
        ),
      );
      final body = archive.dances.single.record.body;
      expect(body.single.label, 'A1');
      expect(body.single.lines, ['(8) petronella']);
    });

    test('missing Dance/Set tables degrade to warnings, never throw', () {
      final empty = FmpDatabase(
        versionNum: 12,
        creator: 'Pro 12.0',
        tables: const [],
        warnings: const [],
      );
      final archive = extractCcUsrArchive(empty);
      expect(archive.dances, isEmpty);
      expect(archive.sets, isEmpty);
      expect(archive.warnings.any((w) => w.contains('"Dance" table')), isTrue);
      expect(archive.warnings.any((w) => w.contains('"Set" table')), isTrue);
    });
  });
}
