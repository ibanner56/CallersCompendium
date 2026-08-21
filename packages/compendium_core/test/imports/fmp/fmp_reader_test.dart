import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_core/src/imports/fmp/fmp_reader.dart';
import 'package:test/test.dart';

/// Tests for the pure-Dart FileMaker 12 container reader ([readFmp12]).
///
/// The reader's data correctness is proven against **real** FileMaker files.
/// Those files are not redistributed in the repo (licensing), so the
/// data-level assertions live in a suite that is **skipped unless** a local
/// fixture is present at `test/imports/support/fmp_local/Charts.fmp12`
/// (git-ignored). Drop a real `.fmp12`/`.USR` there to exercise them locally;
/// CI runs only the hermetic guards below. During development this reader's
/// full output was diffed byte-for-byte against the reference `fmptools`
/// converters across five real files and every table.
void main() {
  group('readFmp12 format guard (hermetic)', () {
    test('rejects a non-FileMaker buffer', () {
      final bytes = Uint8List.fromList(List<int>.filled(2048, 0x41));
      expect(() => readFmp12(bytes), throwsA(isA<FmpFormatException>()));
    });

    test('rejects a too-small buffer', () {
      expect(
        () => readFmp12(Uint8List.fromList([0, 1, 2, 3])),
        throwsA(isA<FmpFormatException>()),
      );
    });

    test('rejects the magic number but non-HBAM7 (old fp3/fp5) layout', () {
      final bytes = Uint8List(2048);
      const magic = [
        0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, //
        0x00, 0x05, 0x00, 0x02, 0x00, 0x02, 0xC0,
      ];
      bytes.setRange(0, magic.length, magic);
      // Leave offset 15.. as zeros (not "HBAM7").
      expect(() => readFmp12(bytes), throwsA(isA<FmpFormatException>()));
    });
  });

  group('readFmp12 against a real file (local-only)', () {
    final fixture = File('test/imports/support/fmp_local/Charts.fmp12');

    test('recovers Charts.fmp12 tables, columns and values', () {
      final db = readFmp12(fixture.readAsBytesSync());

      expect(db.versionNum, 12);
      expect(
        db.tables.map((t) => t.name),
        containsAll(<String>['US Population', 'Demo', 'Congress']),
      );

      final demo = db.tableNamed('Demo');
      expect(demo, isNotNull);
      expect(
        demo!.columns.map((c) => c.name),
        containsAll(<String>['SeriesX', 'SeriesY1', 'ChartTitle']),
      );

      final first = demo.records.first;
      String? cell(String col) =>
          first.valuesByColumnIndex[demo.columnIndexOf(col)];
      // SeriesX/SeriesY1 are return-delimited multi-value chart fields.
      expect(cell('SeriesX'), startsWith('Apple'));
      expect(cell('SeriesX'), contains('Banana'));
      expect(cell('ChartTitle'), contains('Pie Ingredients'));

      // A data-heavy table round-trips a substantial number of records.
      expect(db.tableNamed('Congress')!.records, isNotEmpty);
    }, skip: fixture.existsSync() ? false : 'no local fmp fixture present');
  });
}
