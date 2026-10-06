/// Authenticity gate for the update manifest (issue #431, ADR-002 §6): verifies
/// a **detached Ed25519 signature** over the exact manifest bytes against the
/// in-app pinned public keys ([kUpdateManifestPublicKeys]); a signature that
/// verifies against **any** pinned key is accepted, so a signing-key rotation
/// never strands an install (security-2).
///
/// This is the trust anchor for the *decision to download*: the mandatory
/// sha256 gate ([artifact_verifier.dart]) proves an artifact matches what the
/// manifest claims, but only this signature proves the manifest itself came
/// from the maintainer and was not tampered with in transit or at the CDN. It
/// therefore runs **before** any manifest field is parsed or trusted.
///
/// Fail-closed by construction (OWASP A08 — Software & Data Integrity
/// Failures): a missing, empty, malformed, wrong-length, or non-verifying
/// signature — or an empty set, or no pinned key that is valid and verifies —
/// returns `false`, and the caller
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
/// the pinned [kUpdateManifestPublicKeys].
///
/// Returns `false` — never throws — for every failure mode: an absent/empty
/// signature, a signature that is not valid base64 or is not exactly 64 bytes,
/// an empty key set, or no valid pinned key under which the signature
/// verifies. This is the production wiring; [verifyManifestSignatureWith] takes
/// an explicit key set so tests can verify against generated test keypairs.
Future<bool> verifyManifestSignature(
  List<int> manifestBytes,
  String? signatureText,
) => verifyManifestSignatureWith(
  manifestBytes,
  signatureText,
  publicKeysBase64: kUpdateManifestPublicKeys,
);

/// Verifies [signatureText] over [manifestBytes] against each Ed25519 public
/// key given as standard base64 in [publicKeysBase64], and returns `true` when
/// it verifies against **any** of them. Factored out of
/// [verifyManifestSignature] so unit tests can supply test keys while
/// production pins [kUpdateManifestPublicKeys].
///
/// Each key is judged on its own: an empty, non-base64 or wrong-length entry
/// is skipped (never trusted) and does not stop a later valid key from
/// verifying. An empty set — or a set with no usable key — returns `false`.
/// Fail-closed and never throws.
Future<bool> verifyManifestSignatureWith(
  List<int> manifestBytes,
  String? signatureText, {
  required List<String> publicKeysBase64,
}) async {
  // No signature => refuse. Preserves the "missing signature is a silent no-op"
  // contract without letting an unsigned manifest through.
  if (signatureText == null) return false;
  final trimmedSig = signatureText.trim();
  if (trimmedSig.isEmpty) return false;

  final List<int> signatureBytes;
  try {
    signatureBytes = base64.decode(trimmedSig);
  } on FormatException {
    // diagnostics: silent — a signature that is not valid base64 is malformed input;
    // fails closed (returns false) at the trust boundary
    return false;
  }
  // Enforce the exact Ed25519 length before touching the crypto library, so a
  // truncated/padded signature is rejected deterministically rather than
  // relying on the library to raise.
  if (signatureBytes.length != _kEd25519SignatureBytes) return false;

  for (final keyBase64 in publicKeysBase64) {
    if (await _verifiesUnderKey(manifestBytes, signatureBytes, keyBase64)) {
      return true;
    }
  }
  // Empty set, or no usable key verified => fail closed.
  return false;
}

/// Whether [signatureBytes] verifies over [manifestBytes] under the single
/// key [publicKeyBase64]. `false` — never a throw — for an empty, non-base64
/// or wrong-length key, so one bad entry cannot poison the rest of the set.
Future<bool> _verifiesUnderKey(
  List<int> manifestBytes,
  List<int> signatureBytes,
  String publicKeyBase64,
) async {
  // An empty entry (e.g. an unset "next" slot) is never trusted.
  final trimmedKey = publicKeyBase64.trim();
  if (trimmedKey.isEmpty) return false;

  final List<int> publicKeyBytes;
  try {
    publicKeyBytes = base64.decode(trimmedKey);
  } on FormatException {
    // diagnostics: silent — a pinned key that is not valid base64 is malformed;
    // that entry is skipped (fail closed for it), other keys are still tried
    return false;
  }
  if (publicKeyBytes.length != _kEd25519PublicKeyBytes) return false;

  try {
    final algorithm = Ed25519();
    final publicKey = SimplePublicKey(
      publicKeyBytes,
      type: KeyPairType.ed25519,
    );
    final signature = Signature(signatureBytes, publicKey: publicKey);
    return await algorithm.verify(manifestBytes, signature: signature);
  } on Object {
    // diagnostics: silent — unexpected verification error from the crypto library; fails closed
    return false;
  }
}
