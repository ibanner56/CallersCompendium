/// Orchestrates the Stage-1 update check: fetch the channel manifest (via the
/// injected seam), parse+validate it, compare its version against the running
/// app version, and — if strictly newer — return what the banner needs.
///
/// The pure logic (SemVer compare, schema parse, artifact selection) lives in
/// `semver.dart`/`update_manifest.dart`; this layer only composes them with the
/// network seam. Every failure path — offline, timeout, 404, non-2xx, malformed
/// or unsupported manifest, or a version that is not newer — resolves to `null`
/// (a silent no-op), never an exception or dialog (ADR-002 §5).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'semver.dart';
import 'update_fetcher.dart';
import 'update_manifest.dart';
import 'update_signature.dart';

/// The result of a successful check that found a strictly-newer version: what
/// the banner shows and links to. Carries the selected [artifact] (may be
/// `null` when the release built nothing for this platform/arch) so the
/// assisted-download stage (A11b) can build on it; Stage 1 only uses
/// [releaseNotesUrl].
class UpdateAvailable {
  const UpdateAvailable({
    required this.version,
    required this.releaseNotesUrl,
    required this.channel,
    this.artifact,
  });

  final SemVer version;
  final String releaseNotesUrl;
  final UpdateChannel channel;
  final UpdateArtifact? artifact;
}

/// Runs the update check against the static per-channel manifest.
class UpdateService {
  UpdateService({
    UpdateManifestFetcher? fetcher,
    UpdateManifestSignatureFetcher? signatureFetcher,
    ManifestSignatureVerifier? signatureVerifier,
  }) : _fetcher = fetcher ?? fetchUpdateManifest,
       _signatureFetcher = signatureFetcher ?? fetchUpdateManifestSignature,
       _signatureVerifier = signatureVerifier ?? verifyManifestSignature;

  final UpdateManifestFetcher _fetcher;
  final UpdateManifestSignatureFetcher _signatureFetcher;
  final ManifestSignatureVerifier _signatureVerifier;

  /// Fetches [channel]'s manifest, **authenticates it against the pinned
  /// Ed25519 public key**, validates it, and returns an [UpdateAvailable] when
  /// its version is strictly newer than [currentVersion]; otherwise
  /// (up-to-date, unreachable, unsigned, tampered, malformed, or unsupported)
  /// returns `null`.
  ///
  /// The signature is verified over the **exact fetched bytes before any
  /// manifest field is parsed or trusted** (issue #431, ADR-002 §6): a missing,
  /// invalid, or malformed signature — or an unset pinned key — is refused as a
  /// silent no-op, indistinguishable from "no update" by design, never an
  /// install. This preserves the existing "missing/unreachable manifest =
  /// silent no-op" behavior while adding authenticity.
  ///
  /// [platform]/[arch] are used only for the **client-side** artifact
  /// selection carried on the result — they are never transmitted to the host.
  /// [client] is forwarded to the fetch seams for tests.
  Future<UpdateAvailable?> check({
    required UpdateChannel channel,
    required SemVer currentVersion,
    required UpdatePlatform platform,
    required UpdateArch arch,
    http.Client? client,
  }) async {
    final manifestBytes = await _fetcher(channel, client: client);
    if (manifestBytes == null) return null; // offline / 404 / timeout / empty

    // Authenticate BEFORE trusting the body: fetch the detached signature and
    // verify it over the EXACT wire bytes against the pinned key. Any failure
    // (absent/invalid/malformed signature, unset pinned key) is a fail-closed
    // silent no-op. Verifying over the raw bytes — never a re-encoded decoded
    // String — is what makes this match the bytes CI actually signed.
    final signature = await _signatureFetcher(channel, client: client);
    final authentic = await _signatureVerifier(manifestBytes, signature);
    if (!authentic) return null;

    // Only after the bytes are proven authentic do we decode them for parsing.
    // A body that is not valid UTF-8 (impossible for a manifest we signed) is a
    // fail-closed no-op rather than an exception.
    final String body;
    try {
      body = utf8.decode(manifestBytes);
    } on Object {
      // diagnostics: silent — non-UTF-8 manifest body after signature verification; impossible in practice but fail closed
      return null;
    }

    final UpdateManifest manifest;
    try {
      manifest = UpdateManifest.parse(body, expectedChannel: channel);
    } on UpdateManifestFormatException {
      // diagnostics: silent — malformed/partial/unsupported-schema/channel-mismatch manifest; no update available
      return null;
    } on Object {
      // diagnostics: silent — unexpected parse error; no update available
      return null;
    }

    if (!manifest.version.isNewerThan(currentVersion)) return null;

    return UpdateAvailable(
      version: manifest.version,
      releaseNotesUrl: manifest.releaseNotesUrl,
      channel: manifest.channel,
      artifact: manifest.selectArtifact(platform, arch),
    );
  }
}
