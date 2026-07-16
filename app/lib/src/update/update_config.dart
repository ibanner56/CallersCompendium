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
