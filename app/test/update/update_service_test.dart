import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

/// A fetcher seam that returns a canned body as raw UTF-8 bytes (or null)
/// regardless of channel — mirroring the production fetcher, which now returns
/// the exact wire bytes so the signature is verified over them.
UpdateManifestFetcher _fixedFetcher(String? body) =>
    (channel, {http.Client? client}) async =>
        body == null ? null : utf8.encode(body);

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

    test('verifies over the exact wire bytes for a non-ASCII manifest '
        '(regression: no latin1 re-encode)', () async {
      // A legitimate manifest whose bytes contain a UTF-8 multibyte sequence
      // (é = 0xC3 0xA9, in the release-notes fragment). CI signs the exact
      // file bytes; the client must verify over those same bytes.
      final body = _manifest().replaceFirst(
        '/releases/tag/v0.2.0',
        '/releases/tag/v0.2.0#caf\u00e9',
      );
      expect(body.contains('caf\u00e9'), isTrue);

      final signed = utf8.encode(body);
      final sig = base64.encode(
        (await algorithm.sign(signed, keyPair: keyPair)).bytes,
      );

      // End-to-end through the service (fetcher returns the exact bytes):
      // a correct signature over a newer manifest yields the update.
      final result = await checkWith(body, sig);
      expect(result, isNotNull);
      expect(result!.version.toString(), '0.2.0');

      // Prove the OLD bug would have broken this: package:http may decode the
      // body as latin1 when no charset is sent; re-encoding that String as
      // UTF-8 yields DIFFERENT bytes that no longer verify. This is exactly
      // the failure the raw-bytes fetcher avoids.
      final reencoded = utf8.encode(latin1.decode(signed));
      expect(reencoded, isNot(equals(signed)));
      expect(
        await verifyManifestSignatureWith(
          reencoded,
          sig,
          publicKeyBase64: pinnedKeyBase64,
        ),
        isFalse,
      );
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

  group('fetchUpdateManifest — bounded streamed read (OWASP A08)', () {
    test('returns the body via a streamed 200 response', () async {
      final manifestBytes = utf8.encode(_manifest());
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream<List<int>>.value(manifestBytes),
          200,
        );
      });
      final body = await fetchUpdateManifest(
        UpdateChannel.stable,
        client: client,
      );
      expect(body, manifestBytes);
    });

    test('aborts early without buffering an over-cap body', () async {
      const chunk = 64 * 1024; // 64 KiB per chunk; cap is 256 KiB.
      var produced = 0;
      // A stream that would yield far more than the cap if fully read. The
      // fetcher must stop pulling once the running total exceeds the cap, so
      // only a handful of chunks are ever produced.
      Stream<List<int>> huge() async* {
        for (var i = 0; i < 1000; i++) {
          produced += chunk;
          yield Uint8List(chunk);
        }
      }

      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(huge(), 200);
      });
      final body = await fetchUpdateManifest(
        UpdateChannel.stable,
        client: client,
      );
      expect(body, isNull);
      // Early abort: far fewer bytes were produced than the full 64 MiB body
      // (a few chunks past the 256 KiB cap, not the whole stream).
      expect(produced, lessThan(1024 * 1024));
      expect(produced, lessThan(1000 * chunk));
    });

    test(
      'accepts a body exactly at the cap and rejects one byte over',
      () async {
        final atCap = Uint8List(kMaxManifestBytes)..fillRange(0, 1, 0x7b);
        final atCapClient = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(Stream<List<int>>.value(atCap), 200);
        });
        expect(
          await fetchUpdateManifest(UpdateChannel.stable, client: atCapClient),
          hasLength(kMaxManifestBytes),
        );

        final overCap = Uint8List(kMaxManifestBytes + 1)..fillRange(0, 1, 0x7b);
        final overClient = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(Stream<List<int>>.value(overCap), 200);
        });
        expect(
          await fetchUpdateManifest(UpdateChannel.stable, client: overClient),
          isNull,
        );
      },
    );
  });

  group('fetchUpdateManifestSignature — bounded streamed read', () {
    test('returns the trimmed signature text via a streamed 200', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('c2lnbmF0dXJl\n')),
          200,
        );
      });
      final sig = await fetchUpdateManifestSignature(
        UpdateChannel.stable,
        client: client,
      );
      expect(sig, 'c2lnbmF0dXJl\n');
    });

    test('returns null for an over-cap signature body', () async {
      final overCap = Uint8List(kMaxSignatureBytes + 1)..fillRange(0, 1, 0x41);
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream<List<int>>.value(overCap), 200);
      });
      expect(
        await fetchUpdateManifestSignature(
          UpdateChannel.stable,
          client: client,
        ),
        isNull,
      );
    });

    test('aborts early without buffering an over-cap signature', () async {
      const chunk = 2 * 1024; // 2 KiB per chunk; cap is 4 KiB.
      var produced = 0;
      Stream<List<int>> huge() async* {
        for (var i = 0; i < 1000; i++) {
          produced += chunk;
          yield Uint8List(chunk);
        }
      }

      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(huge(), 200);
      });
      expect(
        await fetchUpdateManifestSignature(
          UpdateChannel.stable,
          client: client,
        ),
        isNull,
      );
      expect(produced, lessThan(1000 * chunk));
    });
  });

  group('fetchUpdateManifest — redirect validation (issue #784)', () {
    // Builds a MockClient that serves one redirect then the final response.
    // The mock sees exactly the requests as sendManifestFollowingHttpsRedirects issues
    // them (each with followRedirects=false), so a 301 to redirectTarget lands
    // on the final handler which returns a 200 with [finalHandler].
    MockClient makeRedirectingClient({
      required String redirectTarget,
      required http.StreamedResponse Function(http.BaseRequest) finalHandler,
    }) {
      return MockClient.streaming((request, _) async {
        if (request.url.host == Uri.parse(redirectTarget).host &&
            request.url.path == Uri.parse(redirectTarget).path) {
          return finalHandler(request);
        }
        // First hop: return a 301 pointing at redirectTarget.
        return http.StreamedResponse(
          Stream<List<int>>.value([]),
          301,
          headers: {'location': redirectTarget},
        );
      });
    }

    test(
      'follows the live redirect ibanner56.github.io → callerscompendium.com '
      'and returns the body',
      () async {
        // This is the real redirect chain every installed client takes:
        // kUpdateManifestBaseUrl (ibanner56.github.io) 301s to the custom
        // Pages domain (callerscompendium.com). Both hosts are in
        // kAllowedArtifactHosts; the redirect must be followed.
        final manifestBytes = utf8.encode(_manifest());
        final client = makeRedirectingClient(
          redirectTarget:
              'https://callerscompendium.com/CallersCompendium/stable.json',
          finalHandler: (_) => http.StreamedResponse(
            Stream<List<int>>.value(manifestBytes),
            200,
          ),
        );
        final body = await fetchUpdateManifest(
          UpdateChannel.stable,
          client: client,
        );
        expect(body, manifestBytes);
      },
    );

    test('refuses a redirect to a disallowed host and returns null', () async {
      // The mock serves a 301 → evil.example.com, then a real 200 at that host.
      // With the guard, sendManifestFollowingHttpsRedirects throws before following,
      // so the result is null. Without the guard (the mutation target) it would
      // follow and return the body, falsifying this expect.
      final body = utf8.encode(_manifest());
      final client = MockClient.streaming((request, _) async {
        if (request.url.host == 'evil.example.com') {
          return http.StreamedResponse(Stream<List<int>>.value(body), 200);
        }
        return http.StreamedResponse(
          Stream<List<int>>.value([]),
          301,
          headers: {'location': 'https://evil.example.com/manifest.json'},
        );
      });
      expect(
        await fetchUpdateManifest(UpdateChannel.stable, client: client),
        isNull,
      );
    });

    test(
      'refuses a scheme downgrade (https → http) even to an allowed host',
      () async {
        // The mock serves a 301 → http://callerscompendium.com, then a 200 at
        // that downgraded URL. With the guard this returns null (the downgrade
        // fails isAllowedArtifactHost because the scheme is http, not https).
        // Without the guard it returns the body, falsifying this expect.
        final body = utf8.encode(_manifest());
        final client = MockClient.streaming((request, _) async {
          if (!request.url.isScheme('https')) {
            return http.StreamedResponse(Stream<List<int>>.value(body), 200);
          }
          return http.StreamedResponse(
            Stream<List<int>>.value([]),
            301,
            headers: {'location': 'http://callerscompendium.com/stable.json'},
          );
        });
        expect(
          await fetchUpdateManifest(UpdateChannel.stable, client: client),
          isNull,
        );
      },
    );

    test('returns null when the redirect hop cap is exceeded', () async {
      // Every response is a redirect, so the cap fires after kMaxArtifactRedirects
      // hops and the helper throws → silent null.
      var hops = 0;
      final client = MockClient.streaming((request, _) async {
        hops++;
        return http.StreamedResponse(
          Stream<List<int>>.value([]),
          301,
          headers: {
            'location':
                'https://ibanner56.github.io/CallersCompendium/stable.json',
          },
        );
      });
      expect(
        await fetchUpdateManifest(UpdateChannel.stable, client: client),
        isNull,
      );
      // Cap is kMaxArtifactRedirects (5); we expect exactly cap+1 requests
      // (initial + cap hops before the exception is thrown).
      expect(hops, kMaxArtifactRedirects + 1);
    });

    test(
      'upfront guard: disallowed initial host throws before any request is made',
      () async {
        // sendManifestFollowingHttpsRedirects validates the initial URI before
        // the first client.send() call, mirroring downloadArtifact's upfront
        // guard. The mock would return a 200 if reached; the guard must throw
        // first so it is never called.
        //
        // This test distinguishes "guards every request" from "guards only
        // redirect targets". Mutation target: remove the upfront
        // isAllowedArtifactHost(uri) check and confirm requestsMade > 0.
        var requestsMade = 0;
        final client = MockClient.streaming((request, _) async {
          requestsMade++;
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(_manifest())),
            200,
          );
        });
        final disallowedUri = Uri.parse('https://evil.example.com/stable.json');
        await expectLater(
          sendManifestFollowingHttpsRedirects(client, disallowedUri),
          throwsA(isA<Exception>()),
        );
        expect(requestsMade, 0);
      },
    );
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
