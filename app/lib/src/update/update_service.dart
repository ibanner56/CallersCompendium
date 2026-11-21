/// Orchestrates the Stage-1 update check: fetch the channel manifest (via the
/// injected seam), parse+validate it, compare its version against the running
/// app version, and — if strictly newer — return what the banner needs. The
/// same authenticated manifest also says whether the running build has an
/// announced end-of-life date ([UpdateCheckResult.endOfLife]).
///
/// The pure logic (SemVer compare, schema parse, artifact selection) lives in
/// `semver.dart`/`update_manifest.dart`; this layer only composes them with the
/// network seam. Every failure path — offline, timeout, 404, non-2xx, malformed
/// or unsupported manifest, or a version that is not newer — resolves to a
/// value, never an exception or dialog (ADR-002 §5). [check] folds all of them
/// to `null`; [checkManifest] says which one it was, so the *manual* check can
/// tell the user why (the automatic check stays silent).
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

/// Why a check could not read the manifest. Carries no prose — the Settings
/// status line chooses the words.
enum UpdateCheckFailure {
  /// The manifest (or its signature) could not be fetched: offline, 404,
  /// timeout, or an empty body.
  unreachable,

  /// The manifest arrived but its signature is absent, malformed, or verified
  /// by no pinned key. Nothing in it is trusted.
  unauthentic,

  /// The manifest is **authentic** but in a format this build cannot read: a
  /// newer `manifestSchemaVersion`, or an artifact for a platform or
  /// architecture this build has no name for. This is what a newer release
  /// looks like to an older app, so it is the one failure that says something
  /// true about the world ("a newer version exists").
  unsupportedFormat,

  /// The manifest is authentic but unreadable for any other reason: invalid
  /// UTF-8 or JSON, a missing or invalid field, or a channel mismatch.
  malformed,
}

/// The outcome of [UpdateService.checkManifest]: either the manifest was read
/// ([UpdateChecked]) or it was not and [UpdateCheckFailed] says why. A caller
/// can thereby tell "the manifest announces nothing" (clear any cached notice)
/// from "the manifest could not be read" (keep what it already knew).
sealed class UpdateCheckOutcome {
  const UpdateCheckOutcome();
}

/// The manifest was fetched, authenticated and parsed.
class UpdateChecked extends UpdateCheckOutcome {
  const UpdateChecked(this.result);

  final UpdateCheckResult result;
}

/// The manifest could not be read, for [failure].
class UpdateCheckFailed extends UpdateCheckOutcome {
  const UpdateCheckFailed(this.failure);

  final UpdateCheckFailure failure;
}

/// Everything one authenticated, well-formed manifest says about the running
/// build. Carried by [UpdateChecked].
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
  /// returns `null`. Use [checkManifest] to learn which.
  ///
  /// The signature is verified over the **exact fetched bytes before any
  /// manifest field is parsed or trusted** (issue #431, ADR-002 §6): a missing,
  /// invalid, or malformed signature — or one no pinned key verifies — is refused,
  /// never an install, and is reported as [UpdateCheckFailure.unauthentic]
  /// (the automatic check shows nothing; the manual one says it could not
  /// check). A missing or unreachable manifest stays a no-op while adding
  /// authenticity.
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
    return switch (result) {
      UpdateChecked(:final result) => result.update,
      UpdateCheckFailed() => null,
    };
  }

  /// The full form of [check]: fetches, authenticates, and parses [channel]'s
  /// manifest exactly as [check] does, and returns both the newer release (if
  /// any) and the end-of-life date the manifest announces for
  /// [currentVersion] (if any).
  ///
  /// Never throws. When the manifest could not be fetched, authenticated,
  /// decoded, or parsed it returns an [UpdateCheckFailed] naming which, which
  /// means "nothing is known" and is different from an [UpdateChecked] whose
  /// fields are both `null` ("the manifest was read and announces nothing for
  /// this build").
  Future<UpdateCheckOutcome> checkManifest({
    required UpdateChannel channel,
    required SemVer currentVersion,
    required UpdatePlatform platform,
    required UpdateArch arch,
    http.Client? client,
  }) async {
    final manifestBytes = await _fetcher(channel, client: client);
    if (manifestBytes == null) {
      // offline / 404 / timeout / empty
      return const UpdateCheckFailed(UpdateCheckFailure.unreachable);
    }

    // Authenticate BEFORE trusting the body: fetch the detached signature and
    // verify it over the EXACT wire bytes against the pinned key set. Any failure
    // (absent/invalid/malformed signature, no pinned key verifies) is a
    // fail-closed no-op (silent in the automatic check). Verifying over the raw bytes — never a re-encoded decoded
    // String — is what makes this match the bytes CI actually signed.
    final signature = await _signatureFetcher(channel, client: client);
    final authentic = await _signatureVerifier(manifestBytes, signature);
    if (!authentic) {
      return const UpdateCheckFailed(UpdateCheckFailure.unauthentic);
    }

    // Only after the bytes are proven authentic do we decode them for parsing.
    // A body that is not valid UTF-8 (impossible for a manifest we signed) is a
    // fail-closed no-op rather than an exception.
    final String body;
    try {
      body = utf8.decode(manifestBytes);
    } on Object {
      // diagnostics: silent — non-UTF-8 manifest body after signature verification; impossible in practice but fail closed
      return const UpdateCheckFailed(UpdateCheckFailure.malformed);
    }

    final UpdateManifest manifest;
    try {
      manifest = UpdateManifest.parse(body, expectedChannel: channel);
    } on UpdateManifestUnsupportedException {
      // diagnostics: silent — authentic manifest in a newer format than this build reads; surfaced as UpdateCheckFailure.unsupportedFormat
      return const UpdateCheckFailed(UpdateCheckFailure.unsupportedFormat);
    } on UpdateManifestFormatException {
      // diagnostics: silent — malformed/partial/lower-schema/channel-mismatch manifest; no update available
      return const UpdateCheckFailed(UpdateCheckFailure.malformed);
    } on Object {
      // diagnostics: silent — unexpected parse error; no update available
      return const UpdateCheckFailed(UpdateCheckFailure.malformed);
    }

    return UpdateChecked(
      UpdateCheckResult(
        update: manifest.version.isNewerThan(currentVersion)
            ? UpdateAvailable(
                version: manifest.version,
                releaseNotesUrl: manifest.releaseNotesUrl,
                channel: manifest.channel,
                artifact: manifest.selectArtifact(platform, arch),
              )
            : null,
        endOfLife: manifest.endOfLifeFor(currentVersion),
      ),
    );
  }
}
