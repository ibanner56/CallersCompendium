import 'dart:isolate';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/usr_archive_isolate.dart';

import '../support/fmp_fixture_builder.dart';

Uint8List _usrBytes() => buildFmp12Fixture([
  FmpFixtureTable(
    index: 1,
    name: 'Dance',
    columnNames: ['zk_Dance_ID', 'Name', 'Author1'],
    rows: [
      MapEntry(1, {1: '1', 2: 'Simplicity Swing', 3: 'Becky Hill'}),
      MapEntry(2, {1: '2', 2: 'Petronella', 3: 'Trad'}),
    ],
  ),
  FmpFixtureTable(
    index: 3,
    name: 'Set',
    columnNames: ['zk_Set_ID', 'Location'],
    rows: [
      MapEntry(1, {1: '9', 2: 'Grange Hall'}),
    ],
  ),
]);

/// Top-level so it can be sent to a worker isolate.
SendPort _workerControlPort(Uint8List _) => Isolate.current.controlPort;

Object _summary(CcUsrArchive a) => {
  'dances': [
    for (final d in a.dances)
      '${d.recordId}|${d.record.name}|${d.record.authors.join('&')}',
  ],
  'sets': [for (final s in a.sets) '${s.recordId}|${s.location}'],
  'warnings': a.warnings,
};

void main() {
  test('parses on a different isolate than the caller', () async {
    final worker = await runOnIsolateWithBytes(_usrBytes(), _workerControlPort);
    expect(worker, isNot(Isolate.current.controlPort));
  });

  test('the archive equals a direct read of the same bytes', () async {
    final bytes = _usrBytes();
    final viaIsolate = await readCcUsrArchiveInIsolate(
      bytes,
      const FmpReadLimits(),
    );
    final direct = readCcUsrArchive(bytes);
    expect(viaIsolate.dances, hasLength(2));
    expect(_summary(viaIsolate), _summary(direct));
  });

  test('leaves the caller\'s bytes intact and usable', () async {
    final bytes = _usrBytes();
    final before = Uint8List.fromList(bytes);
    await readCcUsrArchiveInIsolate(bytes, const FmpReadLimits());
    expect(bytes, before);
    // Still readable afterwards: the transfer copied rather than consumed them.
    expect(readCcUsrArchive(bytes).dances, hasLength(2));
  });

  test('a limit the reader enforces surfaces as the same exception', () {
    expect(
      readCcUsrArchiveInIsolate(_usrBytes(), const FmpReadLimits(maxTables: 1)),
      throwsA(isA<FmpResourceLimitException>()),
    );
  });

  test('a non-FileMaker file surfaces as the same exception', () {
    expect(
      readCcUsrArchiveInIsolate(
        Uint8List.fromList(List<int>.filled(4096 * 3, 0x41)),
        const FmpReadLimits(),
      ),
      throwsA(isA<FmpFormatException>()),
    );
  });

  test(
    'works as the adapter\'s reader, keeping the friendly error mapping',
    () async {
      final adapter = CallersCompanionUsrAdapter(
        limits: const FmpReadLimits(maxTables: 1),
        reader: readCcUsrArchiveInIsolate,
      );
      await expectLater(
        adapter.discover(ImportRequest(options: {'bytes': _usrBytes()})),
        throwsA(
          isA<ImportError>().having(
            (e) => e.message,
            'message',
            'That file is too large to import.',
          ),
        ),
      );
      final ok = CallersCompanionUsrAdapter(reader: readCcUsrArchiveInIsolate);
      final records = await ok.discover(
        ImportRequest(options: {'bytes': _usrBytes()}),
      );
      expect(records.map((r) => r.label), ['Simplicity Swing', 'Petronella']);
    },
  );
}
