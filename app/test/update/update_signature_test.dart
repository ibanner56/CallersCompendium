import 'dart:convert';

import 'package:compendium_app/src/update/update_config.dart';
import 'package:compendium_app/src/update/update_signature.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

/// A freshly-generated Ed25519 test keypair plus a signature over [message],
/// all as the standard-base64 strings the verifier consumes.
class _SignedFixture {
  _SignedFixture({
    required this.publicKeyBase64,
    required this.signatureBase64,
    required this.message,
  });

  final String publicKeyBase64;
  final String signatureBase64;
  final List<int> message;
}

Future<_SignedFixture> _sign(String text) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final message = utf8.encode(text);
  final signature = await algorithm.sign(message, keyPair: keyPair);
  return _SignedFixture(
    publicKeyBase64: base64.encode(publicKey.bytes),
    signatureBase64: base64.encode(signature.bytes),
    message: message,
  );
}

void main() {
  group('verifyManifestSignatureWith', () {
    test('accepts a valid signature over the exact bytes', () async {
      final f = await _sign('{"manifestSchemaVersion":1}');
      final ok = await verifyManifestSignatureWith(
        f.message,
        f.signatureBase64,
        publicKeysBase64: [f.publicKeyBase64],
      );
      expect(ok, isTrue);
    });

    test('rejects a signature made by a different key', () async {
      final f = await _sign('payload');
      final other = await _sign('payload');
      final ok = await verifyManifestSignatureWith(
        f.message,
        f.signatureBase64,
        publicKeysBase64: [other.publicKeyBase64],
      );
      expect(ok, isFalse);
    });

    test('rejects a signature over tampered bytes', () async {
      final f = await _sign('the-real-manifest');
      final ok = await verifyManifestSignatureWith(
        utf8.encode('the-real-manifest-TAMPERED'),
        f.signatureBase64,
        publicKeysBase64: [f.publicKeyBase64],
      );
      expect(ok, isFalse);
    });

    test('fails closed on an empty pinned key', () async {
      final f = await _sign('x');
      final ok = await verifyManifestSignatureWith(
        f.message,
        f.signatureBase64,
        publicKeysBase64: [''],
      );
      expect(ok, isFalse);
    });

    test('fails closed on a null signature', () async {
      final f = await _sign('x');
      final ok = await verifyManifestSignatureWith(
        f.message,
        null,
        publicKeysBase64: [f.publicKeyBase64],
      );
      expect(ok, isFalse);
    });

    test('fails closed on an empty/whitespace signature', () async {
      final f = await _sign('x');
      expect(
        await verifyManifestSignatureWith(
          f.message,
          '',
          publicKeysBase64: [f.publicKeyBase64],
        ),
        isFalse,
      );
      expect(
        await verifyManifestSignatureWith(
          f.message,
          '   \n',
          publicKeysBase64: [f.publicKeyBase64],
        ),
        isFalse,
      );
    });

    test('rejects a non-base64 signature', () async {
      final f = await _sign('x');
      final ok = await verifyManifestSignatureWith(
        f.message,
        'not*valid*base64!!',
        publicKeysBase64: [f.publicKeyBase64],
      );
      expect(ok, isFalse);
    });

    test('rejects a non-base64 pinned key', () async {
      final f = await _sign('x');
      final ok = await verifyManifestSignatureWith(
        f.message,
        f.signatureBase64,
        publicKeysBase64: ['not*valid*base64!!'],
      );
      expect(ok, isFalse);
    });

    test('rejects a signature that is not exactly 64 bytes', () async {
      final f = await _sign('x');
      // 63 bytes and 65 bytes are both refused before touching the library.
      final short = base64.encode(List<int>.filled(63, 0));
      final long = base64.encode(List<int>.filled(65, 0));
      expect(
        await verifyManifestSignatureWith(
          f.message,
          short,
          publicKeysBase64: [f.publicKeyBase64],
        ),
        isFalse,
      );
      expect(
        await verifyManifestSignatureWith(
          f.message,
          long,
          publicKeysBase64: [f.publicKeyBase64],
        ),
        isFalse,
      );
    });

    test('rejects a pinned key that is not exactly 32 bytes', () async {
      final f = await _sign('x');
      final wrongKey = base64.encode(List<int>.filled(31, 0));
      final ok = await verifyManifestSignatureWith(
        f.message,
        f.signatureBase64,
        publicKeysBase64: [wrongKey],
      );
      expect(ok, isFalse);
    });

    test('tolerates surrounding whitespace on a valid signature', () async {
      final f = await _sign('trimmed');
      final ok = await verifyManifestSignatureWith(
        f.message,
        '  ${f.signatureBase64}\n',
        publicKeysBase64: [f.publicKeyBase64],
      );
      expect(ok, isTrue);
    });
  });

  // security-2: the client pins a SET of keys (current + next) so a signing-key
  // rotation never strands an install. A manifest is accepted when its
  // signature verifies against ANY pinned key; everything else fails closed.
  group('verifyManifestSignatureWith — pinned key set', () {
    test(
      'accepts a signature made by the SECOND key of a two-key set',
      () async {
        final current = await _sign('{"manifestSchemaVersion":1}');
        final next = await _sign('{"manifestSchemaVersion":1}');
        final ok = await verifyManifestSignatureWith(
          next.message,
          next.signatureBase64,
          publicKeysBase64: [current.publicKeyBase64, next.publicKeyBase64],
        );
        expect(ok, isTrue);
      },
    );

    test(
      'accepts a signature made by the FIRST key of a two-key set',
      () async {
        final current = await _sign('payload');
        final next = await _sign('payload');
        final ok = await verifyManifestSignatureWith(
          current.message,
          current.signatureBase64,
          publicKeysBase64: [current.publicKeyBase64, next.publicKeyBase64],
        );
        expect(ok, isTrue);
      },
    );

    test('rejects a signature made by a key outside the set', () async {
      final current = await _sign('payload');
      final next = await _sign('payload');
      final outsider = await _sign('payload');
      final ok = await verifyManifestSignatureWith(
        outsider.message,
        outsider.signatureBase64,
        publicKeysBase64: [current.publicKeyBase64, next.publicKeyBase64],
      );
      expect(ok, isFalse);
    });

    test('an invalid entry in the set does not break verification against a '
        'valid one', () async {
      final f = await _sign('payload');
      for (final bad in <String>[
        '',
        '   ',
        'not*valid*base64!!',
        base64.encode(List<int>.filled(31, 0)),
        base64.encode(List<int>.filled(33, 0)),
      ]) {
        expect(
          await verifyManifestSignatureWith(
            f.message,
            f.signatureBase64,
            publicKeysBase64: [bad, f.publicKeyBase64],
          ),
          isTrue,
          reason: 'invalid entry ${jsonEncode(bad)} before the valid key',
        );
        expect(
          await verifyManifestSignatureWith(
            f.message,
            f.signatureBase64,
            publicKeysBase64: [f.publicKeyBase64, bad],
          ),
          isTrue,
          reason: 'invalid entry ${jsonEncode(bad)} after the valid key',
        );
      }
    });

    test('a set of only invalid entries fails closed', () async {
      final f = await _sign('payload');
      final ok = await verifyManifestSignatureWith(
        f.message,
        f.signatureBase64,
        publicKeysBase64: ['', 'not*valid*base64!!'],
      );
      expect(ok, isFalse);
    });

    test('an empty set fails closed', () async {
      final f = await _sign('payload');
      final ok = await verifyManifestSignatureWith(
        f.message,
        f.signatureBase64,
        publicKeysBase64: const [],
      );
      expect(ok, isFalse);
    });

    test('tampered bytes fail against every key in the set', () async {
      final current = await _sign('the-real-manifest');
      final next = await _sign('the-real-manifest');
      final ok = await verifyManifestSignatureWith(
        utf8.encode('the-real-manifest-TAMPERED'),
        next.signatureBase64,
        publicKeysBase64: [current.publicKeyBase64, next.publicKeyBase64],
      );
      expect(ok, isFalse);
    });
  });

  group('kUpdateManifestPublicKeys (pinned set)', () {
    test('is non-empty and every entry is a 32-byte Ed25519 key', () {
      // A malformed entry would be skipped silently by the fail-closed
      // verifier, so a typo in a newly added "next" key would only surface at
      // rotation time — when that key is the one CI signs with. Catch it here.
      expect(kUpdateManifestPublicKeys, isNotEmpty);
      for (final key in kUpdateManifestPublicKeys) {
        expect(base64.decode(key.trim()), hasLength(32), reason: key);
      }
      expect(
        kUpdateManifestPublicKeys.toSet(),
        hasLength(kUpdateManifestPublicKeys.length),
        reason: 'duplicate pinned key',
      );
    });

    test('still pins the key the current releases are signed with', () {
      // Removing this key before CI has switched UPDATE_SIGNING_KEY to the
      // next key would make every install reject every manifest.
      expect(
        kUpdateManifestPublicKeys,
        contains('/39VzhfG58PnR5RlMzDB5ertil945PWRgA+usAj4qvw='),
      );
    });
  });

  group('verifyManifestSignature (production wiring)', () {
    test('fails closed on a signature not made by the pinned key', () async {
      // The production verifier rejects any signature not produced by the
      // pinned key's matching private key; this fixture signs with a random
      // in-test keypair, so it must not verify.
      final f = await _sign('anything');
      final ok = await verifyManifestSignature(f.message, f.signatureBase64);
      expect(ok, isFalse);
    });
  });
}
