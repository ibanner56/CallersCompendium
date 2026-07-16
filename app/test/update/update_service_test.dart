import 'dart:async';

import 'package:compendium_app/src/update/semver.dart';
import 'package:compendium_app/src/update/update_config.dart';
import 'package:compendium_app/src/update/update_fetcher.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:compendium_app/src/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _manifest({String channel = 'stable', String version = '0.2.0'}) =>
    '''
{
  "manifestSchemaVersion": 1,
  "channel": "$channel",
  "version": "$version",
  "releaseNotesUrl": "https://github.com/ibanner56/CallersCompendium/releases/tag/v$version",
  "pubDate": "2026-08-01T00:00:00Z",
  "artifacts": [
    {
      "platform": "linux",
      "arch": "x64",
      "url": "https://example.com/app-$version-linux-x64.AppImage",
      "sha256": "abcd",
      "size": 1000
    }
  ]
}
''';

/// A fetcher seam that returns a canned body (or null) regardless of channel.
UpdateManifestFetcher _fixedFetcher(String? body) =>
    (channel, {http.Client? client}) async => body;

void main() {
  final current = SemVer.tryParse('0.1.0')!;

  group('UpdateService.check — comparison logic (fake fetcher)', () {
    test('returns an UpdateAvailable when the manifest is newer', () async {
      final service = UpdateService(fetcher: _fixedFetcher(_manifest()));
      final result = await service.check(
        channel: UpdateChannel.stable,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      expect(result, isNotNull);
      expect(result!.version.toString(), '0.2.0');
      expect(
        result.releaseNotesUrl,
        'https://github.com/ibanner56/CallersCompendium/releases/tag/v0.2.0',
      );
      expect(result.channel, UpdateChannel.stable);
      expect(result.artifact, isNotNull);
      expect(result.artifact!.platform, UpdatePlatform.linux);
    });

    test('returns null when the manifest is the same version', () async {
      final service = UpdateService(
        fetcher: _fixedFetcher(_manifest(version: '0.1.0')),
      );
      final result = await service.check(
        channel: UpdateChannel.stable,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      expect(result, isNull);
    });

    test('returns null when the manifest is older', () async {
      final service = UpdateService(
        fetcher: _fixedFetcher(_manifest(version: '0.0.9')),
      );
      final result = await service.check(
        channel: UpdateChannel.stable,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      expect(result, isNull);
    });

    test('returns null (no-op) when the fetch failed', () async {
      final service = UpdateService(fetcher: _fixedFetcher(null));
      final result = await service.check(
        channel: UpdateChannel.stable,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      expect(result, isNull);
    });

    test('returns null (no-op) when the body is malformed', () async {
      final service = UpdateService(fetcher: _fixedFetcher('not json'));
      final result = await service.check(
        channel: UpdateChannel.stable,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      expect(result, isNull);
    });

    test('returns null when the manifest channel disagrees', () async {
      // We request beta but the fetched body is a stable manifest.
      final service = UpdateService(fetcher: _fixedFetcher(_manifest()));
      final result = await service.check(
        channel: UpdateChannel.beta,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      expect(result, isNull);
    });

    test('returns null for an unsupported schema version', () async {
      final body = _manifest().replaceFirst(
        '"manifestSchemaVersion": 1',
        '"manifestSchemaVersion": 99',
      );
      final service = UpdateService(fetcher: _fixedFetcher(body));
      final result = await service.check(
        channel: UpdateChannel.stable,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      expect(result, isNull);
    });
  });

  group('fetchUpdateManifest — injected http.Client seam', () {
    test(
      'returns the body on a 200 and requests the bare channel URL',
      () async {
        late Uri requested;
        final client = MockClient((request) async {
          requested = request.url;
          return http.Response(_manifest(), 200);
        });
        final body = await fetchUpdateManifest(
          UpdateChannel.stable,
          client: client,
        );
        expect(body, isNotNull);
        // Privacy contract: the exact static URL, no query params appended.
        expect(
          requested.toString(),
          manifestUrlForChannel(UpdateChannel.stable),
        );
        expect(requested.hasQuery, isFalse);
        expect(requested.path.endsWith('/stable.json'), isTrue);
      },
    );

    test('fetches beta.json when the beta channel is requested', () async {
      late Uri requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(_manifest(channel: 'beta'), 200);
      });
      await fetchUpdateManifest(UpdateChannel.beta, client: client);
      expect(requested.path.endsWith('/beta.json'), isTrue);
    });

    test('returns null on a 404 (page not live yet)', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));
      expect(
        await fetchUpdateManifest(UpdateChannel.stable, client: client),
        isNull,
      );
    });

    test('returns null on a non-2xx server error', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      expect(
        await fetchUpdateManifest(UpdateChannel.stable, client: client),
        isNull,
      );
    });

    test('returns null on an empty 200 body', () async {
      final client = MockClient((_) async => http.Response('   ', 200));
      expect(
        await fetchUpdateManifest(UpdateChannel.stable, client: client),
        isNull,
      );
    });

    test('returns null when offline / the transport throws', () async {
      final client = MockClient(
        (_) async => throw const SocketExceptionLike('offline'),
      );
      expect(
        await fetchUpdateManifest(UpdateChannel.stable, client: client),
        isNull,
      );
    });

    test('returns null on a timeout', () async {
      final client = MockClient((_) async => throw TimeoutException('slow'));
      expect(
        await fetchUpdateManifest(UpdateChannel.stable, client: client),
        isNull,
      );
    });
  });
}

/// A stand-in transport error (avoids importing `dart:io` in a test that may
/// run on any platform); the fetcher's `on Object` catch treats any thrown
/// error as a silent no-op.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);
  final String message;
  @override
  String toString() => 'SocketExceptionLike: $message';
}
