import 'package:compendium_core/src/imports/callers_companion_usr_archive.dart';
import 'package:compendium_core/src/imports/fmp/fmp_reader.dart';
import 'package:test/test.dart';

/// Tests for the CC-schema extraction layer ([extractCcUsrArchive] /
/// [ccDanceRecordFromColumns]).
///
/// The raw FileMaker container reader ([readFmp12]) is validated separately
/// against real files; here we feed a **hand-built** [FmpDatabase] shaped like
/// the CC schema so the CC-specific mapping (table/column discovery, the
/// tolerant Set/SetItem foreign-key matching, and the verbatim raw-column
/// preservation) is tested hermetically and Flutter-free.
FmpDatabase _ccDatabase() {
  final dance = FmpTable(
    1,
    'Dance',
    [
      FmpColumn(1, 'Name'),
      FmpColumn(2, 'Author1'),
      FmpColumn(3, 'Type'),
      FmpColumn(4, 'ContraForm'),
      FmpColumn(5, 'Level'),
      FmpColumn(6, 'A1'),
      FmpColumn(7, 'Rating'),
      FmpColumn(8, 'DateComposed'),
      FmpColumn(9, 'UserDefined_1'),
      FmpColumn(10, 'UserDefined_1_Name'),
      FmpColumn(11, 'Music'),
    ],
    [
      FmpRecord(7, {
        1: 'Simplicity Swing',
        2: 'Becky Hill',
        3: 'Contra',
        4: 'Improper',
        5: 'Intermediate',
        6: '(8) gypsy your partner',
        7: '3',
        8: '2016',
        9: 'blue',
        10: 'Card colour',
        11: 'a lovely reel',
      }),
    ],
  );

  final set = FmpTable(
    2,
    'Set',
    [
      FmpColumn(1, 'Title'),
      FmpColumn(2, 'Date'),
      FmpColumn(3, 'Location'),
      FmpColumn(4, 'Band'),
      FmpColumn(5, 'Caller'),
      FmpColumn(6, 'Notes'),
    ],
    [
      FmpRecord(100, {
        1: 'Friday Contra',
        2: '3/14/2020',
        3: 'Grange Hall',
        4: 'The Band',
        5: 'Jane',
        6: 'a good night',
      }),
    ],
  );

  final setItem = FmpTable(
    3,
    'SetItem',
    [
      FmpColumn(1, 'SetId'),
      FmpColumn(2, 'DanceId'),
      FmpColumn(3, 'Order'),
      FmpColumn(4, 'Time'),
      FmpColumn(5, 'Break'),
    ],
    [
      FmpRecord(200, {1: '100', 2: '7', 3: '1', 4: '8'}),
      FmpRecord(201, {1: '100', 3: '2', 5: 'Waltz break'}),
    ],
  );

  return FmpDatabase(
    versionNum: 12,
    creator: 'Pro 12.0',
    tables: [dance, set, setItem],
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
    test('extracts dances keyed by their FileMaker record id', () {
      final archive = extractCcUsrArchive(_ccDatabase());

      expect(archive.dances, hasLength(1));
      final dance = archive.dances.single;
      expect(dance.recordId, '7');
      expect(dance.record.name, 'Simplicity Swing');
      // Raw columns are preserved verbatim (nothing dropped).
      expect(dance.rawColumns['Music'], 'a lovely reel');
      expect(dance.rawColumns['UserDefined_1_Name'], 'Card colour');
    });

    test('extracts sets with ordered items and resolves FK columns', () {
      final archive = extractCcUsrArchive(_ccDatabase());

      expect(archive.sets, hasLength(1));
      final set = archive.sets.single;
      expect(set.recordId, '100');
      expect(set.title, 'Friday Contra');
      expect(set.location, 'Grange Hall');
      expect(set.band, 'The Band');

      expect(set.items, hasLength(2));
      expect(set.items[0].order, 1);
      expect(set.items[0].danceRecordId, '7');
      expect(set.items[0].minutes, 8);
      expect(set.items[1].order, 2);
      expect(set.items[1].danceRecordId, isNull);
      expect(set.items[1].breakText, 'Waltz break');
    });

    test('records tolerant column-guess warnings for later confirmation', () {
      final archive = extractCcUsrArchive(_ccDatabase());
      expect(
        archive.warnings.any((w) => w.contains('SetItem→Set link')),
        isTrue,
      );
      expect(archive.warnings.any((w) => w.contains('program title')), isTrue);
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
