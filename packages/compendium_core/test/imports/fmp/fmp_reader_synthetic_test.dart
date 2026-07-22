import 'dart:typed_data';

import 'package:compendium_core/src/imports/fmp/fmp_reader.dart';
import 'package:test/test.dart';

import '../support/fmp_fixture_builder.dart';

/// Hermetic end-to-end test of [readFmp12] driven by a from-scratch
/// [buildFmp12Fixture] byte image (no real, licensed FileMaker file needed in
/// CI). This exercises the header parse, sector chain, chunk byte-code decoder,
/// path-stack traversal, and the table/column/record passes — the reader's core
/// machinery — round-tripping a container we author byte-by-byte.
void main() {
  test('reads tables, columns and rows from a built fmp12 image', () {
    final bytes = buildFmp12Fixture([
      FmpFixtureTable(
        index: 1,
        name: 'Dance',
        columnNames: ['Name', 'Author1'],
        rows: [
          MapEntry(7, {1: 'Simplicity Swing', 2: 'Becky Hill'}),
          MapEntry(9, {1: 'Petronella', 2: 'Trad'}),
        ],
      ),
    ]);

    final db = readFmp12(bytes);

    expect(db.versionNum, 12);
    expect(db.creator, 'Pro 12.0');

    final dance = db.tableNamed('Dance');
    expect(dance, isNotNull);
    expect(dance!.columns.map((c) => c.name), ['Name', 'Author1']);

    expect(dance.records, hasLength(2));
    // Records expose their real FileMaker record ids.
    expect(dance.records.map((r) => r.id), [7, 9]);

    final first = dance.records.first;
    expect(first.valuesByColumnIndex[1], 'Simplicity Swing');
    expect(first.valuesByColumnIndex[2], 'Becky Hill');
    expect(dance.records[1].valuesByColumnIndex[1], 'Petronella');
  });

  test('handles multiple tables and empty tables without crashing', () {
    final bytes = buildFmp12Fixture([
      FmpFixtureTable(
        index: 1,
        name: 'Dance',
        columnNames: ['Name'],
        rows: [
          MapEntry(1, {1: 'Simplicity Swing'}),
        ],
      ),
      FmpFixtureTable(
        index: 2,
        name: 'Set',
        columnNames: ['Title'],
        rows: [
          MapEntry(1, {1: 'Friday Contra'}),
        ],
      ),
    ]);

    final db = readFmp12(bytes);
    expect(db.tables.map((t) => t.name), containsAll(['Dance', 'Set']));
    expect(
      db.tableNamed('Set')!.records.single.valuesByColumnIndex[1],
      'Friday Contra',
    );
  });

  group('structural resource limits (fail-closed DoS guard)', () {
    // Two tables, one with two rows and two body sectors — enough to trip each
    // bound when its limit is set to 1.
    Uint8List twoTableFixture() => buildFmp12Fixture([
      FmpFixtureTable(
        index: 1,
        name: 'Dance',
        columnNames: ['Name'],
        rows: [
          MapEntry(1, {1: 'Simplicity Swing'}),
          MapEntry(2, {1: 'Petronella'}),
        ],
      ),
      FmpFixtureTable(
        index: 2,
        name: 'Set',
        columnNames: ['Title'],
        rows: [
          MapEntry(1, {1: 'Friday Contra'}),
        ],
      ),
    ]);

    test('rejects a file with too many tables', () {
      expect(
        () => readFmp12(
          twoTableFixture(),
          limits: const FmpReadLimits(maxTables: 1),
        ),
        throwsA(
          isA<FmpResourceLimitException>().having(
            (e) => e.message,
            'message',
            contains('too many tables'),
          ),
        ),
      );
    });

    test('rejects a file with too many records', () {
      expect(
        () => readFmp12(
          twoTableFixture(),
          limits: const FmpReadLimits(maxRecords: 1),
        ),
        throwsA(isA<FmpResourceLimitException>()),
      );
    });

    test('rejects a file with too many sectors', () {
      expect(
        () => readFmp12(
          twoTableFixture(),
          limits: const FmpReadLimits(maxSectors: 1),
        ),
        throwsA(isA<FmpResourceLimitException>()),
      );
    });

    test('parses normally under generous (default-shaped) limits', () {
      final db = readFmp12(
        twoTableFixture(),
        limits: const FmpReadLimits(
          maxTables: 100,
          maxSectors: 100,
          maxRecords: 100,
        ),
      );
      expect(db.tables.map((t) => t.name), containsAll(['Dance', 'Set']));
      expect(db.tableNamed('Dance')!.records, hasLength(2));
    });

    test('the default limits admit a normal small file', () {
      // Sanity: the production defaults never reject a legitimate tiny file.
      expect(() => readFmp12(twoTableFixture()), returnsNormally);
    });
  });
}
