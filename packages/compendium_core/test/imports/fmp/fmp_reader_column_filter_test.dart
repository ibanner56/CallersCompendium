import 'dart:typed_data';

import 'package:compendium_core/src/imports/fmp/fmp_reader.dart';
import 'package:test/test.dart';

import '../support/fmp_fixture_builder.dart';

/// [readFmp12]'s `columnFilter` skips decoding dropped columns without changing
/// anything else: row identity, record ids, the record budget and the complete
/// column schema all stay as an unfiltered read would give them.

const _longText =
    'A long transcription line, repeated so it spans several segment chunks and '
    'more than one sector: 0123456789 0123456789 0123456789 0123456789 '
    '0123456789 0123456789 0123456789 0123456789 0123456789 0123456789.';

FmpFixtureTable _table() => FmpFixtureTable(
  index: 1,
  name: 'Dance',
  columnNames: ['Name', 'Author1', 'Notes', 'Search', 'Level'],
  longColumns: {4},
  rows: [
    MapEntry(10, {1: 'One', 2: 'Alice', 4: _longText * 2, 5: 'Basic'}),
    // Only a dropped column present: the row must still exist.
    MapEntry(11, {2: 'Bob'}),
    MapEntry(12, {1: 'Three', 3: 'note', 4: _longText, 5: 'Adv'}),
    // Only the long dropped column.
    MapEntry(13, {4: _longText}),
    MapEntry(14, {1: 'Five', 2: 'Cy', 5: 'Basic'}),
  ],
);

Uint8List _bytes({FmpMultiSectorOptions? options}) =>
    buildFmp12FixtureMultiSector([
      _table(),
    ], options: options ?? const FmpMultiSectorOptions(sectorBudget: 300));

List<Map<int, String>> _rows(FmpDatabase db) => [
  for (final r in db.tableNamed('Dance')!.records) r.valuesByColumnIndex,
];

void main() {
  test('the long column really is stored as a long string', () {
    final all = readFmp12(_bytes());
    expect(_rows(all)[0][4], _longText * 2);
    expect(_rows(all)[3], {4: _longText});
  });

  test('a null filter and a keep-everything filter change nothing', () {
    final base = _rows(readFmp12(_bytes()));
    expect(_rows(readFmp12(_bytes(), columnFilter: (_, _) => null)), base);
    expect(
      _rows(
        readFmp12(
          _bytes(),
          columnFilter: (_, cols) => {for (final c in cols) c.index},
        ),
      ),
      base,
    );
  });

  test('dropped columns are absent; kept columns are exactly as read', () {
    final db = readFmp12(_bytes(), columnFilter: (_, _) => {1, 5});
    expect(_rows(db), [
      {1: 'One', 5: 'Basic'},
      <int, String>{}, // Bob's row: only a dropped column
      {1: 'Three', 5: 'Adv'},
      <int, String>{}, // the row that held only the long dropped column
      {1: 'Five', 5: 'Basic'},
    ]);
  });

  test('row identity survives: every row keeps its record id', () {
    final db = readFmp12(_bytes(), columnFilter: (_, _) => {1});
    expect(
      [for (final r in db.tableNamed('Dance')!.records) r.id],
      [10, 11, 12, 13, 14],
    );
  });

  test('a kept long column is still reassembled across segments/sectors', () {
    final db = readFmp12(_bytes(), columnFilter: (_, _) => {4});
    expect(_rows(db), [
      {4: _longText * 2},
      <int, String>{},
      {4: _longText},
      {4: _longText},
      <int, String>{},
    ]);
  });

  test('the column schema stays complete', () {
    final db = readFmp12(_bytes(), columnFilter: (_, _) => {1});
    expect(
      [for (final c in db.tableNamed('Dance')!.columns) c.name],
      ['Name', 'Author1', 'Notes', 'Search', 'Level'],
    );
  });

  test('the callback receives the table name and its full schema', () {
    String? seenName;
    List<String>? seenColumns;
    readFmp12(
      _bytes(),
      columnFilter: (name, cols) {
        seenName = name;
        seenColumns = [for (final c in cols) c.name];
        return null;
      },
    );
    expect(seenName, 'Dance');
    expect(seenColumns, ['Name', 'Author1', 'Notes', 'Search', 'Level']);
  });

  test('dropped-only rows still count toward the record budget', () {
    // 5 rows, of which two hold only dropped columns. Skipping them from the
    // count would let 3 pass; the budget must count all 5.
    expect(
      () => readFmp12(
        _bytes(),
        columnFilter: (_, _) => {1},
        limits: const FmpReadLimits(maxRecords: 5),
      ),
      returnsNormally,
    );
    expect(
      () => readFmp12(
        _bytes(),
        columnFilter: (_, _) => {1},
        limits: const FmpReadLimits(maxRecords: 4),
      ),
      throwsA(isA<FmpResourceLimitException>()),
    );
  });

  test('with filler sectors, pruned == unpruned under a filter', () {
    const busy = FmpMultiSectorOptions(
      sectorBudget: 300,
      indexSectorsPerTable: 2,
      mediaSectors: 1,
      mixedSectors: true,
    );
    Set<int>? keep(String _, List<FmpColumn> _) => {1, 4};
    expect(
      _rows(readFmp12(_bytes(options: busy), columnFilter: keep)),
      _rows(
        readFmp12(
          _bytes(options: busy),
          columnFilter: keep,
          pruneSectors: false,
        ),
      ),
    );
  });
}
