/// Static app identity used by the About/Licenses section (settings) and any
/// other in-app attribution surface.
///
/// The version is kept as a plain constant rather than read at runtime via a
/// plugin (e.g. `package_info_plus`): the app has no existing runtime version
/// mechanism, and pulling in a platform plugin purely to echo the pubspec
/// version would add build/test surface for no functional gain. This constant
/// is the single in-code source of truth and **must be kept in step with the
/// `version:` field in `app/pubspec.yaml`** (currently `0.1.0+1`).
library;

/// Human-facing application name.
const String kAppName = "Caller's Compendium";

/// Marketing/display version. Mirror the `version:` in `app/pubspec.yaml`
/// (the leading semver, without the `+build` suffix).
const String kAppVersion = '0.1.0';

/// The project's canonical source repository. Surfaced in the About section to
/// satisfy the AGPL-3.0 obligation to offer the corresponding source, and used
/// as the "View source" link target.
const String kSourceRepoUrl = 'https://github.com/ibanner56/CallersCompendium';

/// SPDX identifier for the application's own license. The repository is
/// licensed under the GNU Affero General Public License, version 3 (see the
/// top-level `LICENSE` file and the README license badge).
const String kAppLicenseSpdx = 'AGPL-3.0';
