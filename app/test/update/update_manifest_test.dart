import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// A well-formed stable manifest (ADR-002 §2) used as the happy-path baseline;
/// individual tests mutate a copy to exercise the failure branches.
const String _validStable = '''
{
  "manifestSchemaVersion": 1,
  "channel": "stable",
  "version": "0.2.0",
  "releaseNotesUrl": "https://github.com/ibanner56/CallersCompendium/releases/tag/v0.2.0",
  "pubDate": "2026-08-01T00:00:00Z",
  "artifacts": [
    {
      "platform": "macos",
      "arch": "universal",
      "url": "https://example.com/CallersCompendium-0.2.0-macos-universal.dmg",
      "sha256": "aaaa",
      "size": 12345678,
      "minOsVersion": "11.0"
    },
    {
      "platform": "windows",
      "arch": "x64",
      "url": "https://example.com/CallersCompendium-0.2.0-windows-x64.exe",
      "sha256": "bbbb",
      "size": 22222222
    },
    {
      "platform": "linux",
      "arch": "arm64",
      "url": "https://example.com/CallersCompendium-0.2.0-linux-arm64.AppImage",
      "sha256": "cccc",
      "size": 33333333
    }
  ]
}
''';

void main() {
  group('UpdateManifest.parse — happy path', () {
    test('parses all fields of a valid stable manifest', () {
      final m = UpdateManifest.parse(
        _validStable,
        expectedChannel: UpdateChannel.stable,
      );
      expect(m.manifestSchemaVersion, 1);
      expect(m.channel, UpdateChannel.stable);
      expect(m.version.toString(), '0.2.0');
      expect(
        m.releaseNotesUrl,
        'https://github.com/ibanner56/CallersCompendium/releases/tag/v0.2.0',
      );
      expect(m.pubDate.toUtc(), DateTime.utc(2026, 8, 1));
      expect(m.artifacts, hasLength(3));
      expect(m.artifacts.first.platform, UpdatePlatform.macos);
      expect(m.artifacts.first.arch, UpdateArch.universal);
      expect(m.artifacts.first.minOsVersion, '11.0');
      expect(m.artifacts[1].minOsVersion, isNull);
    });
  });

  group('UpdateManifest.parse — hard refusals', () {
    test('refuses an unknown manifestSchemaVersion', () {
      final json = _validStable.replaceFirst(
        '"manifestSchemaVersion": 1',
        '"manifestSchemaVersion": 2',
      );
      expect(
        () => UpdateManifest.parse(json, expectedChannel: UpdateChannel.stable),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('refuses a missing manifestSchemaVersion', () {
      final json = _validStable.replaceFirst('"manifestSchemaVersion": 1,', '');
      expect(
        () => UpdateManifest.parse(json, expectedChannel: UpdateChannel.stable),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('refuses a channel that disagrees with the requested one', () {
      // The file says stable, but we requested beta (e.g. fetched beta.json).
      expect(
        () => UpdateManifest.parse(
          _validStable,
          expectedChannel: UpdateChannel.beta,
        ),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('refuses an unknown channel string', () {
      final json = _validStable.replaceFirst(
        '"channel": "stable"',
        '"channel": "nightly"',
      );
      expect(
        () => UpdateManifest.parse(json, expectedChannel: UpdateChannel.stable),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('refuses an invalid version string', () {
      final json = _validStable.replaceFirst(
        '"version": "0.2.0"',
        '"version": "not-a-version"',
      );
      expect(
        () => UpdateManifest.parse(json, expectedChannel: UpdateChannel.stable),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('refuses an invalid pubDate', () {
      final json = _validStable.replaceFirst(
        '"pubDate": "2026-08-01T00:00:00Z"',
        '"pubDate": "last tuesday"',
      );
      expect(
        () => UpdateManifest.parse(json, expectedChannel: UpdateChannel.stable),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('refuses an empty artifacts list', () {
      final json = _validStable.replaceFirst(
        RegExp(r'"artifacts": \[.*\]', dotAll: true),
        '"artifacts": []',
      );
      expect(
        () => UpdateManifest.parse(json, expectedChannel: UpdateChannel.stable),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('refuses an artifact with an unknown platform', () {
      final json = _validStable.replaceFirst(
        '"platform": "macos"',
        '"platform": "solaris"',
      );
      expect(
        () => UpdateManifest.parse(json, expectedChannel: UpdateChannel.stable),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('refuses an artifact whose size is not an int', () {
      final json = _validStable.replaceFirst(
        '"size": 12345678',
        '"size": "big"',
      );
      expect(
        () => UpdateManifest.parse(json, expectedChannel: UpdateChannel.stable),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });
  });

  group('UpdateManifest.parse — malformed / partial JSON', () {
    test('refuses non-JSON text', () {
      expect(
        () => UpdateManifest.parse(
          '<html>404</html>',
          expectedChannel: UpdateChannel.stable,
        ),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('refuses a JSON array root', () {
      expect(
        () => UpdateManifest.parse('[]', expectedChannel: UpdateChannel.stable),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('refuses a truncated / partial object', () {
      const partial = '{"manifestSchemaVersion": 1, "channel": "stable"';
      expect(
        () => UpdateManifest.parse(
          partial,
          expectedChannel: UpdateChannel.stable,
        ),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });

    test('refuses a manifest missing required fields', () {
      const missing =
          '{"manifestSchemaVersion": 1, "channel": "stable", "version": "0.2.0"}';
      expect(
        () => UpdateManifest.parse(
          missing,
          expectedChannel: UpdateChannel.stable,
        ),
        throwsA(isA<UpdateManifestFormatException>()),
      );
    });
  });

  group('selectArtifact — client-side platform/arch match', () {
    final manifest = UpdateManifest.parse(
      _validStable,
      expectedChannel: UpdateChannel.stable,
    );

    test('exact platform+arch match wins', () {
      final a = manifest.selectArtifact(UpdatePlatform.windows, UpdateArch.x64);
      expect(a, isNotNull);
      expect(a!.platform, UpdatePlatform.windows);
      expect(a.arch, UpdateArch.x64);
    });

    test('universal artifact matches any requested arch on that platform', () {
      final a = manifest.selectArtifact(UpdatePlatform.macos, UpdateArch.arm64);
      expect(a, isNotNull);
      expect(a!.platform, UpdatePlatform.macos);
      expect(a.arch, UpdateArch.universal);
    });

    test('returns null when no artifact matches the platform', () {
      expect(
        manifest.selectArtifact(UpdatePlatform.android, UpdateArch.universal),
        isNull,
      );
    });

    test('returns null when the platform matches but the arch does not', () {
      // Only windows-x64 is published; asking for windows-arm64 finds nothing.
      expect(
        manifest.selectArtifact(UpdatePlatform.windows, UpdateArch.arm64),
        isNull,
      );
    });
  });
}
