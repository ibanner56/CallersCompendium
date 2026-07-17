import 'dart:io';

import 'package:compendium_app/src/update/artifact_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// sha256("hello") — the well-known digest, lowercase hex.
const _helloSha256 =
    '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

void main() {
  group('constantTimeHexEquals', () {
    test('equal lowercase hex matches', () {
      expect(constantTimeHexEquals(_helloSha256, _helloSha256), isTrue);
    });

    test('comparison is case-insensitive', () {
      expect(
        constantTimeHexEquals(_helloSha256, _helloSha256.toUpperCase()),
        isTrue,
      );
    });

    test('a single differing character fails', () {
      final tampered = 'f${_helloSha256.substring(1)}';
      expect(constantTimeHexEquals(_helloSha256, tampered), isFalse);
    });

    test('a length mismatch fails', () {
      expect(constantTimeHexEquals(_helloSha256, 'abc'), isFalse);
      expect(constantTimeHexEquals('', _helloSha256), isFalse);
    });
  });

  group('verifyArtifactSha256', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('verifier_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('passes when the file hashes to the expected sha256', () async {
      final file = File('${tempDir.path}/hello.bin');
      await file.writeAsString('hello');

      expect(await verifyArtifactSha256(file, _helloSha256), isTrue);
      // Case-insensitive against an uppercase manifest value.
      expect(
        await verifyArtifactSha256(file, _helloSha256.toUpperCase()),
        isTrue,
      );
    });

    test('fails when the content does not match the expected sha256', () async {
      final file = File('${tempDir.path}/hello.bin')
        ..writeAsStringSync('goodbye');
      expect(await verifyArtifactSha256(file, _helloSha256), isFalse);
    });

    test(
      'fails (does not throw) when the file is unreadable/missing',
      () async {
        final missing = File('${tempDir.path}/does-not-exist.bin');
        expect(await verifyArtifactSha256(missing, _helloSha256), isFalse);
      },
    );
  });
}
