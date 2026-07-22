/// Authenticity gate for the update manifest (issue #431, ADR-002 §6): verifies
/// a **detached Ed25519 signature** over the exact manifest bytes against the
/// in-app pinned public key ([kUpdateManifestPublicKey]).
///
/// This is the trust anchor for the *decision to download*: the mandatory
/// sha256 gate ([artifact_verifier.dart]) proves an artifact matches what the
/// manifest claims, but only this signature proves the manifest itself came
/// from the maintainer and was not tampered with in transit or at the CDN. It
/// therefore runs **before** any manifest field is parsed or trusted.
///
/// Fail-closed by construction (OWASP A08 — Software & Data Integrity
/// Failures): a missing, empty, malformed, wrong-length, or non-verifying
/// signature — or an unset/invalid pinned key — returns `false`, and the caller
/// treats that exactly like an unavailable update (a silent no-op, never an
/// install). It never throws.
///
/// Ed25519 verification uses `package:cryptography` (already an app dependency
/// for #461's backup crypto), which cleanly supports detached-signature
/// verification (`Ed25519().verify`). Keeping this in the `app` package respects
/// ADR-001 (compendium_core stays Flutter-free).
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'update_config.dart';

/// The injectable manifest-signature verification seam. [UpdateService] depends
/// on this typedef (default [verifyManifestSignature]) so tests can drive
/// good/bad/absent-signature paths with an in-test keypair.
typedef ManifestSignatureVerifier =
    Future<bool> Function(List<int> manifestBytes, String? signatureText);

/// Ed25519 (PureEdDSA) length invariants.
const int _kEd25519PublicKeyBytes = 32;
const int _kEd25519SignatureBytes = 64;

/// Default [ManifestSignatureVerifier]: verifies [signatureText] (standard
/// base64 of the raw 64-byte Ed25519 signature) over [manifestBytes] against
/// the pinned [kUpdateManifestPublicKey].
///
/// Returns `false` — never throws — for every failure mode: an absent/empty
/// signature, a signature that is not valid base64 or is not exactly 64 bytes,
/// an unset/invalid pinned key, or a signature that does not verify. This is
/// the production wiring; [verifyManifestSignatureWith] takes an explicit key so
/// tests can verify against a generated test keypair.
Future<bool> verifyManifestSignature(
  List<int> manifestBytes,
  String? signatureText,
) => verifyManifestSignatureWith(
  manifestBytes,
  signatureText,
  publicKeyBase64: kUpdateManifestPublicKey,
);

/// Verifies [signatureText] over [manifestBytes] against the Ed25519 public key
/// given as standard base64 in [publicKeyBase64]. Factored out of
/// [verifyManifestSignature] so unit tests can supply a test key while
/// production pins [kUpdateManifestPublicKey]. Fail-closed and never throws.
Future<bool> verifyManifestSignatureWith(
  List<int> manifestBytes,
  String? signatureText, {
  required String publicKeyBase64,
}) async {
  // No signature => refuse. Preserves the "missing signature is a silent no-op"
  // contract without letting an unsigned manifest through.
  if (signatureText == null) return false;
  final trimmedSig = signatureText.trim();
  if (trimmedSig.isEmpty) return false;

  // No pinned key (the shipped placeholder) => fail closed: the client never
  // trusts a manifest until the maintainer provisions the real key.
  final trimmedKey = publicKeyBase64.trim();
  if (trimmedKey.isEmpty) return false;

  final List<int> publicKeyBytes;
  final List<int> signatureBytes;
  try {
    publicKeyBytes = base64.decode(trimmedKey);
    signatureBytes = base64.decode(trimmedSig);
  } on FormatException {
    // A pinned key or signature that is not valid base64 is malformed input at
    // the trust boundary => refuse.
    return false;
  }

  // Enforce the exact Ed25519 lengths before touching the crypto library, so a
  // truncated/padded key or signature is rejected deterministically rather than
  // relying on the library to raise.
  if (publicKeyBytes.length != _kEd25519PublicKeyBytes) return false;
  if (signatureBytes.length != _kEd25519SignatureBytes) return false;

  try {
    final algorithm = Ed25519();
    final publicKey = SimplePublicKey(
      publicKeyBytes,
      type: KeyPairType.ed25519,
    );
    final signature = Signature(signatureBytes, publicKey: publicKey);
    return await algorithm.verify(manifestBytes, signature: signature);
  } on Object {
    // Any unexpected verification error fails closed rather than surfacing.
    return false;
  }
}
