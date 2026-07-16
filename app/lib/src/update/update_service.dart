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

import 'package:http/http.dart' as http;

import 'semver.dart';
import 'update_fetcher.dart';
import 'update_manifest.dart';

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
  UpdateService({UpdateManifestFetcher? fetcher})
    : _fetcher = fetcher ?? fetchUpdateManifest;

  final UpdateManifestFetcher _fetcher;

  /// Fetches [channel]'s manifest, validates it, and returns an
  /// [UpdateAvailable] when its version is strictly newer than
  /// [currentVersion]; otherwise (up-to-date, unreachable, malformed, or
  /// unsupported) returns `null`.
  ///
  /// [platform]/[arch] are used only for the **client-side** artifact
  /// selection carried on the result — they are never transmitted to the host.
  /// [client] is forwarded to the fetch seam for tests.
  Future<UpdateAvailable?> check({
    required UpdateChannel channel,
    required SemVer currentVersion,
    required UpdatePlatform platform,
    required UpdateArch arch,
    http.Client? client,
  }) async {
    final body = await _fetcher(channel, client: client);
    if (body == null) return null; // offline / 404 / timeout / empty

    final UpdateManifest manifest;
    try {
      manifest = UpdateManifest.parse(body, expectedChannel: channel);
    } on UpdateManifestFormatException {
      // Malformed / partial / unsupported-schema / channel-mismatch: no-op.
      return null;
    } on Object {
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
