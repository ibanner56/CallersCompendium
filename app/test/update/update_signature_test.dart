import 'dart:convert';

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
        publicKeyBase64: f.publicKeyBase64,
      );
      expect(ok, isTrue);
    });

    test('rejects a signature made by a different key', () async {
      final f = await _sign('payload');
      final other = await _sign('payload');
      final ok = await verifyManifestSignatureWith(
        f.message,
        f.signatureBase64,
        publicKeyBase64: other.publicKeyBase64,
      );
      expect(ok, isFalse);
    });

    test('rejects a signature over tampered bytes', () async {
      final f = await _sign('the-real-manifest');
      final ok = await verifyManifestSignatureWith(
        utf8.encode('the-real-manifest-TAMPERED'),
        f.signatureBase64,
        publicKeyBase64: f.publicKeyBase64,
      );
      expect(ok, isFalse);
    });

    test(
      'fails closed on an empty pinned key (the shipped placeholder)',
      () async {
        final f = await _sign('x');
        final ok = await verifyManifestSignatureWith(
          f.message,
          f.signatureBase64,
          publicKeyBase64: '',
        );
        expect(ok, isFalse);
      },
    );

    test('fails closed on a null signature', () async {
      final f = await _sign('x');
      final ok = await verifyManifestSignatureWith(
        f.message,
        null,
        publicKeyBase64: f.publicKeyBase64,
      );
      expect(ok, isFalse);
    });

    test('fails closed on an empty/whitespace signature', () async {
      final f = await _sign('x');
      expect(
        await verifyManifestSignatureWith(
          f.message,
          '',
          publicKeyBase64: f.publicKeyBase64,
        ),
        isFalse,
      );
      expect(
        await verifyManifestSignatureWith(
          f.message,
          '   \n',
          publicKeyBase64: f.publicKeyBase64,
        ),
        isFalse,
      );
    });

    test('rejects a non-base64 signature', () async {
      final f = await _sign('x');
      final ok = await verifyManifestSignatureWith(
        f.message,
        'not*valid*base64!!',
        publicKeyBase64: f.publicKeyBase64,
      );
      expect(ok, isFalse);
    });

    test('rejects a non-base64 pinned key', () async {
      final f = await _sign('x');
      final ok = await verifyManifestSignatureWith(
        f.message,
        f.signatureBase64,
        publicKeyBase64: 'not*valid*base64!!',
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
          publicKeyBase64: f.publicKeyBase64,
        ),
        isFalse,
      );
      expect(
        await verifyManifestSignatureWith(
          f.message,
          long,
          publicKeyBase64: f.publicKeyBase64,
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
        publicKeyBase64: wrongKey,
      );
      expect(ok, isFalse);
    });

    test('tolerates surrounding whitespace on a valid signature', () async {
      final f = await _sign('trimmed');
      final ok = await verifyManifestSignatureWith(
        f.message,
        '  ${f.signatureBase64}\n',
        publicKeyBase64: f.publicKeyBase64,
      );
      expect(ok, isTrue);
    });
  });

  group('verifyManifestSignature (production wiring)', () {
    test(
      'fails closed because the shipped pinned key is a placeholder',
      () async {
        // Ships empty, so the default verifier can never accept anything until
        // the maintainer provisions the real key.
        final f = await _sign('anything');
        final ok = await verifyManifestSignature(f.message, f.signatureBase64);
        expect(ok, isFalse);
      },
    );
  });
}
