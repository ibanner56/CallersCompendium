import 'dart:io';

import 'package:compendium_core/src/imports/callers_companion_usr_archive.dart';
import 'package:compendium_core/src/imports/fmp/fmp_reader.dart';
import 'package:test/test.dart';

import 'support/fmp_fixture_builder.dart';

/// [readCcUsrArchive] asks the reader for only the tables and columns the
/// importer uses. These tests prove that is invisible to the result — the same
/// archive as reading every column of every table — and guard the list of
/// `Dance` columns against drifting from [ccDanceRecordFromColumns].

const _searchKey =
    'N\nNo\nNot\nNoto\nNotor\nNotori\nNotorio\nNotoriou\nNotorious\nNotorious \n'
    'Notorious F\nNotorious Fi\nNotorious Fir\nNotorious Firs\nNotorious First';

// Dance: readable columns interleaved with CC's derived helpers.
const _danceCols = [
  'zc_CreatedDate', //                     1  derived
  'zk_Dance_ID', //                        2  key
  'Name', //                               3
  'Author1', //                            4
  'Author2', //                            5
  'Formation', //                          6
  'zk_SearchKey_NameAuthor', //            7  derived, long
  'Music', //                              8
  'Credits', //                            9
  'UserDefined_1', //                     10
  'UserDefined_1_Name', //                11
  'zi_TypeFormLevel_c', //                12  derived
  'A1', //                                13  Dance-row fallback body
  'zz_TestUnstored', //                   14  derived
];

// Phrase: the real columns plus the duplicates the real table carries.
const _phraseCols = [
  'PhraseNumber', //                        1
  'PhraseText', //                          2
  'zk_Dance_ID', //                         3
  'PhraseText_GenderSwap_LR', //            4  must never be read as PhraseText
  'zi_PhraseDisplay6_HTML', //              5  derived
  'A1_Only', //                             6  derived duplicate
];

FmpFixtureTable _dances() => FmpFixtureTable(
  index: 1,
  name: 'Dance',
  columnNames: _danceCols,
  longColumns: {7},
  rows: [
    for (var i = 1; i <= 25; i++)
      MapEntry(100 + i, {
        1: '3/28/2016',
        2: '$i',
        3: 'Dance $i',
        4: 'Author ${i % 5}',
        if (i.isEven) 5: 'Second Author',
        6: i % 3 == 0 ? 'Becket' : 'Duple Minor',
        7: _searchKey * 3,
        8: 'Tune $i',
        9: 'Credit $i',
        if (i % 4 == 0) 10: 'user value $i',
        if (i % 4 == 0) 11: 'My field',
        12: 'Contra / Improper / Int',
        if (i == 7) 13: '(8) fallback figure',
        14: 'Duple Minor - Improper',
      }),
  ],
);

FmpFixtureTable _phrases() => FmpFixtureTable(
  index: 5,
  name: 'Phrase',
  columnNames: _phraseCols,
  rows: [
    for (var i = 1; i <= 25; i++)
      for (var p = 0; p < 4; p++)
        MapEntry(1000 + i * 10 + p, {
          1: ['A1', 'A2', 'B1', 'B2'][p],
          2: '(8) figure $i.$p\n(8) second line',
          3: '$i',
          4: '(8) SWAPPED $i.$p',
          5: '<b>(8) figure $i.$p</b>',
          6: '(8) figure $i.$p',
        }),
  ],
);

FmpFixtureTable _sets() => FmpFixtureTable(
  index: 3,
  name: 'Set',
  columnNames: ['zk_Set_ID', 'Date', 'Location', 'Band', 'Caller', 'Notes'],
  rows: [
    MapEntry(1, {
      1: '9',
      2: '4/5/2024',
      3: 'Town Hall',
      4: 'The Band',
      5: 'Me',
      6: 'note',
    }),
  ],
);

FmpFixtureTable _setItems() => FmpFixtureTable(
  index: 4,
  name: 'SetItem',
  columnNames: ['zk_Set_ID', 'zk_Dance_ID', 'Order', 'Time'],
  rows: [
    MapEntry(1, {1: '9', 2: '3', 3: '1', 4: '12'}),
    MapEntry(2, {1: '9', 2: '4', 3: '2', 4: '15'}),
  ],
);

FmpFixtureTable _reference() => FmpFixtureTable(
  index: 19,
  name: 'MD_References',
  columnNames: ['Ref', 'Page'],
  rows: [
    for (var i = 0; i < 40; i++) MapEntry(500 + i, {1: 'Book $i', 2: '$i'}),
  ],
);

final _bytes = buildFmp12FixtureMultiSector(
  [_dances(), _sets(), _setItems(), _phrases(), _reference()],
  options: const FmpMultiSectorOptions(
    sectorBudget: 700,
    indexSectorsPerTable: 2,
    mediaSectors: 2,
    mixedSectors: true,
  ),
);

