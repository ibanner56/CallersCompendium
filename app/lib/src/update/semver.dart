/// Pure-Dart Semantic Versioning value type used by the update client (ADR-002
/// §2/§8). Kept dependency-free and I/O-free so the version comparison at the
/// heart of the update check is unit-testable without Flutter or a network.
///
/// `pub_semver` is only a *transitive* dependency of the workspace; Stage 1
/// deliberately adds no new dependency, and the ADR calls for the SemVer
/// compare to live in this pure-Dart model, so it is implemented here against
/// the Semantic Versioning 2.0.0 spec (<https://semver.org>).
library;

/// A parsed [Semantic Version](https://semver.org): `MAJOR.MINOR.PATCH`, with
/// an optional dot-separated pre-release series and `+build` metadata.
///
/// Ordering follows spec §11: numeric identifiers compare numerically,
/// alphanumeric identifiers compare in ASCII sort order, a version *with* a
/// pre-release is lower than the same version without one, and when all shared
/// pre-release identifiers are equal the version with *more* identifiers is
/// higher. Build metadata (`+…`) is ignored for precedence (§10).
class SemVer implements Comparable<SemVer> {
  const SemVer({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease = const <String>[],
    this.build = '',
  });

  final int major;
  final int minor;
  final int patch;

  /// The dot-separated pre-release identifiers (e.g. `['rc', '1']` for
  /// `-rc.1`), or an empty list for a normal release.
  final List<String> preRelease;

  /// The raw build-metadata string after `+` (without the `+`), or `''` when
  /// absent. Never affects ordering or equality precedence.
  final String build;

  /// Whether this version carries a pre-release suffix (e.g. `0.2.0-rc.1`).
  bool get isPreRelease => preRelease.isNotEmpty;

  /// A run of ASCII digits (a numeric core / pre-release identifier).
  static final RegExp _numeric = RegExp(r'^\d+$');

  /// One legal pre-release/build identifier: `[0-9A-Za-z-]`, non-empty.
  static final RegExp _identifier = RegExp(r'^[0-9A-Za-z-]+$');

  /// Parses [input] into a [SemVer], returning `null` when it is not a valid
  /// `MAJOR.MINOR.PATCH[-prerelease][+build]` string. Lenient only about
  /// surrounding whitespace and a single leading `v`/`V` (a common release-tag
  /// convention); everything else must conform so a malformed manifest
  /// `version` is rejected rather than silently mis-parsed.
  static SemVer? tryParse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }

    // Split off build metadata (+…) first, then the pre-release (-…).
    String? build;
    final plus = text.indexOf('+');
    if (plus >= 0) {
      build = text.substring(plus + 1);
      text = text.substring(0, plus);
      // Build identifiers allow leading zeros (spec §10).
      if (build.isEmpty ||
          !_isValidDotSeries(build, numericLeadingZeroOk: true)) {
        return null;
      }
    }

    List<String> pre = const <String>[];
    final dash = text.indexOf('-');
    if (dash >= 0) {
      final preText = text.substring(dash + 1);
      text = text.substring(0, dash);
      if (preText.isEmpty || !_isValidDotSeries(preText)) return null;
      pre = preText.split('.');
    }

    final parts = text.split('.');
    if (parts.length != 3) return null;
    final nums = <int>[];
    for (final p in parts) {
      if (!_numeric.hasMatch(p)) return null;
      // Reject leading zeros on multi-digit core identifiers (spec §2).
      if (p.length > 1 && p.startsWith('0')) return null;
      final n = int.tryParse(p);
      if (n == null) return null;
      nums.add(n);
    }

    return SemVer(
      major: nums[0],
      minor: nums[1],
      patch: nums[2],
      preRelease: pre,
      build: build ?? '',
    );
  }

  /// Whether every dot-separated identifier in [series] is a legal pre-release/
  /// build identifier: non-empty, `[0-9A-Za-z-]` only, and (for pre-release
  /// numeric identifiers) no leading zeros unless [numericLeadingZeroOk].
  static bool _isValidDotSeries(
    String series, {
    bool numericLeadingZeroOk = false,
  }) {
    for (final id in series.split('.')) {
      if (id.isEmpty) return false;
      if (!_identifier.hasMatch(id)) return false;
      if (!numericLeadingZeroOk &&
          id.length > 1 &&
          _numeric.hasMatch(id) &&
          id.startsWith('0')) {
        return false;
      }
    }
    return true;
  }

  /// Returns `true` when this version is strictly greater than [other] by
  /// SemVer precedence — i.e. [other] should update *to* this version.
  bool isNewerThan(SemVer other) => compareTo(other) > 0;

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return _comparePreRelease(preRelease, other.preRelease);
  }

  /// Compares two pre-release identifier lists per spec §11.4. An empty list
  /// (a normal release) ranks *higher* than any non-empty one.
  static int _comparePreRelease(List<String> a, List<String> b) {
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty) return 1; // release > pre-release
    if (b.isEmpty) return -1;
    final shared = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < shared; i++) {
      final cmp = _compareIdentifier(a[i], b[i]);
      if (cmp != 0) return cmp;
    }
    // All shared identifiers equal: the longer set has higher precedence.
    return a.length.compareTo(b.length);
  }

  static int _compareIdentifier(String a, String b) {
    final aNum = _numeric.hasMatch(a);
    final bNum = _numeric.hasMatch(b);
    if (aNum && bNum) return int.parse(a).compareTo(int.parse(b));
    // Numeric identifiers always have lower precedence than alphanumeric.
    if (aNum) return -1;
    if (bNum) return 1;
    return a.compareTo(b);
  }

  /// The canonical `MAJOR.MINOR.PATCH[-pre][+build]` string.
  @override
  String toString() {
    final buffer = StringBuffer('$major.$minor.$patch');
    if (preRelease.isNotEmpty) buffer.write('-${preRelease.join('.')}');
    if (build.isNotEmpty) buffer.write('+$build');
    return buffer.toString();
  }

  /// Equality by precedence (build metadata ignored, per §10) — two versions
  /// that differ only in `+build` are considered equal.
  @override
  bool operator ==(Object other) => other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode =>
      Object.hash(major, minor, patch, Object.hashAll(preRelease));
}
