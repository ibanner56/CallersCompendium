import 'dart:math';
import 'dart:typed_data';

import 'package:compendium_core/src/imports/fmp/fmp_reader.dart';
import 'package:test/test.dart';

import '../support/fmp_fixture_builder.dart';

/// Proves that sector pruning and the table allowlist change what the reader
/// *costs*, never what it *returns*: every result is compared with the rows the
/// fixture authored and with an unpruned read of the same bytes.

List<FmpFixtureTable> _tables() => [
  FmpFixtureTable(
    index: 1,
    name: 'Dance',
    columnNames: ['Name', 'Author1', 'Notes', 'Level'],
    rows: [
      for (var i = 0; i < 90; i++)
        MapEntry(i + 1, {
          1: 'Dance $i',
          2: 'Author ${i % 7}',
          if (i % 3 == 0) 3: 'note ${'x' * (i % 40)}',
          if (i % 5 == 0) 4: 'Basic',
        }),
    ],
  ),
  FmpFixtureTable(
    index: 5,
    name: 'Phrase',
    columnNames: ['PhraseNumber', 'PhraseText', 'zk_Dance_ID'],
    rows: [
      for (var i = 0; i < 240; i++)
        MapEntry(200 + i, {
          1: ['A1', 'A2', 'B1', 'B2'][i % 4],
          2: '(8) figure line ${'y' * (i % 60)}',
          3: '${i ~/ 4 + 1}',
        }),
    ],
  ),
  FmpFixtureTable(
    index: 9,
    name: 'MD_References',
    columnNames: ['Ref', 'Page'],
    rows: [
      for (var i = 0; i < 60; i++) MapEntry(400 + i, {1: 'Book $i', 2: '$i'}),
    ],
  ),
];

const _busy = FmpMultiSectorOptions(
  sectorBudget: 500,
  indexSectorsPerTable: 3,
  mediaSectors: 2,
  mixedSectors: true,
  badOpcodeSectors: 1,
);

/// A comparable, order-stable rendering of everything a read returns.
Object _snapshot(FmpDatabase db) => {
  'version': db.versionNum,
  'creator': db.creator,
  'warnings': db.warnings,
  'tables': [
    for (final t in db.tables)
      {
        'index': t.index,
        'name': t.name,
        'columns': [for (final c in t.columns) '${c.index}=${c.name}'],
        'records': [
          for (final r in t.records)
            {'id': r.id, 'values': r.valuesByColumnIndex},
        ],
      },
  ],
};

/// A read's outcome, so a throw compares equal to the same throw.
Object _outcome(Uint8List bytes, {required bool prune, Set<String>? tables}) {
  try {
    return _snapshot(readFmp12(bytes, tables: tables, pruneSectors: prune));
  } on FmpFormatException catch (e) {
    return 'FmpFormatException: ${e.message}';
  } on FmpResourceLimitException catch (e) {
    return 'FmpResourceLimitException: ${e.message}';
  }
}

