import 'dart:io';

import 'package:compendium_app/src/export/share_file.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Files handed to the share sheet are staged in one folder, which is emptied
/// before the next file is staged and at start, rather than straight after
/// the share sheet returns (the receiving app may not have read it yet).
void main() {
  late Directory temp;
  late Directory staging;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cc_share_staging_test');
    staging = await shareStagingDirectory(temporaryDirectory: () async => temp);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('the staging folder is its own folder in the temporary folder', () {
    expect(p.dirname(staging.path), temp.path);
    expect(p.basename(staging.path), kShareStagingFolderName);
    // share_plus refuses, on Android, a file already in its own cache folder.
    expect(kShareStagingFolderName, isNot(startsWith('share_plus')));
  });

  test('staging a file deletes the one staged before it, and nothing '
      'outside the folder', () async {
    final outside = File(p.join(temp.path, 'not-staged.txt'))
      ..writeAsStringSync('keep');
    final first = await writeBundleFile(
      'pay,100',
      'programs_2026-11-28.csv',
      getDir: () async => staging,
    );
    expect(File(first.path).existsSync(), isTrue);

    final second = await writeBundleFile(
      'BEGIN:VCALENDAR',
      'program.ics',
      getDir: () async => staging,
    );

    expect(File(first.path).existsSync(), isFalse);
    expect(File(second.path).readAsStringSync(), 'BEGIN:VCALENDAR');
    expect(outside.readAsStringSync(), 'keep');
  });

  test('clearing empties the folder, folders inside it too, and keeps '
      'the folder itself and everything beside it', () async {
    final outside = File(p.join(temp.path, 'beside.txt'))
      ..writeAsStringSync('keep');
    await writeBundleFile('{}', 'a.json', getDir: () async => staging);
    Directory(p.join(staging.path, 'nested')).createSync();
    File(p.join(staging.path, 'nested', 'b.json')).writeAsStringSync('{}');

    await clearShareStaging(stagingDirectory: () async => staging);

    expect(staging.existsSync(), isTrue);
    expect(staging.listSync(), isEmpty);
    expect(outside.readAsStringSync(), 'keep');
  });

  test('a staging folder that is a link is not followed or emptied', () async {
    final target = Directory(p.join(temp.path, 'someone-else'))..createSync();
    final theirs = File(p.join(target.path, 'keep.txt'))
      ..writeAsStringSync('keep');
    Link(staging.path).createSync(target.path);

    await clearShareStaging(stagingDirectory: () async => staging);

    expect(theirs.readAsStringSync(), 'keep');
  });

  group('clearLeftoverSharedFiles at start', () {
    late File staged;
    late File sharePlusCopy;
    setUp(() {
      resetLeftoverSharedFilesClearedForTesting();
      addTearDown(resetLeftoverSharedFilesClearedForTesting);
      staged = File(p.join(staging.path, 'backup.json'))
        ..createSync(recursive: true);
      sharePlusCopy = File(p.join(temp.path, 'share_plus', 'backup.json'))
        ..createSync(recursive: true);
    });

    test(
      'on Android, empties the staging folder and share_plus\'s copies',
      () async {
        await clearLeftoverSharedFiles(
          platform: TargetPlatform.android,
          temporaryDirectory: () async => temp,
        );
        expect(staged.existsSync(), isFalse);
        expect(sharePlusCopy.existsSync(), isFalse);
      },
    );

    test(
      'on iOS, macOS and Windows, empties the staging folder only',
      () async {
        for (final platform in [
          TargetPlatform.iOS,
          TargetPlatform.macOS,
          TargetPlatform.windows,
        ]) {
          staged.createSync(recursive: true);
          resetLeftoverSharedFilesClearedForTesting();
          await clearLeftoverSharedFiles(
            platform: platform,
            temporaryDirectory: () async => temp,
          );
          expect(staged.existsSync(), isFalse, reason: '$platform');
          expect(sharePlusCopy.existsSync(), isTrue, reason: '$platform');
        }
      },
    );

    // A Retry or a reset bootstraps again in the same process, maybe while
    // the app a file was just shared to is still reading it.
    test('only the first call in a process clears anything', () async {
      await clearLeftoverSharedFiles(
        platform: TargetPlatform.android,
        temporaryDirectory: () async => temp,
      );
      final justShared = File(p.join(temp.path, 'share_plus', 'recovery.db'))
        ..createSync(recursive: true);
      staged.createSync(recursive: true);

      await clearLeftoverSharedFiles(
        platform: TargetPlatform.android,
        temporaryDirectory: () async => temp,
      );

      expect(justShared.existsSync(), isTrue);
      expect(staged.existsSync(), isTrue);
    });

    test('on Linux, where nothing is staged, touches nothing', () async {
      await clearLeftoverSharedFiles(
        platform: TargetPlatform.linux,
        temporaryDirectory: () async => temp,
      );
      expect(staged.existsSync(), isTrue);
      expect(sharePlusCopy.existsSync(), isTrue);
    });
  });

  test('clearing a folder that is not there, or with no temporary folder, '
      'does nothing and does not throw', () async {
    await clearShareStaging(stagingDirectory: () async => staging);
    expect(staging.existsSync(), isFalse);

    await clearShareStaging(
      stagingDirectory: () async => throw const FileSystemException('none'),
    );
  });
}
