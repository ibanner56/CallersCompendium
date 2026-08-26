/// Static app identity used by the About/Licenses section (settings) and any
/// other in-app attribution surface.
///
/// The version is kept as a plain constant rather than read at runtime via a
/// plugin (e.g. `package_info_plus`): the app has no existing runtime version
/// mechanism, and pulling in a platform plugin purely to echo the pubspec
/// version would add build/test surface for no functional gain. This constant
/// is the single in-code source of truth and **must be kept in step with the
/// `version:` field in `app/pubspec.yaml`** (exactly `X.Y.Z`, with no suffix).
library;

/// Human-facing application name.
const String kAppName = "Caller's Compendium";

/// One-line mission/tagline shown under the app name on the About brand header.
/// Kept here as the single source of truth so any other surface can reuse it.
const String kAppTagline =
    'Your dances, your dialect — in the hall or on the road.';

/// Marketing/display version. Mirror the exact `version:` in `app/pubspec.yaml`.
const String kAppVersion = '0.1.3';

/// Release identity the strict updater compares with manifest versions.
///
/// Release builds inject the tag-derived SemVer through
/// `CALLERS_COMPENDIUM_RELEASE_VERSION`, so a beta build identifies itself as
/// `X.Y.Z-beta` while the marketing version remains the bare `X.Y.Z` required
/// by `app/pubspec.yaml`. Development and non-release builds use [kAppVersion].
const String kUpdaterVersion = String.fromEnvironment(
  'CALLERS_COMPENDIUM_RELEASE_VERSION',
  defaultValue: kAppVersion,
);

/// The project's canonical source repository. Surfaced in the About section to
/// satisfy the AGPL-3.0 obligation to offer the corresponding source, and used
/// as the "View source" link target.
const String kSourceRepoUrl = 'https://github.com/ibanner56/CallersCompendium';

/// SPDX identifier for the application's own license. The repository is
/// licensed under the GNU Affero General Public License, version 3 (see the
/// top-level `LICENSE` file and the README license badge). The `LICENSE` text
/// is plain AGPLv3 with no "or (at your option) any later version" grant, so
/// the exact SPDX id is `AGPL-3.0-only`.
const String kAppLicenseSpdx = 'AGPL-3.0-only';
