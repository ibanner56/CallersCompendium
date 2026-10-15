/// Orchestrates the Stage-1 update check: fetch the channel manifest (via the
/// injected seam), parse+validate it, compare its version against the running
/// app version, and — if strictly newer — return what the banner needs. The
/// same authenticated manifest also says whether the running build has an
/// announced end-of-life date ([UpdateCheckResult.endOfLife]).
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

/// Everything one authenticated, well-formed manifest says about the running
/// build. Returned by [UpdateService.checkManifest]; a check that could not
/// fetch, authenticate, or parse the manifest yields no result at all, so a
/// caller can tell "the manifest announces nothing" (clear any cached notice)
/// from "the manifest could not be read" (keep what it already knew).
class UpdateCheckResult {
  const UpdateCheckResult({this.update, this.endOfLife});

  /// The strictly-newer release, or `null` when the running build is current.
  final UpdateAvailable? update;

  /// The announced end-of-life date for the running build (a UTC-midnight
  /// calendar date — see [UpdateRetirement.endOfLife]), or `null` when the
  /// manifest announces none for it.
  final DateTime? endOfLife;
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
  /// Ed25519 public keys** (any one of them), validates it, and returns an [UpdateAvailable] when
  /// its version is strictly newer than [currentVersion]; otherwise
  /// (up-to-date, unreachable, unsigned, tampered, malformed, or unsupported)
  /// returns `null`.
  ///
  /// The signature is verified over the **exact fetched bytes before any
  /// manifest field is parsed or trusted** (issue #431, ADR-002 §6): a missing,
  /// invalid, or malformed signature — or one no pinned key verifies — is refused as a
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
    final result = await checkManifest(
      channel: channel,
      currentVersion: currentVersion,
      platform: platform,
      arch: arch,
      client: client,
    );
    return result?.update;
  }

  /// The full form of [check]: fetches, authenticates, and parses [channel]'s
  /// manifest exactly as [check] does, and returns both the newer release (if
  /// any) and the end-of-life date the manifest announces for
  /// [currentVersion] (if any).
  ///
  /// Returns `null` — never throws — when the manifest could not be fetched,
  /// authenticated, decoded, or parsed. A `null` therefore means "nothing is
  /// known", which is different from a result whose fields are both `null`
  /// ("the manifest was read and announces nothing for this build").
  Future<UpdateCheckResult?> checkManifest({
    required UpdateChannel channel,
    required SemVer currentVersion,
    required UpdatePlatform platform,
    required UpdateArch arch,
    http.Client? client,
  }) async {
    final manifestBytes = await _fetcher(channel, client: client);
    if (manifestBytes == null) return null; // offline / 404 / timeout / empty

    // Authenticate BEFORE trusting the body: fetch the detached signature and
    // verify it over the EXACT wire bytes against the pinned key set. Any failure
    // (absent/invalid/malformed signature, no pinned key verifies) is a fail-closed
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

    return UpdateCheckResult(
      update: manifest.version.isNewerThan(currentVersion)
          ? UpdateAvailable(
              version: manifest.version,
              releaseNotesUrl: manifest.releaseNotesUrl,
              channel: manifest.channel,
              artifact: manifest.selectArtifact(platform, arch),
            )
          : null,
      endOfLife: manifest.endOfLifeFor(currentVersion),
    );
  }
}
