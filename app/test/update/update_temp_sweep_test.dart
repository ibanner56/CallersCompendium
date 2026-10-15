import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compendium_app/src/update/artifact_downloader.dart';
import 'package:compendium_app/src/update/artifact_handoff.dart';
import 'package:compendium_app/src/update/semver.dart';
import 'package:compendium_app/src/update/update_config.dart';
import 'package:compendium_app/src/update/update_controller.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:compendium_app/src/update/update_service.dart';
import 'package:compendium_app/src/update/update_temp_sweep.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/test_repositories.dart';

void main() {
  late Directory temp;

  // Every directory the tests create has a modification time of "now", so the
  // sweep is run with a clock [kUpdateTempDirMinAge] and a day past it: the
  // directories' own times are then old, and what keeps one alive is its
  // contents' time, which the tests set explicitly relative to this clock.
  late DateTime later;
  DateTime nowLater() => later;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('update_sweep_test_');
    later = DateTime.now().add(kUpdateTempDirMinAge + const Duration(days: 1));
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// A `cc_update_` directory holding one installer last written [age] before
  /// [later].
  Directory updateDir(String name, {required Duration age}) {
    final dir = Directory('${temp.path}/$name')..createSync();
    File('${dir.path}/installer.exe')
      ..writeAsStringSync('bytes')
      ..setLastModifiedSync(later.subtract(age));
    return dir;
  }

  group('sweepStaleUpdateTempDirs', () {
    test('removes a stale update directory and its installer', () async {
      final stale = updateDir(
        '${kUpdateTempDirPrefix}stale',
        age: kUpdateTempDirMinAge + const Duration(hours: 1),
      );

      final removed = await sweepStaleUpdateTempDirs(temp, now: nowLater);

      expect(removed, 1);
      expect(stale.existsSync(), isFalse);
    });

    test('keeps a directory whose installer was written recently, even though '
        'the directory itself is old (a download still in progress, or an '
        'installer just handed to the user)', () async {
      final fresh = updateDir(
        '${kUpdateTempDirPrefix}fresh',
        age: kUpdateTempDirMinAge - const Duration(hours: 1),
      );

      final removed = await sweepStaleUpdateTempDirs(temp, now: nowLater);

      expect(removed, 0);
      expect(fresh.existsSync(), isTrue);
      expect(File('${fresh.path}/installer.exe').existsSync(), isTrue);
    });

    test('keeps a directory created just now (the real clock)', () async {
      final justNow = Directory('${temp.path}/${kUpdateTempDirPrefix}new')
        ..createSync();

      final removed = await sweepStaleUpdateTempDirs(temp);

      expect(removed, 0);
      expect(justNow.existsSync(), isTrue);
    });

    test('treats a modification time in the future as recent', () async {
      final skewed = updateDir(
        '${kUpdateTempDirPrefix}skewed',
        age: -const Duration(days: 400),
      );

      final removed = await sweepStaleUpdateTempDirs(temp, now: nowLater);

      expect(removed, 0);
      expect(skewed.existsSync(), isTrue);
    });

    test('only touches directories named with the update prefix', () async {
      final stale = kUpdateTempDirMinAge + const Duration(days: 30);
      final others = <FileSystemEntity>[
        updateDir('other_app_cache', age: stale),
        updateDir('cc_update', age: stale),
        updateDir('cc_updat_x', age: stale),
        updateDir('x_${kUpdateTempDirPrefix}y', age: stale),
        File('${temp.path}/${kUpdateTempDirPrefix}file')
          ..writeAsStringSync('a file with the prefix is not ours')
          ..setLastModifiedSync(later.subtract(stale)),
      ];
      final ours = updateDir('${kUpdateTempDirPrefix}abc', age: stale);

      final removed = await sweepStaleUpdateTempDirs(temp, now: nowLater);

      expect(removed, 1);
      expect(ours.existsSync(), isFalse);
      for (final other in others) {
        expect(other.existsSync(), isTrue, reason: other.path);
      }
    });

    test(
      'never follows a symbolic link named like an update directory',
      () async {
        final outside = Directory.systemTemp.createTempSync('sweep_outside_');
        addTearDown(() => outside.deleteSync(recursive: true));
        final precious = File('${outside.path}/precious.txt')
          ..writeAsStringSync('keep')
          ..setLastModifiedSync(later.subtract(const Duration(days: 400)));
        try {
          Link(
            '${temp.path}/${kUpdateTempDirPrefix}link',
          ).createSync(outside.path);
        } on FileSystemException {
          markTestSkipped('this host cannot create symbolic links');
          return;
        }

        final removed = await sweepStaleUpdateTempDirs(temp, now: nowLater);

        expect(removed, 0);
        expect(precious.existsSync(), isTrue);
      },
    );

    test('a missing temp directory is not an error', () async {
      final gone = Directory('${temp.path}/does-not-exist');

      expect(await sweepStaleUpdateTempDirs(gone, now: nowLater), 0);
    });

    test('an entry that fails does not stop the sweep or throw', () async {
      final stale = kUpdateTempDirMinAge + const Duration(days: 1);
      final good = updateDir('${kUpdateTempDirPrefix}good', age: stale);
      final listing = _FixedListing([
        _BrokenUpdateDir('${kUpdateTempDirPrefix}broken'),
        good,
      ]);

      final removed = await sweepStaleUpdateTempDirs(listing, now: nowLater);

      expect(removed, 1, reason: 'the entry after the broken one is swept');
      expect(good.existsSync(), isFalse);
    });

    test('a temp directory that cannot be listed is not an error', () async {
      expect(
        await sweepStaleUpdateTempDirs(_UnlistableDir(), now: nowLater),
        0,
      );
    });
  });

  group('UpdateController.sweepStaleDownloads', () {
    UpdateController build(
      Future<Directory> Function() provider, {
      DateTime Function()? clock,
    }) {
      final repos = openTestRepositories();
      final controller = UpdateController(
        repos.settings,
        service: UpdateService(
          fetcher: (channel, {http.Client? client}) async => utf8.encode('{}'),
          signatureFetcher: (channel, {http.Client? client}) async => 'sig',
          signatureVerifier: (bytes, sig) async => true,
        ),
        currentVersion: SemVer.tryParse('0.1.0'),
        platform: UpdatePlatform.windows,
        arch: UpdateArch.x64,
        temporaryDirectoryProvider: provider,
        clock: clock,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    test('sweeps the temp directory the downloads are written to', () async {
      final stale = updateDir(
        '${kUpdateTempDirPrefix}stale',
        age: kUpdateTempDirMinAge + const Duration(hours: 1),
      );
      final fresh = updateDir(
        '${kUpdateTempDirPrefix}fresh',
        age: const Duration(hours: 1),
      );
      final controller = build(() async => temp, clock: nowLater);

      await controller.sweepStaleDownloads();

      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    test('a failing temp directory provider is swallowed', () async {
      final controller = build(() async => throw StateError('no temp dir'));

      await expectLater(controller.sweepStaleDownloads(), completes);
    });

    test('a download finished a moment ago survives the sweep', () async {
      final repos = openTestRepositories();
      final controller = UpdateController(
        repos.settings,
        service: UpdateService(
          fetcher: (channel, {http.Client? client}) async =>
              utf8.encode(_manifest()),
          signatureFetcher: (channel, {http.Client? client}) async => 'sig',
          signatureVerifier: (bytes, sig) async => true,
        ),
        currentVersion: SemVer.tryParse('0.1.0'),
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
        downloader:
            (
              artifact, {
              required destination,
              client,
              onProgress,
              cancelToken,
            }) async {
              await destination.writeAsString('artifact-bytes');
              return DownloadOutcome.success(destination);
            },
        verifier: (file, expected) async => true,
        handoff: (file, platform) async => HandoffResult.revealed,
        temporaryDirectoryProvider: () async => temp,
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.checkNow();
      await controller.startAssistedDownload();
      expect(controller.downloadStatus, AssistedDownloadStatus.completed);
      final dirs = temp
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains(kUpdateTempDirPrefix))
          .toList();
      expect(dirs, hasLength(1));

      await controller.sweepStaleDownloads();

      expect(dirs.single.existsSync(), isTrue);
      expect(dirs.single.listSync(), hasLength(1), reason: 'installer kept');
    });
  });
}

String _manifest() => '''
{
  "manifestSchemaVersion": 1,
  "channel": "stable",
  "version": "0.2.0",
  "releaseNotesUrl": "https://github.com/ibanner56/CallersCompendium/releases/tag/v0.2.0",
  "pubDate": "2026-08-01T00:00:00Z",
  "artifacts": [
    {
      "platform": "linux",
      "arch": "x64",
      "url": "https://release-assets.githubusercontent.com/CallersCompendium-0.2.0-linux-x64.AppImage",
      "sha256": "abcd",
      "size": 1000
    }
  ]
}
''';

/// A temp directory that lists exactly [_entries].
class _FixedListing implements Directory {
  _FixedListing(this._entries);
  final List<FileSystemEntity> _entries;

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream.fromIterable(_entries);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FixedListing.${invocation.memberName}');
}

/// A stale-looking update directory on which every filesystem call throws, as
/// a directory deleted or locked by another process mid-scan would.
class _BrokenUpdateDir implements Directory {
  _BrokenUpdateDir(this._name);
  final String _name;

  @override
  Uri get uri => Uri.directory('/tmp/$_name');

  @override
  Future<FileStat> stat() async =>
      throw const FileSystemException('vanished mid-scan');

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async =>
      throw const FileSystemException('in use');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_BrokenUpdateDir.${invocation.memberName}');
}

/// A temp directory whose listing fails.
class _UnlistableDir implements Directory {
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream<FileSystemEntity>.error(
    const FileSystemException('permission denied'),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_UnlistableDir.${invocation.memberName}');
}
