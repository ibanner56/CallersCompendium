import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compendium_app/src/update/artifact_downloader.dart';
import 'package:compendium_app/src/update/artifact_handoff.dart';
import 'package:compendium_app/src/update/semver.dart';
import 'package:compendium_app/src/update/update_controller.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:compendium_app/src/update/update_service.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/test_repositories.dart';

const _stableManifest = '''
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
      "url": "https://example.com/app-0.2.0-linux-x64.AppImage",
      "sha256": "abcd",
      "size": 1000
    }
  ]
}
''';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'a channel switch during an in-flight check discards the stale result',
    () async {
      final repos = openTestRepositories();
      // The fetcher completes only when we choose, so we can flip channels
      // while the (stable) check is still in flight.
      final gate = Completer<List<int>?>();
      final controller = UpdateController(
        repos.settings,
        service: UpdateService(
          fetcher: (channel, {http.Client? client}) => gate.future,
          signatureFetcher: (channel, {http.Client? client}) async => "sig",
          signatureVerifier: (bytes, sig) async => true,
        ),
        currentVersion: SemVer.tryParse('0.1.0'),
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      addTearDown(controller.dispose);
      await controller.load();

      // Start a check on stable, then opt into beta before it resolves.
      final pending = controller.checkNow();
      expect(controller.status, UpdateCheckStatus.checking);
      await controller.setBetaChannel(true);
      expect(controller.channel, UpdateChannel.beta);
      expect(controller.status, UpdateCheckStatus.idle);

      // The in-flight stable check now completes with a newer stable manifest.
      gate.complete(utf8.encode(_stableManifest));
      await pending;

      // The stale cross-channel result must be dropped: no banner, and the
      // state still reflects the freshly-selected beta channel.
      expect(controller.foundUpdate, isNull);
      expect(controller.bannerUpdate, isNull);
      expect(controller.status, UpdateCheckStatus.idle);
    },
  );

  test('a check whose channel is unchanged applies its result', () async {
    final repos = openTestRepositories();
    final gate = Completer<List<int>?>();
    final controller = UpdateController(
      repos.settings,
      service: UpdateService(
        fetcher: (channel, {http.Client? client}) => gate.future,
        signatureFetcher: (channel, {http.Client? client}) async => 'sig',
        signatureVerifier: (bytes, sig) async => true,
      ),
      currentVersion: SemVer.tryParse('0.1.0'),
      platform: UpdatePlatform.linux,
      arch: UpdateArch.x64,
    );
    addTearDown(controller.dispose);
    await controller.load();

    final pending = controller.checkNow();
    gate.complete(utf8.encode(_stableManifest));
    await pending;

    expect(controller.status, UpdateCheckStatus.updateAvailable);
    expect(controller.foundUpdate, isNotNull);
    expect(controller.foundUpdate!.version.toString(), '0.2.0');
    expect(controller.bannerUpdate, isNotNull);
  });

  test('routes the assisted-download destination through a fresh, '
      'unpredictable subdirectory rather than a predictable temp-dir path '
      '(issue #626)', () async {
    final repos = openTestRepositories();
    final rootTemp = Directory.systemTemp.createTempSync('controller_root_');
    addTearDown(() => rootTemp.deleteSync(recursive: true));

    File? capturedDestination;
    final controller = UpdateController(
      repos.settings,
      service: UpdateService(
        fetcher: (channel, {http.Client? client}) async =>
            utf8.encode(_stableManifest),
        signatureFetcher: (channel, {http.Client? client}) async => 'sig',
        signatureVerifier: (bytes, sig) async => true,
      ),
      currentVersion: SemVer.tryParse('0.1.0'),
      platform: UpdatePlatform.linux,
      arch: UpdateArch.x64,
      temporaryDirectoryProvider: () async => rootTemp,
      downloader:
          (
            artifact, {
            required File destination,
            http.Client? client,
            void Function(DownloadProgress)? onProgress,
            DownloadCancelToken? cancelToken,
          }) async {
            capturedDestination = destination;
            await destination.writeAsString('artifact-bytes');
            return DownloadOutcome.success(destination);
          },
      verifier: (file, sha256) async => true,
      handoff: (file, platform) async => HandoffResult.revealed,
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.checkNow();
    expect(controller.canAssistDownload, isTrue);

    await controller.startAssistedDownload();

    expect(controller.downloadStatus, AssistedDownloadStatus.completed);
    final destination = capturedDestination;
    expect(destination, isNotNull);
    // The destination must NOT sit directly under the shared temp root at
    // a name derived only from the artifact URL (the old predictable
    // path a local attacker could pre-plant a symlink at) — it must be one
    // level deeper, inside a per-attempt subdirectory.
    expect(destination!.parent.path, isNot(rootTemp.path));
    expect(destination.parent.parent.path, rootTemp.path);
    expect(destination.path, endsWith('app-0.2.0-linux-x64.AppImage'));
    // The verified artifact (and its containing directory) are kept after
    // a successful handoff so the user can still reach it.
    expect(await destination.exists(), isTrue);
  });
}
