import 'dart:convert';
import 'dart:typed_data';

import 'package:compendium_app/src/data/backup_io.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readBackupFile size cap', () {
    test('reads a file that is within the size cap', () async {
      const contents = '{"backupVersion":1,"core":{}}';
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(contents)),
        name: 'ok.json',
      );

      expect(await readBackupFile(file), contents);
    });

    test('rejects a file larger than the cap without reading it', () async {
      // `length` is overstated without allocating the bytes, so the guard must
      // refuse based on the reported size *before* touching the (tiny) data.
      final file = XFile.fromData(
        Uint8List(0),
        name: 'huge.json',
        length: kMaxBackupFileBytes + 1,
      );

      await expectLater(
        readBackupFile(file),
        throwsA(isA<BackupFileTooLargeException>()),
      );
    });

    test('accepts a file exactly at the cap', () async {
      final file = XFile.fromData(
        Uint8List(0),
        name: 'edge.json',
        length: kMaxBackupFileBytes,
      );

      // At the boundary the read is attempted (the 0-byte payload decodes to '').
      expect(await readBackupFile(file), '');
    });

    test('the friendly message names both sizes and reassures the user', () {
      const e = BackupFileTooLargeException(
        sizeBytes: 60 * 1024 * 1024,
        maxBytes: 50 * 1024 * 1024,
      );

      expect(e.message, contains('too large'));
      expect(e.message, contains('60.0 MB'));
      expect(e.message, contains('50.0 MB'));
      expect(e.message, contains('unchanged'));
    });

    test('rejects a file that reports a small/stale length but STREAMS more '
        'than the cap (TOCTOU: the stat is not trusted as the bound)', () async {
      // The reported length (1) is well under the cap, so the fast pre-check
      // passes — but the file actually streams 32 bytes. The real, streamed
      // read must enforce the bound and reject, proving length() alone is not
      // relied on (the path could grow/be swapped between stat and read).
      const maxBytes = 10;
      final file = XFile.fromData(
        Uint8List.fromList(List<int>.filled(32, 0x20)),
        name: 'stale-length.json',
        length: 1,
      );

      await expectLater(
        readBackupFile(file, maxBytes: maxBytes),
        throwsA(
          isA<BackupFileTooLargeException>()
              // The rejection reflects the ACTUAL streamed size, not the stale
              // reported length.
              .having((e) => e.sizeBytes, 'sizeBytes', greaterThan(maxBytes))
              .having((e) => e.maxBytes, 'maxBytes', maxBytes),
        ),
      );
    });

    test('reads a within-cap file through the streamed path (UTF-8)', () async {
      const contents = '{"backupVersion":1,"core":{"dances":[]}}';
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(contents)),
        name: 'streamed.json',
        // Stale small length must not truncate the real read.
        length: 1,
      );

      expect(await readBackupFile(file, maxBytes: 1024), contents);
    });
  });
}
