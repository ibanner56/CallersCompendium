import 'dart:async';
import 'dart:convert';

import 'package:compendium_app/src/update/semver.dart';
import 'package:compendium_app/src/update/update_config.dart';
import 'package:compendium_app/src/update/update_fetcher.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:compendium_app/src/update/update_service.dart';
import 'package:compendium_app/src/update/update_signature.dart';
import 'package:cryptography/cryptography.dart';
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

/// A signature fetcher that always returns a canned detached signature.
UpdateManifestSignatureFetcher _fixedSignatureFetcher(String? sig) =>
    (channel, {http.Client? client}) async => sig;

/// Builds an [UpdateService] whose signature gate is permissive by default, so
/// the comparison-logic tests exercise the version/parse behavior without
/// needing a real keypair. The signature-authenticity behavior is covered
/// explicitly in the "signature gate" group below.
UpdateService _service(
  String? body, {
  ManifestSignatureVerifier? verifier,
  String? signature = 'c2ln', // base64("sig") — value is irrelevant here
}) => UpdateService(
  fetcher: _fixedFetcher(body),
  signatureFetcher: _fixedSignatureFetcher(signature),
  signatureVerifier: verifier ?? (bytes, sig) async => true,
);

void main() {
  final current = SemVer.tryParse('0.1.0')!;

  group('UpdateService.check — comparison logic (fake fetcher)', () {
    test('returns an UpdateAvailable when the manifest is newer', () async {
      final service = _service(_manifest());
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
      final service = _service(_manifest(version: '0.1.0'));
      final result = await service.check(
        channel: UpdateChannel.stable,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      expect(result, isNull);
    });

    test('returns null when the manifest is older', () async {
      final service = _service(_manifest(version: '0.0.9'));
      final result = await service.check(
        channel: UpdateChannel.stable,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      expect(result, isNull);
    });

    test('returns null (no-op) when the fetch failed', () async {
      final service = _service(null);
      final result = await service.check(
        channel: UpdateChannel.stable,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      expect(result, isNull);
    });

    test('returns null (no-op) when the body is malformed', () async {
      final service = _service('not json');
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
      final service = _service(_manifest());
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
      final service = _service(body);
      final result = await service.check(
        channel: UpdateChannel.stable,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      expect(result, isNull);
    });
  });

  group('UpdateService.check — signature gate (real Ed25519 keypair)', () {
    // A real keypair signs the exact manifest bytes; the service is wired with
    // the production verifier but a *test* pinned key so we exercise the true
    // verification path end-to-end (issue #431).
    late Ed25519 algorithm;
    late SimpleKeyPair keyPair;
    late String pinnedKeyBase64;

    setUp(() async {
      algorithm = Ed25519();
      keyPair = await algorithm.newKeyPair();
      final pub = await keyPair.extractPublicKey();
      pinnedKeyBase64 = base64.encode(pub.bytes);
    });

    Future<String> signBase64(String body) async {
      final sig = await algorithm.sign(utf8.encode(body), keyPair: keyPair);
      return base64.encode(sig.bytes);
    }

    ManifestSignatureVerifier verifierForTestKey() =>
        (bytes, sig) => verifyManifestSignatureWith(
          bytes,
          sig,
          publicKeyBase64: pinnedKeyBase64,
        );

    Future<UpdateAvailable?> checkWith(String? body, String? signature) {
      final service = UpdateService(
        fetcher: _fixedFetcher(body),
        signatureFetcher: _fixedSignatureFetcher(signature),
        signatureVerifier: verifierForTestKey(),
      );
      return service.check(
        channel: UpdateChannel.stable,
        currentVersion: current,
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
    }

    test(
      'a valid signature over a newer manifest returns the update',
      () async {
        final body = _manifest();
        final result = await checkWith(body, await signBase64(body));
        expect(result, isNotNull);
        expect(result!.version.toString(), '0.2.0');
      },
    );

    test('an absent signature is refused (silent no-op)', () async {
      final body = _manifest();
      final result = await checkWith(body, null);
      expect(result, isNull);
    });

    test('a signature over different bytes is refused', () async {
      final body = _manifest();
      // Sign a *different* body, then serve the real one.
      final wrongSig = await signBase64(_manifest(version: '9.9.9'));
      final result = await checkWith(body, wrongSig);
      expect(result, isNull);
    });

    test('a malformed (non-base64) signature is refused', () async {
      final body = _manifest();
      final result = await checkWith(body, 'not*base64!!');
      expect(result, isNull);
    });

    test(
      'a valid signature over a not-newer manifest still returns null',
      () async {
        final body = _manifest(version: '0.1.0');
        final result = await checkWith(body, await signBase64(body));
        expect(result, isNull);
      },
    );

    test('a valid signature over a malformed manifest returns null', () async {
      const body = 'not json';
      final result = await checkWith(body, await signBase64(body));
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
