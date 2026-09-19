import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_app/src/data/backup_io.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter_test/flutter_test.dart';

/// Basenames of everything currently in [dir]. Because the atomic writer now
/// names its temp file unpredictably (symlink hardening), "no temp litter" can
/// no longer be checked against a fixed `<path>.tmp`; a whole-directory scan
/// asserts nothing at all was left behind.
List<String> _entryNames(Directory dir) => dir
    .listSync()
    .map((e) => e.path.split(Platform.pathSeparator).last)
    .toList();

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

  group('writeStringAtomically (atomic backup write)', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('backup_io_atomic_test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('an interrupted write leaves the previous good backup intact and '
        'leaves no temp litter', () async {
      final target = File('${dir.path}/backup.json');
      await target.writeAsString('GOOD');

      // Simulate a crash/disk-full *after* the temp file is written but before
      // the rename — the moment a naive in-place overwrite would already have
      // clobbered the previous good backup.
      await expectLater(
        writeStringAtomically(
          target.path,
          'NEW-BUT-DOOMED',
          debugSimulateFailure: () async =>
              throw const FileSystemException('simulated write failure'),
        ),
        throwsA(isA<FileSystemException>()),
      );

      // The prior good backup is untouched, and the failed write cleaned up its
      // temp file — the directory holds only the original backup.
      expect(await target.readAsString(), 'GOOD');
      expect(_entryNames(dir), unorderedEquals(['backup.json']));
    });

    test(
      'atomically replaces an existing file with the new contents',
      () async {
        final target = File('${dir.path}/backup.json');
        await target.writeAsString('OLD');

        await writeStringAtomically(target.path, 'NEW');

        expect(await target.readAsString(), 'NEW');
        expect(_entryNames(dir), unorderedEquals(['backup.json']));
      },
    );

    test('creates the target when it does not already exist', () async {
      final target = File('${dir.path}/fresh-backup.json');
      expect(await target.exists(), isFalse);

      await writeStringAtomically(target.path, 'HELLO');

      expect(await target.readAsString(), 'HELLO');
      expect(_entryNames(dir), unorderedEquals(['fresh-backup.json']));
    });

    test(
      'does not follow a symlink pre-planted at the legacy <path>.tmp name '
      '(CWE-59 regression)',
      () async {
        final target = File('${dir.path}/backup.json');
        await target.writeAsString('GOOD');

        // A local attacker pre-plants a symlink at the OLD, predictable temp
        // path, pointing at a file they want the write to clobber.
        final canary = File('${dir.path}/canary.txt');
        await canary.writeAsString('DO-NOT-TOUCH');
        await Link('${target.path}.tmp').create(canary.path);

        await writeStringAtomically(target.path, 'NEW');

        // The write went to an unpredictable sibling and renamed over the
        // target, never through the planted link — so the canary is untouched.
        // (A regression to the fixed `<path>.tmp` name would overwrite the
        // canary with 'NEW'.)
        expect(await target.readAsString(), 'NEW');
        expect(await canary.readAsString(), 'DO-NOT-TOUCH');
      },
      // `Link.create` needs symlink privilege on Windows; the POSIX CI runner
      // exercises this guard.
      skip: Platform.isWindows
          ? 'symlink creation requires privilege on Windows'
          : false,
    );

    test('round-trips: a file written atomically reads back via '
        'readBackupFile', () async {
      const contents = '{"backupVersion":1,"core":{"dances":[]}}';
      final target = File('${dir.path}/roundtrip.json');

      await writeStringAtomically(target.path, contents);

      expect(await readBackupFile(XFile(target.path)), contents);
    });
  });

  group('writeDesktopBackup (platform routing)', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('backup_io_desktop_test');
    });

    tearDown(() async {
      // Restore the seam so routing never leaks between tests.
      isMacOsPlatform = () => Platform.isMacOS;
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test(
      'non-macOS routes through the atomic writer: an interrupted write leaves '
      'the previous good backup intact and no .tmp litter',
      () async {
        isMacOsPlatform = () => false;
        final target = File('${dir.path}/backup.json');
        await target.writeAsString('GOOD');

        // The failure fires after the temp file is written but before the
        // rename — exactly where a naive in-place overwrite would already have
        // clobbered the previous good backup.
        await expectLater(
          writeDesktopBackup(
            target.path,
            'NEW-BUT-DOOMED',
            debugSimulateFailure: () async =>
                throw const FileSystemException('simulated write failure'),
          ),
          throwsA(isA<FileSystemException>()),
        );

        // Proves Windows/Linux went through writeStringAtomically: the prior
        // backup survives and no temp file is left behind. A regression that
        // routed non-macOS to the direct write would complete without throwing
        // and leave 'NEW-BUT-DOOMED' here.
        expect(await target.readAsString(), 'GOOD');
        expect(_entryNames(dir), unorderedEquals(['backup.json']));
      },
    );

    test(
      'non-macOS replaces the file and leaves no temp litter on success',
      () async {
        isMacOsPlatform = () => false;
        final target = File('${dir.path}/backup.json');
        await target.writeAsString('OLD');

        await writeDesktopBackup(target.path, 'NEW');

        expect(await target.readAsString(), 'NEW');
        expect(_entryNames(dir), unorderedEquals(['backup.json']));
      },
    );

    test(
      'macOS routes to the in-place write, bypassing the atomic seam',
      () async {
        isMacOsPlatform = () => true;
        final target = File('${dir.path}/backup.json');
        await target.writeAsString('GOOD');

        // The in-place macOS path ignores debugSimulateFailure, so the write
        // completes and overwrites the target. A regression that routed macOS
        // through the atomic writer would honor the seam and throw here (and
        // preserve 'GOOD'), failing this test.
        await writeDesktopBackup(
          target.path,
          'NEW',
          debugSimulateFailure: () async =>
              throw const FileSystemException('must not fire on macOS'),
        );

        expect(await target.readAsString(), 'NEW');
      },
    );
  });

  group('writeStringToUserSelectedPath', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp(
        'backup_io_selected_path_test',
      );
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test(
      'writes directly to the selected path without creating a sibling',
      () async {
        final target = File('${dir.path}/backup.json');

        await writeStringToUserSelectedPath(target.path, 'BACKUP');

        expect(await target.readAsString(), 'BACKUP');
        expect(await File('${target.path}.tmp').exists(), isFalse);
      },
    );

    test(
      'overwrites the selected file when sibling creation is denied',
      () async {
        final target = File('${dir.path}/backup.json');
        await target.writeAsString('OLD');

        final chmod = await Process.run('chmod', ['0500', dir.path]);
        expect(chmod.exitCode, 0, reason: '${chmod.stderr}');

        // Prove the directory is no longer writable for new siblings (what this
        // regression guard relies on).
        final sibling = File('${target.path}.tmp');
        await expectLater(
          sibling.writeAsString('SHOULD-NOT-WRITE'),
          throwsA(isA<FileSystemException>()),
        );
        expect(await sibling.exists(), isFalse);

        try {
          await writeStringToUserSelectedPath(target.path, 'BACKUP');
        } finally {
          final restore = await Process.run('chmod', ['0700', dir.path]);
          expect(restore.exitCode, 0, reason: '${restore.stderr}');
        }

        expect(await target.readAsString(), 'BACKUP');
      },
      skip: Platform.isWindows,
    );
  });
}
