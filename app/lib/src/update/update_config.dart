/// App-level configuration and persistence keys for the Stage-1 update check
/// (ADR-002 §1/§2/§5). Kept out of the pure model so the model stays free of
/// deployment specifics (URLs, timeouts, storage keys).
library;

import '../utils/safe_name.dart';
import 'update_manifest.dart';

/// The GitHub Pages base under which the per-channel manifests are published
/// (ADR-002 §1). **Not live until A11c publishes it** — so a 404/unreachable
/// manifest is a silent no-op, never an error (see the fetcher and ADR-002 §5).
const String kUpdateManifestBaseUrl =
    'https://ibanner56.github.io/CallersCompendium';

/// The pinned Ed25519 **public key** (32 bytes, standard base64) the client
/// verifies the update manifest's detached signature against (issue #431,
/// ADR-002 §6). This is the root of trust for the *authenticity* of an update:
/// a manifest whose signature does not verify against this key — or that has no
/// signature at all — is refused as a silent no-op, never installed.
///
/// Rotating the key requires publishing the new public key in an app update
/// **before** switching the signing key, because older clients pin the old key.
const String kUpdateManifestPublicKey =
    '/39VzhfG58PnR5RlMzDB5ertil945PWRgA+usAj4qvw=';

/// The filename suffix of a channel manifest's detached signature, served next
/// to `<channel>.json` on gh-pages (e.g. `stable.json` → `stable.json.sig`).
/// The `.sig` body is the standard-base64 encoding of the raw 64-byte Ed25519
/// signature over the **exact** bytes of `<channel>.json` (issue #431).
const String kUpdateSignatureFileSuffix = '.sig';

/// A hard upper bound on the manifest body the client will read (issue #431).
/// A channel manifest is small JSON (a handful of artifacts); 256 KiB is far
/// above any realistic manifest yet small enough that a misbehaving or
/// compromised — even allowlisted — host cannot force a large allocation. The
/// fetcher streams the body and aborts as soon as the running total exceeds
/// this cap, so the bound is enforced **before** the bytes are buffered (OWASP
/// A08 / resource exhaustion), never merely checked after the fact.
const int kMaxManifestBytes = 256 * 1024;

/// A hard upper bound on the manifest signature body the client will read. A
/// base64-encoded 64-byte Ed25519 signature is ~88 bytes; this cap (with slack
/// for whitespace) ensures a misbehaving host cannot stream an unbounded body
/// into memory at the trust boundary (OWASP A08 / resource exhaustion).
const int kMaxSignatureBytes = 4 * 1024;

/// The exhaustive allowlist of hosts an update artifact (and every redirect hop
/// on the way to it) may be served from (issue #431). Restricting downloads to
/// canonical GitHub-owned domains — the release-assets host that
/// `https://github.com/<repo>/releases/download/...` redirects to, plus the
/// gh-pages origin — closes an off-host redirect as an exfiltration/tamper
/// vector even before the mandatory signature + sha256 gates (OWASP A10 —
/// Server-Side Request Forgery / A08). Matched **exactly** (no subdomain
/// wildcard) so a look-alike or taken-over subdomain is never trusted.
const Set<String> kAllowedArtifactHosts = {
  // Release-download URLs the manifest publishes.
  'github.com',
  // Where `github.com/.../releases/download/...` currently 302-redirects.
  'release-assets.githubusercontent.com',
  // GitHub's historical/fallback release-asset host, kept so a redirect to it
  // is not spuriously refused.
  'objects.githubusercontent.com',
  // The gh-pages origin that serves the manifests (and could serve artifacts).
  'ibanner56.github.io',
};

/// Whether [uri] is an acceptable target for an artifact download or redirect
/// hop (issue #431). Requires **all** of: an `https` scheme, a host on
/// [kAllowedArtifactHosts] (compared case-insensitively, exact match), no
/// userinfo (`user:pass@host` — a classic host-confusion trick), and either no
/// explicit port or the default TLS port 443. Anything else is refused so a
/// scheme downgrade, a userinfo/port trick, or an off-allowlist host — direct
/// or reached via redirect — can never steer the download (OWASP A10 / A08).
bool isAllowedArtifactHost(Uri uri) {
  if (!uri.isScheme('https')) return false;
  if (uri.userInfo.isNotEmpty) return false;
  if (uri.hasPort && uri.port != 443) return false;
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return false;
  return kAllowedArtifactHosts.contains(host);
}

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
/// single artifact, applied as a **backstop** for an artifact that carries no
/// usable `size` (`size == 0`). A manifest parsed by [UpdateManifest] can never
/// produce that case (the model rejects `size <= 0`), so in practice this only
/// guards a *direct* caller that constructs an unsized [UpdateArtifact]; the
/// manifest `size` is otherwise the tight per-download bound. Either way a
/// compromised or misbehaving host cannot stream unbounded bytes to disk
/// (OWASP A08 / resource exhaustion). Set well above any realistic desktop
/// installer (1 GiB) so it never truncates a legitimate update.
const int kMaxArtifactDownloadBytes = 1024 * 1024 * 1024;

/// The maximum number of HTTP redirects [downloadArtifact] follows before giving
/// up. Redirects are followed **manually** so each hop can be re-validated as
/// https (GitHub serves release assets via an `https → https` redirect); this
/// only bounds a redirect loop.
const int kMaxArtifactRedirects = 5;

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
  name = replaceUnsafeNameChars(name);
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

/// Builds the detached-signature URL for [channel]'s manifest:
/// `…/stable.json.sig` (or `…/beta.json.sig`). Like the manifest request this
/// is a bare `GET` with no query params (ADR-002 §5).
String signatureUrlForChannel(UpdateChannel channel) =>
    '${manifestUrlForChannel(channel)}$kUpdateSignatureFileSuffix';

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