void main() {
  group('sector pruning', () {
    test('the busy fixture really spans many sectors and carries fillers', () {
      final bytes = buildFmp12FixtureMultiSector(_tables(), options: _busy);
      // header + root + a good many body sectors: the tests below would prove
      // little on a one-sector file.
      expect(bytes.length ~/ 4096, greaterThan(40));
    });

    test('returns exactly the authored rows, filler sectors ignored', () {
      final bytes = buildFmp12FixtureMultiSector(_tables(), options: _busy);
      final db = readFmp12(bytes);
      expect(db.tables.map((t) => t.name), [
        'Dance',
        'Phrase',
        'MD_References',
      ]);
      for (final authored in _tables()) {
        final read = db.tableNamed(authored.name)!;
        expect(
          [for (final r in read.records) r.id],
          [for (final r in authored.rows) r.key],
        );
        expect(
          [for (final r in read.records) r.valuesByColumnIndex],
          [for (final r in authored.rows) r.value],
        );
        expect([for (final c in read.columns) c.name], authored.columnNames);
      }
    });

    test('pruned read == unpruned read, cell for cell', () {
      final bytes = buildFmp12FixtureMultiSector(_tables(), options: _busy);
      expect(_outcome(bytes, prune: true), _outcome(bytes, prune: false));
    });

    test('a sector that switches table mid-sector keeps its records', () {
      // Every table gets a first/last data sector that opens (or closes) with
      // index or media chunks. Judging a sector by its leading path would drop
      // those records or, worse, the catalog.
      final bytes = buildFmp12FixtureMultiSector(
        _tables(),
        options: const FmpMultiSectorOptions(
          sectorBudget: 4000,
          mixedSectors: true,
        ),
      );
      final db = readFmp12(bytes);
      expect([for (final t in db.tables) t.records.length], [90, 240, 60]);
    });

    test('decode warnings match an unpruned read (order included)', () {
      final bytes = buildFmp12FixtureMultiSector(_tables(), options: _busy);
      final pruned = readFmp12(bytes).warnings;
      expect(pruned, isNotEmpty); // the bad-opcode sector
      expect(pruned, readFmp12(bytes, pruneSectors: false).warnings);
    });
  });

  group('table allowlist', () {
    late Uint8List bytes;
    setUp(() {
      bytes = buildFmp12FixtureMultiSector(_tables(), options: _busy);
    });

    test('returns only the named tables, case-insensitively', () {
      final db = readFmp12(bytes, tables: {'dance', 'PHRASE', 'NoSuchTable'});
      expect(db.tables.map((t) => t.name), ['Dance', 'Phrase']);
    });

    test('each returned table equals the same table from a full read', () {
      final full = readFmp12(bytes, pruneSectors: false);
      final some = readFmp12(bytes, tables: {'Phrase', 'MD_References'});
      for (final t in some.tables) {
        final other = full.tableNamed(t.name)!;
        expect(t.columns.map((c) => '${c.index}=${c.name}'), [
          for (final c in other.columns) '${c.index}=${c.name}',
        ]);
        expect(
          [for (final r in t.records) '${r.id}:${r.valuesByColumnIndex}'],
          [for (final r in other.records) '${r.id}:${r.valuesByColumnIndex}'],
        );
      }
    });

    test('pruned and unpruned agree for the same allowlist', () {
      const names = {'Dance', 'Phrase'};
      expect(
        _outcome(bytes, prune: true, tables: names),
        _outcome(bytes, prune: false, tables: names),
      );
    });

    test('the record budget counts only the requested tables', () {
      // Dance 90 + Phrase 240 = 330 wanted rows; the file holds 390.
      expect(
        () => readFmp12(
          bytes,
          tables: {'Dance', 'Phrase'},
          limits: const FmpReadLimits(maxRecords: 330),
        ),
        returnsNormally,
      );
      expect(
        () => readFmp12(
          bytes,
          tables: {'Dance', 'Phrase'},
          limits: const FmpReadLimits(maxRecords: 329),
        ),
        throwsA(isA<FmpResourceLimitException>()),
      );
    });

    test('the table-count bound still applies to the whole file', () {
      expect(
        () => readFmp12(
          bytes,
          tables: {'Dance'},
          limits: const FmpReadLimits(maxTables: 2),
        ),
        throwsA(isA<FmpResourceLimitException>()),
      );
    });
  });

  test('seeded byte mutations: pruned and unpruned reads never disagree', () {
    final base = buildFmp12FixtureMultiSector(_tables(), options: _busy);
    final rng = Random(0x1418);
    for (var i = 0; i < 300; i++) {
      final bytes = Uint8List.fromList(base);
      // Mutate only the body (a mangled header just throws in both).
      for (var k = 0, n = 1 + rng.nextInt(4); k < n; k++) {
        bytes[8192 + rng.nextInt(bytes.length - 8192)] = rng.nextInt(256);
      }
      expect(
        _outcome(bytes, prune: true),
        _outcome(bytes, prune: false),
        reason: 'iteration $i',
      );
    }
  });
}
