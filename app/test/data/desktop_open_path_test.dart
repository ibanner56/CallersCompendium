import 'dart:io';

import 'package:compendium_app/src/data/desktop_open_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The path check in front of desktop file opens (PLAT-3). Any local process
/// can send the single-instance channel an `open` line, so each refusal here
/// is a security boundary: each has its own test.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('desktop_open_path_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  String inDir(String name) => p.join(dir.path, name);

  File shareFile(String name, {int bytes = 16}) =>
      File(inDir(name))..writeAsBytesSync(List<int>.filled(bytes, 0x20));

  Future<DesktopOpenRejection?> rejectionOf(
    String path, {
    int? maxBytes,
  }) async {
    final check = maxBytes == null
        ? await checkDesktopOpenPath(path)
        : await checkDesktopOpenPath(path, maxBytes: maxBytes);
    return check.rejection;
  }

  group('checkDesktopOpenPath accepts', () {
    test('a local regular .ccshare file, returning the same path', () async {
      final file = shareFile('Contra Night.ccshare');

      final check = await checkDesktopOpenPath(file.path);

      expect(check.rejection, isNull);
      expect(check.path, file.path);
    });

    test('the extension in any case', () async {
      final file = shareFile('LOUD.CCSHARE');

      expect(await rejectionOf(file.path), isNull);
    });

    test('a file of exactly the size cap', () async {
      final file = shareFile('edge.ccshare', bytes: 32);

      expect(await rejectionOf(file.path, maxBytes: 32), isNull);
    });
  });

  group('checkDesktopOpenPath refuses', () {
    test('an empty path', () async {
      expect(await rejectionOf(''), DesktopOpenRejection.malformed);
    });

    test('a path with a control character', () async {
      final file = shareFile('ok.ccshare');
      for (final bad in [
        '${file.path}\n',
        '${dir.path}/a\nb.ccshare',
        '${dir.path}/a\u0000.ccshare',
        '${dir.path}/a\r.ccshare',
        '${dir.path}/a\u007f.ccshare',
      ]) {
        expect(
          await rejectionOf(bad),
          DesktopOpenRejection.malformed,
          reason: bad,
        );
      }
    });

    test('a UNC or device path', () async {
      for (final remote in [
        r'\\attacker\share\x.ccshare',
        r'\\?\C:\x.ccshare',
        r'\\.\pipe\x.ccshare',
        '//attacker/share/x.ccshare',
      ]) {
        expect(
          await rejectionOf(remote),
          DesktopOpenRejection.remote,
          reason: remote,
        );
      }
    });

    test('a relative path', () async {
      for (final relative in ['x.ccshare', './x.ccshare', '../x.ccshare']) {
        expect(
          await rejectionOf(relative),
          DesktopOpenRejection.notAbsolute,
          reason: relative,
        );
      }
    });

    test('any other extension, including one hidden behind .ccshare', () async {
      for (final name in [
        'backup.json',
        'x.ccshare.txt',
        'x.ccshare.',
        'x.ccshare:stream',
        'ccshare',
      ]) {
        final file = shareFile(name);
        expect(
          await rejectionOf(file.path),
          DesktopOpenRejection.wrongExtension,
          reason: name,
        );
      }
    });

    test('a missing file', () async {
      expect(
        await rejectionOf(inDir('gone.ccshare')),
        DesktopOpenRejection.notRegularFile,
      );
    });

    test('a directory named like a share file', () async {
      final folder = Directory(inDir('folder.ccshare'))..createSync();

      expect(
        await rejectionOf(folder.path),
        DesktopOpenRejection.notRegularFile,
      );
    });

    test(
      'a symlink, even to a valid share file',
      () async {
        final target = shareFile('real.ccshare');
        final link = Link(inDir('link.ccshare'))..createSync(target.path);

        expect(
          await rejectionOf(link.path),
          DesktopOpenRejection.notRegularFile,
        );
      },
      skip: Platform.isWindows ? 'symlinks need a privilege on Windows' : null,
    );

    test('a symlink to a device', () async {
      final link = Link(inDir('zero.ccshare'))..createSync('/dev/zero');

      expect(await rejectionOf(link.path), DesktopOpenRejection.notRegularFile);
    }, skip: Platform.isWindows ? 'no /dev/zero on Windows' : null);

    test('a named pipe, which would block the read forever', () async {
      final fifo = inDir('pipe.ccshare');
      final made = await Process.run('mkfifo', [fifo]);
      expect(made.exitCode, 0, reason: '${made.stderr}');

      expect(await rejectionOf(fifo), DesktopOpenRejection.notRegularFile);
    }, skip: Platform.isWindows ? 'no mkfifo on Windows' : null);

    test('a file over the size cap', () async {
      final file = shareFile('big.ccshare', bytes: 33);

      expect(
        await rejectionOf(file.path, maxBytes: 32),
        DesktopOpenRejection.tooLarge,
      );
    });
  });

  // The Windows rules, checked on any host through a Windows path context.
  // Every refusal here happens before the file system is touched, which is
  // the point for the remote forms: a stat would already contact the host.
  group('checkDesktopOpenPath with Windows paths refuses', () {
    final windows = p.Context(style: p.Style.windows, current: r'C:\work');

    Future<DesktopOpenRejection?> windowsRejection(String path) async =>
        (await checkDesktopOpenPath(path, context: windows)).rejection;

    test('two leading separators in any mix, and the NT prefix', () async {
      for (final remote in [
        r'\\host\share\x.ccshare',
        r'//host/share/x.ccshare',
        r'/\host\share\x.ccshare',
        r'\/host\share\x.ccshare',
        r'\\?\UNC\host\share\x.ccshare',
        r'\??\UNC\host\share\x.ccshare',
      ]) {
        expect(
          await windowsRejection(remote),
          DesktopOpenRejection.remote,
          reason: remote,
        );
      }
    });

    test('a root-relative or drive-relative path', () async {
      for (final relative in [r'\x.ccshare', '/x.ccshare', r'C:x.ccshare']) {
        expect(
          await windowsRejection(relative),
          DesktopOpenRejection.notAbsolute,
          reason: relative,
        );
      }
    });

    test('an alternate data stream', () async {
      expect(
        await windowsRejection(r'C:\a\evil.exe:x.ccshare'),
        DesktopOpenRejection.malformed,
      );
    });

    test('a reserved device name', () async {
      for (final name in [
        'COM1',
        'nul',
        'Con ',
        'LPT9.x',
        r'CONIN$',
        'COM¹',
        'lpt³',
      ]) {
        expect(
          await windowsRejection('C:\\a\\$name.ccshare'),
          DesktopOpenRejection.deviceName,
          reason: name,
        );
      }
    });

    test('nothing else about a plain drive path', () async {
      // Passes every string rule, so it reaches the file system, where this
      // host has no such file.
      for (final ok in [r'C:\a\COMPANY.ccshare', r'd:/a/x.CCSHARE']) {
        expect(
          await windowsRejection(ok),
          DesktopOpenRejection.notRegularFile,
          reason: ok,
        );
      }
    });
  });

  group('desktopOpenPathFromArgs', () {
    test('picks the .ccshare argument and makes it absolute', () {
      final path = desktopOpenPathFromArgs([
        '--verbose',
        'notes.txt',
        'sub/../Contra Night.CCSHARE',
      ], platformOpensArgs: true);

      expect(path, p.join(Directory.current.path, 'Contra Night.CCSHARE'));
    });

    test('returns null with no share-file argument', () {
      expect(
        desktopOpenPathFromArgs(['notes.txt'], platformOpensArgs: true),
        isNull,
      );
      expect(desktopOpenPathFromArgs([], platformOpensArgs: true), isNull);
    });

    test(
      'ignores arguments where the platform does not pass files (macOS)',
      () {
        expect(
          desktopOpenPathFromArgs(['/x.ccshare'], platformOpensArgs: false),
          isNull,
        );
      },
    );

    test('reads arguments on Windows and Linux only', () {
      expect(
        desktopOpenPathFromArgs(['/x.ccshare']) != null,
        Platform.isWindows || Platform.isLinux,
      );
    });
  });
}