/// Everything an archive consumer sees, in a comparable form. `rawColumns` is
/// deliberately excluded — narrowing it is the point.
Object _canonical(CcUsrArchive a) => {
  'dances': [
    for (final d in a.dances)
      {
        'id': d.recordId,
        'name': d.record.name,
        'authors': d.record.authors,
        'type': d.record.type,
        'formation': d.record.formation,
        'level': d.record.level,
        'progression': d.record.progression,
        'music': d.record.music,
        'notes': d.record.notes,
        'composed': d.record.composed,
        'revised': d.record.revised,
        'rating': d.record.rating,
        'userFields': [
          for (final u in d.record.userFields) '${u.label}=${u.value}',
        ],
        'body': [
          for (final b in d.record.body) '${b.label}:${b.lines.join('|')}',
        ],
      },
  ],
  'sets': [
    for (final s in a.sets)
      {
        'id': s.recordId,
        'title': s.title,
        'date': s.eventDate,
        'location': s.location,
        'band': s.band,
        'caller': s.caller,
        'notes': s.notes,
        'items': [
          for (final i in s.items)
            '${i.order}:${i.danceRecordId}:${i.minutes}:${i.breakText}',
        ],
      },
  ],
  'insertCalls': a.insertCalls.length,
  'related': a.relatedDancePairs.length,
  'warnings': a.warnings,
};

void main() {
  test('reading only the needed tables/columns gives the same archive', () {
    final narrow = readCcUsrArchive(_bytes);
    final whole = extractCcUsrArchive(readFmp12(_bytes));
    expect(narrow.dances, hasLength(25));
    expect(_canonical(narrow), _canonical(whole));
  });

  test('the Phrase join is unaffected (and never reads the swapped text)', () {
    final narrow = readCcUsrArchive(_bytes);
    final body = narrow.dances.first.record.body;
    expect(body.map((b) => b.label), ['A1', 'A2', 'B1', 'B2']);
    expect(body.first.lines, ['(8) figure 1.0', '(8) second line']);
    expect(
      body.expand((b) => b.lines).any((l) => l.contains('SWAPPED')),
      false,
    );
  });

  test('derived Dance columns are never decoded', () {
    final narrow = readCcUsrArchive(_bytes).dances.first.rawColumns;
    final whole = extractCcUsrArchive(
      readFmp12(_bytes),
    ).dances.first.rawColumns;
    // The unfiltered read really does carry the derived columns...
    expect(
      whole.keys,
      containsAll(['zk_SearchKey_NameAuthor', 'zi_TypeFormLevel_c']),
    );
    // ...the importer's read does not, and keeps every column it uses.
    expect(narrow.keys, isNot(contains('zk_SearchKey_NameAuthor')));
    expect(narrow.keys, isNot(contains('zi_TypeFormLevel_c')));
    expect(narrow.keys, isNot(contains('zz_TestUnstored')));
    expect(narrow.keys, isNot(contains('zc_CreatedDate')));
    expect(
      narrow.keys,
      containsAll([
        'zk_Dance_ID',
        'Name',
        'Author1',
        'Formation',
        'Music',
        'Credits',
      ]),
    );
  });

  test('a dance without a resolvable key column still reads its columns', () {
    // No `zk_Dance_ID`: the id falls back to the record id and the readable
    // columns must survive the filter.
    final bytes = buildFmp12FixtureMultiSector([
      FmpFixtureTable(
        index: 1,
        name: 'Dance',
        columnNames: ['Name', 'zk_SearchKey_NameAuthor'],
        rows: [
          MapEntry(7, {1: 'Petronella', 2: 'P\nPe\nPet'}),
        ],
      ),
    ]);
    final a = readCcUsrArchive(bytes);
    expect(a.dances.single.recordId, '7');
    expect(a.dances.single.record.name, 'Petronella');
    expect(a.dances.single.rawColumns.keys, ['Name']);
  });

  test(
    'every literal ccDanceRecordFromColumns looks up is in the list read',
    () {
      // The filter is only as good as kCcDanceColumnsRead. A lookup added to the
      // extractor but not to the list would read as empty on a real file while
      // every hand-built test database still passed, so scan the source.
      final src = File(
        'lib/src/imports/callers_companion_usr_archive.dart',
      ).readAsStringSync();
      final start = src.indexOf('CcDanceRecord ccDanceRecordFromColumns(');
      final end = src.indexOf('\n}\n', start);
      expect(start, greaterThan(0));
      final body = src.substring(start, end);

      final literals = <String>{
        for (final m in RegExp(r"lookup\.get\('([^'$]+)'\)").allMatches(body))
          m.group(1)!,
        for (final list in RegExp(
          r'firstNonEmpty\(\[([^\]]*)\]',
        ).allMatches(body))
          for (final m in RegExp(r"'([^']+)'").allMatches(list.group(1)!))
            m.group(1)!,
      };
      expect(literals, isNotEmpty, reason: 'the scan itself found nothing');
      final read = kCcDanceColumnsRead.map((n) => n.toLowerCase()).toSet();
      expect(
        literals.where((n) => !read.contains(n.toLowerCase())),
        isEmpty,
        reason:
            'looked up by ccDanceRecordFromColumns but not in '
            'kCcDanceColumnsRead',
      );
      // The interpolated lookups the regexp cannot see.
      for (var i = 1; i <= 3; i++) {
        expect(read, containsAll(['userdefined_$i', 'userdefined_${i}_name']));
      }
    },
  );
}
