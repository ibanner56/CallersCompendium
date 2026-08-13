/// The mandatory sha256 integrity gate for the assisted-download flow
/// (ADR-002 §2/§6, "Stage 1.5"): after a download completes, the file's sha256
/// is recomputed and compared against the manifest artifact's `sha256`.
///
/// A mismatch is a **hard security failure**, never a silent no-op: the caller
/// deletes the file and surfaces a clear error rather than handing a possibly
/// tampered/corrupt artifact to the OS installer. The digest is streamed
/// through `package:crypto` so a large artifact is never buffered whole, and
/// the hex comparison is **case-insensitive and constant-time-ish** (a
/// fixed-work accumulate over the full digest) so it neither trips on casing
/// nor leaks match position via early return.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

/// The injectable verification seam. The [UpdateController] depends on this
/// typedef (default [verifyArtifactSha256]) so tests can force a match/mismatch
/// without hashing a real file.
typedef ArtifactVerifier =
    Future<bool> Function(File file, String expectedSha256Hex);

/// Default [ArtifactVerifier]: streams [file] through sha256 and returns whether
/// the lowercase-hex digest equals [expectedSha256Hex] (compared with
/// [constantTimeHexEquals]). Returns `false` — never throws — if the file is
/// unreadable, so an I/O hiccup fails the gate closed rather than crashing the
/// download flow.
Future<bool> verifyArtifactSha256(File file, String expectedSha256Hex) async {
  final Digest digest;
  try {
    digest = await sha256.bind(file.openRead()).first;
  } on Object {
    // diagnostics: silent — I/O error reading the artifact file for SHA-256 verification; fails closed (returns false)
    return false;
  }
  return constantTimeHexEquals(digest.toString(), expectedSha256Hex);
}

/// Case-insensitively compares two hex strings in (near) constant time relative
/// to their length: it first rejects a length mismatch, then accumulates the
/// per-character difference across **all** characters instead of returning at
/// the first divergence, so timing does not reveal where two equal-length
/// digests first differ. Non-hex input simply fails to match.
bool constantTimeHexEquals(String a, String b) {
  final lowerA = a.toLowerCase();
  final lowerB = b.toLowerCase();
  if (lowerA.length != lowerB.length) return false;
  var diff = 0;
  for (var i = 0; i < lowerA.length; i++) {
    diff |= lowerA.codeUnitAt(i) ^ lowerB.codeUnitAt(i);
  }
  return diff == 0;
}
