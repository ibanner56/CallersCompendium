import 'package:compendium_app/src/update/semver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SemVer.tryParse', () {
    test('parses a plain version', () {
      final v = SemVer.tryParse('1.2.3');
      expect(v, isNotNull);
      expect(v!.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
      expect(v.preRelease, isEmpty);
      expect(v.build, isEmpty);
      expect(v.isPreRelease, isFalse);
    });

    test('parses a pre-release with dotted identifiers', () {
      final v = SemVer.tryParse('0.2.0-rc.1');
      expect(v, isNotNull);
      expect(v!.preRelease, ['rc', '1']);
      expect(v.isPreRelease, isTrue);
    });

    test('parses and ignores build metadata for precedence', () {
      final a = SemVer.tryParse('1.0.0+build.5');
      final b = SemVer.tryParse('1.0.0+build.9');
      expect(a, isNotNull);
      expect(a!.build, 'build.5');
      // Build metadata never affects precedence (spec §10).
      expect(a.compareTo(b!), 0);
      expect(a == b, isTrue);
    });

    test('tolerates surrounding whitespace and a leading v', () {
      expect(SemVer.tryParse('  v1.2.3 ').toString(), '1.2.3');
      expect(SemVer.tryParse('V0.1.0')!.major, 0);
    });

    test('returns null for malformed input', () {
      for (final bad in <String>[
        '',
        '   ',
        '1',
        '1.2',
        '1.2.3.4',
        'a.b.c',
        '1.2.x',
        '1.2.-1',
        '01.2.3', // leading zero in core
        '1.2.3-', // empty pre-release
        '1.2.3+', // empty build
        '1.2.3-beta..1', // empty identifier
        '1.2.3-bet@', // illegal char
      ]) {
        expect(SemVer.tryParse(bad), isNull, reason: 'should reject "$bad"');
      }
    });
  });

  group('SemVer precedence', () {
    test('orders by major, minor, patch', () {
      expect(
        SemVer.tryParse('2.0.0')!.isNewerThan(SemVer.tryParse('1.9.9')!),
        isTrue,
      );
      expect(
        SemVer.tryParse('1.2.0')!.isNewerThan(SemVer.tryParse('1.1.9')!),
        isTrue,
      );
      expect(
        SemVer.tryParse('1.1.2')!.isNewerThan(SemVer.tryParse('1.1.1')!),
        isTrue,
      );
    });

    test('a release is newer than its pre-release (0.2.0-rc.1 < 0.2.0)', () {
      final rc = SemVer.tryParse('0.2.0-rc.1')!;
      final release = SemVer.tryParse('0.2.0')!;
      expect(release.isNewerThan(rc), isTrue);
      expect(rc.isNewerThan(release), isFalse);
      expect(rc.compareTo(release) < 0, isTrue);
    });

    test('orders pre-release identifiers per spec §11.4', () {
      // From the spec's canonical example chain.
      final chain = [
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-alpha.beta',
        '1.0.0-beta',
        '1.0.0-beta.2',
        '1.0.0-beta.11',
        '1.0.0-rc.1',
        '1.0.0',
      ].map((s) => SemVer.tryParse(s)!).toList();
      for (var i = 0; i < chain.length - 1; i++) {
        expect(
          chain[i + 1].isNewerThan(chain[i]),
          isTrue,
          reason: '${chain[i + 1]} should be newer than ${chain[i]}',
        );
      }
    });

    test('numeric pre-release identifiers compare numerically (2 < 11)', () {
      expect(
        SemVer.tryParse(
          '1.0.0-beta.11',
        )!.isNewerThan(SemVer.tryParse('1.0.0-beta.2')!),
        isTrue,
      );
    });

    test('numeric identifiers rank below alphanumeric ones', () {
      expect(
        SemVer.tryParse(
          '1.0.0-alpha.beta',
        )!.isNewerThan(SemVer.tryParse('1.0.0-alpha.1')!),
        isTrue,
      );
    });

    test('equal versions are neither newer', () {
      final a = SemVer.tryParse('1.2.3')!;
      final b = SemVer.tryParse('1.2.3')!;
      expect(a.isNewerThan(b), isFalse);
      expect(b.isNewerThan(a), isFalse);
      expect(a == b, isTrue);
    });
  });

  group('isNewerThan against the current app version', () {
    // kAppVersion is 0.1.0 today; use a fixed baseline so the test is stable
    // regardless of future bumps.
    final current = SemVer.tryParse('0.1.0')!;

    test('a higher published version is newer', () {
      expect(SemVer.tryParse('0.2.0')!.isNewerThan(current), isTrue);
      expect(SemVer.tryParse('1.0.0')!.isNewerThan(current), isTrue);
    });

    test('the same or a lower version is not newer', () {
      expect(SemVer.tryParse('0.1.0')!.isNewerThan(current), isFalse);
      expect(SemVer.tryParse('0.0.9')!.isNewerThan(current), isFalse);
      // A pre-release of the same version is older than the release.
      expect(SemVer.tryParse('0.1.0-rc.1')!.isNewerThan(current), isFalse);
    });
  });

  test('toString round-trips the canonical form', () {
    expect(SemVer.tryParse('1.2.3')!.toString(), '1.2.3');
    expect(SemVer.tryParse('0.2.0-rc.1')!.toString(), '0.2.0-rc.1');
    expect(
      SemVer.tryParse('1.0.0-beta+exp.sha.5')!.toString(),
      '1.0.0-beta+exp.sha.5',
    );
  });
}
