import 'dart:async';
import 'dart:io';

import 'package:compendium_app/src/update/artifact_downloader.dart';
import 'package:compendium_app/src/update/artifact_handoff.dart';
import 'package:compendium_app/src/update/artifact_verifier.dart';
import 'package:compendium_app/src/update/semver.dart';
import 'package:compendium_app/src/update/update_controller.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:compendium_app/src/update/update_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/test_repositories.dart';

/// A stable manifest whose only artifact targets [platform]/[arch].
String _manifest({
  String platform = 'macos',
  String arch = 'universal',
  String version = '0.2.0',
}) =>
    '''
{
  "manifestSchemaVersion": 1,
  "channel": "stable",
  "version": "$version",
  "releaseNotesUrl": "https://github.com/ibanner56/CallersCompendium/releases/tag/v$version",
  "pubDate": "2026-08-01T00:00:00Z",
  "artifacts": [
    {
      "platform": "$platform",
      "arch": "$arch",
      "url": "https://example.com/CallersCompendium-$version-$platform-$arch.dmg",
      "sha256": "abcd",
      "size": 1000
    }
  ]
}
''';

class _HandoffCall {
  _HandoffCall(this.file, this.platform);
  final File file;
  final UpdatePlatform platform;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('assisted_dl_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Builds a controller wired to fake seams. [manifestBody] drives the check;
  /// [downloader]/[verifier]/[handoff] default to a succeeding happy path.
  UpdateController controller(
    CompendiumRepositories repos, {
    String? manifestBody,
    ArtifactDownloader? downloader,
    ArtifactVerifier? verifier,
    ArtifactHandoff? handoff,
    UpdatePlatform platform = UpdatePlatform.macos,
    UpdateArch arch = UpdateArch.universal,
  }) {
    return UpdateController(
      repos.settings,
      service: UpdateService(
        fetcher: (channel, {http.Client? client}) async => manifestBody,
      ),
      currentVersion: SemVer.tryParse('0.1.0'),
      platform: platform,
      arch: arch,
      downloader:
          downloader ??
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
      verifier: verifier ?? (file, expected) async => true,
      handoff: handoff ?? (file, platform) async => true,
      temporaryDirectoryProvider: () async => tempDir,
    );
  }

  test('happy path: download → verify → handoff → completed', () async {
    final repos = openTestRepositories();
    final handoffs = <_HandoffCall>[];
    final c = controller(
      repos,
      manifestBody: _manifest(),
      handoff: (file, platform) async {
        handoffs.add(_HandoffCall(file, platform));
        return true;
      },
    );
    addTearDown(c.dispose);
    await c.load();
    await c.checkNow();

    expect(c.canAssistDownload, isTrue);
    await c.startAssistedDownload();

    expect(c.downloadStatus, AssistedDownloadStatus.completed);
    expect(c.downloadError, isNull);
    expect(handoffs, hasLength(1));
    expect(handoffs.single.platform, UpdatePlatform.macos);
    expect(await handoffs.single.file.exists(), isTrue);
  });

  test('verify mismatch fails loudly, deletes the file, no handoff', () async {
    final repos = openTestRepositories();
    File? captured;
    final handoffs = <_HandoffCall>[];
    final c = controller(
      repos,
      manifestBody: _manifest(),
      downloader:
          (
            artifact, {
            required destination,
            client,
            onProgress,
            cancelToken,
          }) async {
            captured = destination;
            await destination.writeAsString('tampered');
            return DownloadOutcome.success(destination);
          },
      verifier: (file, expected) async => false,
      handoff: (file, platform) async {
        handoffs.add(_HandoffCall(file, platform));
        return true;
      },
    );
    addTearDown(c.dispose);
    await c.load();
    await c.checkNow();

    await c.startAssistedDownload();

    expect(c.downloadStatus, AssistedDownloadStatus.failed);
    expect(c.downloadError, isNotNull);
    expect(c.downloadError, contains('security'));
    expect(handoffs, isEmpty);
    expect(await captured!.exists(), isFalse); // deleted by the gate
  });

  test('a network download error fails loudly (no handoff)', () async {
    final repos = openTestRepositories();
    final handoffs = <_HandoffCall>[];
    final c = controller(
      repos,
      manifestBody: _manifest(),
      downloader:
          (
            artifact, {
            required destination,
            client,
            onProgress,
            cancelToken,
          }) async => DownloadOutcome.networkError('offline'),
      handoff: (file, platform) async {
        handoffs.add(_HandoffCall(file, platform));
        return true;
      },
    );
    addTearDown(c.dispose);
    await c.load();
    await c.checkNow();

    await c.startAssistedDownload();

    expect(c.downloadStatus, AssistedDownloadStatus.failed);
    expect(c.downloadError, isNotNull);
    expect(handoffs, isEmpty);
  });

  test('a failed handoff surfaces an error but keeps the file', () async {
    final repos = openTestRepositories();
    final c = controller(
      repos,
      manifestBody: _manifest(),
      handoff: (file, platform) async => false,
    );
    addTearDown(c.dispose);
    await c.load();
    await c.checkNow();

    await c.startAssistedDownload();

    expect(c.downloadStatus, AssistedDownloadStatus.failed);
    expect(c.downloadError, contains('View release'));
  });

  test('cancel during download aborts to cancelled', () async {
    final repos = openTestRepositories();
    final gate = Completer<DownloadOutcome>();
    DownloadCancelToken? captured;
    final c = controller(
      repos,
      manifestBody: _manifest(),
      downloader:
          (artifact, {required destination, client, onProgress, cancelToken}) {
            captured = cancelToken;
            return gate.future;
          },
    );
    addTearDown(c.dispose);
    await c.load();
    await c.checkNow();

    final pending = c.startAssistedDownload();
    expect(c.downloadStatus, AssistedDownloadStatus.downloading);
    // Let the (async) temp-dir resolution run so the downloader is invoked and
    // captures the cancel token before we cancel.
    await Future<void>.delayed(Duration.zero);

    c.cancelDownload();
    expect(captured, isNotNull);
    expect(captured!.isCancelled, isTrue);

    gate.complete(DownloadOutcome.cancelled());
    await pending;

    expect(c.downloadStatus, AssistedDownloadStatus.cancelled);
    expect(c.downloadError, isNull);
  });

  test('mobile cannot assist-download (link only)', () async {
    final repos = openTestRepositories();
    var downloaderCalled = false;
    final c = controller(
      repos,
      manifestBody: _manifest(platform: 'android'),
      platform: UpdatePlatform.android,
      downloader:
          (
            artifact, {
            required destination,
            client,
            onProgress,
            cancelToken,
          }) async {
            downloaderCalled = true;
            return DownloadOutcome.success(destination);
          },
    );
    addTearDown(c.dispose);
    await c.load();
    await c.checkNow();

    expect(c.foundUpdate, isNotNull); // an update was still found
    expect(c.canAssistDownload, isFalse); // but no assisted download on mobile
    expect(c.downloadableArtifact, isNull);

    await c.startAssistedDownload(); // no-op
    expect(downloaderCalled, isFalse);
    expect(c.downloadStatus, AssistedDownloadStatus.idle);
  });

  test('a fresh check re-arms a terminal (failed) download state', () async {
    final repos = openTestRepositories();
    final c = controller(
      repos,
      manifestBody: _manifest(),
      handoff: (file, platform) async => false, // force a failure
    );
    addTearDown(c.dispose);
    await c.load();
    await c.checkNow();
    await c.startAssistedDownload();
    expect(c.downloadStatus, AssistedDownloadStatus.failed);

    // Re-checking clears the terminal state so the affordance re-arms.
    await c.checkNow();
    expect(c.downloadStatus, AssistedDownloadStatus.idle);
    expect(c.downloadError, isNull);
  });

  test('resetDownload clears a terminal state to idle', () async {
    final repos = openTestRepositories();
    final c = controller(
      repos,
      manifestBody: _manifest(),
      handoff: (file, platform) async => false,
    );
    addTearDown(c.dispose);
    await c.load();
    await c.checkNow();
    await c.startAssistedDownload();
    expect(c.downloadStatus, AssistedDownloadStatus.failed);

    c.resetDownload();
    expect(c.downloadStatus, AssistedDownloadStatus.idle);
    expect(c.downloadError, isNull);
  });
}
