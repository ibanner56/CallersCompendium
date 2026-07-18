/// App-level configuration and persistence keys for the Stage-1 update check
/// (ADR-002 §1/§2/§5). Kept out of the pure model so the model stays free of
/// deployment specifics (URLs, timeouts, storage keys).
library;

import 'update_manifest.dart';

/// The GitHub Pages base under which the per-channel manifests are published
/// (ADR-002 §1). **Not live until A11c publishes it** — so a 404/unreachable
/// manifest is a silent no-op, never an error (see the fetcher and ADR-002 §5).
const String kUpdateManifestBaseUrl =
    'https://ibanner56.github.io/CallersCompendium';

/// How long the update check waits before giving up. Deliberately short: a
/// missing network must be a fast, silent no-op rather than a hang (ADR-002 §5).
const Duration kUpdateCheckTimeout = Duration(seconds: 10);

/// The **idle** timeout for an assisted download (ADR-002 "Stage 1.5"): the
/// engine aborts if no bytes arrive within this window. It is an inter-chunk
/// timeout (reset on every chunk), not a wall-clock cap, so a large artifact on
/// a slow-but-alive connection is not cut off while a genuinely stalled
/// connection still fails promptly. Longer than [kUpdateCheckTimeout] because a
/// real transfer is expected here, unlike the fire-and-forget check.
const Duration kUpdateDownloadTimeout = Duration(seconds: 60);

/// A hard upper bound on the number of bytes [downloadArtifact] will write for a
/// single artifact, applied as a **backstop** when the manifest declares no
/// usable `size` (`size == 0`). A manifest parsed by [UpdateManifest] always
/// carries a positive `size` (the model rejects `size <= 0`), and that value is
/// the tight per-download bound; this constant only guards a direct caller that
/// supplies an unsized artifact, so a compromised or misbehaving host can never
/// stream unbounded bytes to disk (OWASP A08 / resource exhaustion). Set well
/// above any realistic desktop installer (1 GiB) so it never truncates a
/// legitimate update.
const int kMaxArtifactDownloadBytes = 1024 * 1024 * 1024;

/// Derives a safe local filename for a downloaded [artifactUrl]: the URL's last
/// non-empty path segment (e.g. `CallersCompendium-0.2.0-macos-universal.dmg`),
/// stripped of any path separators or characters that are unsafe in a filename,
/// with a generic fallback when the URL carries no usable segment. Used to name
/// the temp file the artifact streams into.
String downloadFileName(String artifactUrl) {
  final uri = Uri.tryParse(artifactUrl);
  var name = '';
  if (uri != null && uri.pathSegments.isNotEmpty) {
    name = uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
  }
  // Defense-in-depth: never let a crafted URL segment escape the temp dir or
  // inject shell-unsafe characters into the on-disk name.
  name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (name.isEmpty || name == '.' || name == '..') {
    return 'CallersCompendium-update.download';
  }
  return name;
}

/// Builds the static-manifest URL for [channel]: `…/stable.json` (the default)
/// or `…/beta.json` (only when the user has opted into beta). The request is a
/// bare `GET` of this URL — no query params are ever appended (ADR-002 §5).
String manifestUrlForChannel(UpdateChannel channel) =>
    '$kUpdateManifestBaseUrl/${channel.wire}.json';

/// Persisted-settings key for the beta-channel opt-in (ADR-002 §3). Stored as a
/// `bool`; absent/unset means off → the client only ever fetches `stable.json`.
const String kUpdateBetaChannelKey = 'update_beta_channel';

/// Persisted-settings key for the automatic background-check opt-in
/// (ADR-002 §5). Stored as a `bool`; absent/unset means off → the check only
/// runs when the user presses "Check for updates".
const String kUpdateAutoCheckKey = 'update_auto_check';

/// Persisted-settings key for the last version the user dismissed from the
/// update banner (ADR-002 §5). Stored as a SemVer string; once version X is
/// dismissed the banner stays hidden until a strictly-newer version appears.
const String kUpdateDismissedVersionKey = 'update_dismissed_version';
