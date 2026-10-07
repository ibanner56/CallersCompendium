/// Pure-Dart model of the ADR-002 §2 update manifest (the feed contract shared
/// by the release workflow that *writes* it and this client that *reads* it).
///
/// Everything here is dependency-free and I/O-free (only `dart:convert`): the
/// schema parse, the `manifestSchemaVersion` guard, the channel check, and the
/// client-side platform/arch artifact selection are all unit-testable without
/// Flutter or a network (ADR-001 pure-core rule, ADR-002 §8).
library;

import 'dart:convert';

import 'semver.dart';

/// The single manifest-schema version this client understands. The client
/// **hard-refuses** any other value rather than guessing (ADR-002 §2); a
/// breaking schema change increments this and re-ratifies the contract.
const int kSupportedManifestSchemaVersion = 1;

/// The two release channels (ADR-002 §3). Beta is an opt-in Settings toggle,
/// default off (stable).
enum UpdateChannel {
  stable('stable'),
  beta('beta');

  const UpdateChannel(this.wire);

  /// The on-the-wire string used in the manifest `channel` field and the
  /// `<channel>.json` filename.
  final String wire;

  /// Parses a manifest `channel` string, or `null` when unrecognized.
  static UpdateChannel? fromWire(String value) {
    for (final c in UpdateChannel.values) {
      if (c.wire == value) return c;
    }
    return null;
  }
}

/// A target platform in an artifact entry (ADR-002 §2).
enum UpdatePlatform {
  linux('linux'),
  macos('macos'),
  windows('windows'),
  android('android'),
  ios('ios');

  const UpdatePlatform(this.wire);

  final String wire;

  static UpdatePlatform? fromWire(String value) {
    for (final p in UpdatePlatform.values) {
      if (p.wire == value) return p;
    }
    return null;
  }
}

/// A target CPU architecture in an artifact entry (ADR-002 §2).
enum UpdateArch {
  x64('x64'),
  arm64('arm64'),
  universal('universal');

  const UpdateArch(this.wire);

  final String wire;

  static UpdateArch? fromWire(String value) {
    for (final a in UpdateArch.values) {
      if (a.wire == value) return a;
    }
    return null;
  }
}

/// Raised when a manifest cannot be trusted: malformed/partial JSON, an
/// unrecognized [kSupportedManifestSchemaVersion], a channel that disagrees with
/// the file it came from, or a missing/invalid required field. Callers treat
/// this as a **silent no-op** (never an error dialog) per ADR-002 §5 — the
/// [message] exists only for tests/logging, not the UI.
class UpdateManifestFormatException implements Exception {
  const UpdateManifestFormatException(this.message);

  final String message;

  @override
  String toString() => 'UpdateManifestFormatException: $message';
}

/// One downloadable artifact: `{platform, arch, url, sha256, size,
/// minOsVersion?}` (ADR-002 §2). Stage 1 does not download or verify anything,
/// but the model carries `sha256`/`size` so the assisted-download stage (A11b)
/// can reuse it unchanged.
class UpdateArtifact {
  const UpdateArtifact({
    required this.platform,
    required this.arch,
    required this.url,
    required this.sha256,
    required this.size,
    this.minOsVersion,
  });

  final UpdatePlatform platform;
  final UpdateArch arch;
  final String url;
  final String sha256;
  final int size;
  final String? minOsVersion;

  static UpdateArtifact _fromJson(Object? node) {
    if (node is! Map<String, Object?>) {
      throw const UpdateManifestFormatException('artifact is not an object');
    }
    final platform = _requireString(node, 'platform');
    final arch = _requireString(node, 'arch');
    final parsedPlatform = UpdatePlatform.fromWire(platform);
    final parsedArch = UpdateArch.fromWire(arch);
    if (parsedPlatform == null) {
      throw UpdateManifestFormatException('unknown platform "$platform"');
    }
    if (parsedArch == null) {
      throw UpdateManifestFormatException('unknown arch "$arch"');
    }
    final size = node['size'];
    if (size is! int) {
      throw const UpdateManifestFormatException('artifact.size must be an int');
    }
    // Reject a non-positive size at the trust boundary: `0`/negative would
    // otherwise disable the downloader's byte-count integrity check (which only
    // runs when `size > 0`) and let a truncated/empty artifact look complete
    // (OWASP A08 — Software & Data Integrity Failures).
    if (size <= 0) {
      throw const UpdateManifestFormatException(
        'artifact.size must be a positive int',
      );
    }
    final minOs = node['minOsVersion'];
    if (minOs != null && minOs is! String) {
      throw const UpdateManifestFormatException(
        'artifact.minOsVersion must be a string',
      );
    }
    return UpdateArtifact(
      platform: parsedPlatform,
      arch: parsedArch,
      url: _requireHttpsUrl(node, 'url'),
      sha256: _requireString(node, 'sha256'),
      size: size,
      minOsVersion: minOs as String?,
    );
  }
}

/// One end-of-life announcement from the manifest's optional `retirements`
/// list (ADR-002 §2): every build whose release identity is **at or below**
/// [through] (SemVer precedence, so `0.7.0-beta` is covered by `0.7.0`) stops
/// being supported on [endOfLife].
///
/// The field is additive — builds up to and including 0.6.0-beta parse the
/// manifest without reading it, so they never see a notice; every later build
/// does.
class UpdateRetirement {
  const UpdateRetirement({required this.through, required this.endOfLife});

  /// The newest release identity this notice retires (inclusive).
  final SemVer through;

  /// The announced end-of-life day, as a calendar date with no time zone: a
  /// UTC-midnight [DateTime] whose year/month/day are the published
  /// `YYYY-MM-DD`. Callers compare and display it as a date, never as an
  /// instant.
  final DateTime endOfLife;

  /// Whether the build identified by [version] is covered by this notice.
  bool appliesTo(SemVer version) => !version.isNewerThan(through);

  static final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Parses a `YYYY-MM-DD` calendar date, or `null` when [value] is not one
  /// (including impossible dates such as `2027-02-30`, which [DateTime] would
  /// otherwise silently roll over into March).
  static DateTime? parseDate(String value) {
    final match = _isoDate.firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  /// The exact key set of an entry. Anything else — a typo such as
  /// `endofLife` beside `endOfLife` included — is malformed, matching the
  /// producer (`gen_release_metadata.py`), which refuses unknown keys.
  static const Set<String> _keys = {'through', 'endOfLife'};

  static UpdateRetirement _fromJson(Object? node) {
    if (node is! Map<String, Object?>) {
      throw const UpdateManifestFormatException('retirement is not an object');
    }
    final unknown = node.keys.where((k) => !_keys.contains(k));
    if (unknown.isNotEmpty) {
      throw UpdateManifestFormatException(
        'retirement has unknown keys ${unknown.toList()}',
      );
    }
    final throughStr = _requireString(node, 'through');
    final through = SemVer.tryParse(throughStr);
    if (through == null) {
      throw UpdateManifestFormatException(
        'invalid retirement.through "$throughStr"',
      );
    }
    final dateStr = _requireString(node, 'endOfLife');
    final endOfLife = parseDate(dateStr);
    if (endOfLife == null) {
      throw UpdateManifestFormatException(
        'invalid retirement.endOfLife "$dateStr" (expected YYYY-MM-DD)',
      );
    }
    return UpdateRetirement(through: through, endOfLife: endOfLife);
  }
}

/// A parsed, validated update manifest (ADR-002 §2).
class UpdateManifest {
  const UpdateManifest({
    required this.manifestSchemaVersion,
    required this.channel,
    required this.version,
    required this.releaseNotesUrl,
    required this.pubDate,
    required this.artifacts,
    this.retirements = const <UpdateRetirement>[],
  });

  final int manifestSchemaVersion;
  final UpdateChannel channel;
  final SemVer version;
  final String releaseNotesUrl;

  /// The RFC3339 UTC publication timestamp, parsed from the manifest `pubDate`.
  final DateTime pubDate;

  final List<UpdateArtifact> artifacts;

  /// The optional end-of-life announcements (`retirements`); empty when the
  /// manifest carries none.
  final List<UpdateRetirement> retirements;

  /// Parses [source] as an ADR-002 §2 manifest and validates it against
  /// [expectedChannel] (the channel whose file was fetched — `stable.json` →
  /// [UpdateChannel.stable]).
  ///
  /// Throws [UpdateManifestFormatException] — which callers treat as a silent
  /// no-op — when the JSON is malformed/partial, when
  /// `manifestSchemaVersion` is not [kSupportedManifestSchemaVersion], when
  /// `channel` disagrees with [expectedChannel], when any required field is
  /// missing or the wrong type, or when an optional `retirements` list is
  /// present but malformed (the producer validates it, so a malformed list
  /// means the file is not what the release workflow wrote).
  static UpdateManifest parse(
    String source, {
    required UpdateChannel expectedChannel,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      // diagnostics: silent — converts invalid-JSON FormatException to UpdateManifestFormatException and rethrows
      throw UpdateManifestFormatException('invalid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const UpdateManifestFormatException('root is not a JSON object');
    }

    // Refuse an unrecognized schema version *before* trusting any other field.
    final schema = decoded['manifestSchemaVersion'];
    if (schema is! int) {
      throw const UpdateManifestFormatException(
        'manifestSchemaVersion missing or not an int',
      );
    }
    if (schema != kSupportedManifestSchemaVersion) {
      throw UpdateManifestFormatException(
        'unsupported manifestSchemaVersion $schema '
        '(expected $kSupportedManifestSchemaVersion)',
      );
    }

    final channelStr = _requireString(decoded, 'channel');
    final channel = UpdateChannel.fromWire(channelStr);
    if (channel == null) {
      throw UpdateManifestFormatException('unknown channel "$channelStr"');
    }
    if (channel != expectedChannel) {
      throw UpdateManifestFormatException(
        'channel "$channelStr" does not match requested '
        '"${expectedChannel.wire}"',
      );
    }

    final versionStr = _requireString(decoded, 'version');
    final version = SemVer.tryParse(versionStr);
    if (version == null) {
      throw UpdateManifestFormatException('invalid version "$versionStr"');
    }

    final pubDateStr = _requireString(decoded, 'pubDate');
    final pubDate = DateTime.tryParse(pubDateStr);
    if (pubDate == null) {
      throw UpdateManifestFormatException('invalid pubDate "$pubDateStr"');
    }

    final rawArtifacts = decoded['artifacts'];
    if (rawArtifacts is! List || rawArtifacts.isEmpty) {
      throw const UpdateManifestFormatException(
        'artifacts must be a non-empty list',
      );
    }
    final artifacts = rawArtifacts
        .map(UpdateArtifact._fromJson)
        .toList(growable: false);

    // Absent means "none"; present means a list. An explicit `null` is not
    // something the producer writes, so it is malformed rather than absent.
    final rawRetirements = decoded.containsKey('retirements')
        ? decoded['retirements']
        : const <Object?>[];
    if (rawRetirements is! List) {
      throw const UpdateManifestFormatException('retirements must be a list');
    }
    final retirements = rawRetirements
        .map(UpdateRetirement._fromJson)
        .toList(growable: false);

    return UpdateManifest(
      manifestSchemaVersion: schema,
      channel: channel,
      version: version,
      releaseNotesUrl: _requireHttpsUrl(decoded, 'releaseNotesUrl'),
      pubDate: pubDate,
      artifacts: artifacts,
      retirements: retirements,
    );
  }

  /// The end-of-life date announced for the build identified by [version], or
  /// `null` when no retirement covers it. When several entries cover the same
  /// build the **earliest** date wins: the strictest announcement is the one
  /// the user must meet.
  DateTime? endOfLifeFor(SemVer version) {
    DateTime? earliest;
    for (final r in retirements) {
      if (!r.appliesTo(version)) continue;
      if (earliest == null || r.endOfLife.isBefore(earliest)) {
        earliest = r.endOfLife;
      }
    }
    return earliest;
  }

  /// Selects the artifact matching the running [platform] and [arch]
  /// **client-side, after the manifest was fetched** — so the server never
  /// learns the user's platform/arch (ADR-002 §5). Returns `null` when no
  /// entry matches (e.g. an arch the release did not build).
  ///
  /// A `universal` artifact for the platform matches any requested [arch], so
  /// the exact-arch match is preferred and the `universal` entry is the
  /// fallback.
  UpdateArtifact? selectArtifact(UpdatePlatform platform, UpdateArch arch) {
    UpdateArtifact? universalFallback;
    for (final a in artifacts) {
      if (a.platform != platform) continue;
      if (a.arch == arch) return a;
      if (a.arch == UpdateArch.universal) universalFallback ??= a;
    }
    return universalFallback;
  }
}

/// Reads a required string field, throwing [UpdateManifestFormatException]
/// (a silent-no-op signal) when it is absent or not a string.
String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw UpdateManifestFormatException('$key missing or not a string');
  }
  return value;
}

/// Reads a required URL field and validates it is a well-formed **https** URL
/// with a non-empty host, throwing [UpdateManifestFormatException] otherwise.
///
/// Enforcing TLS at the ingest boundary is defense-in-depth (OWASP A08 —
/// Software & Data Integrity Failures) alongside the mandatory sha256 gate: a
/// tampered or transport-downgraded manifest can never steer the client at a
/// cleartext (`http://`) or non-web (`file:`/`javascript:`) artifact- or
/// release-notes URL. The release workflow already publishes only `https://`
/// URLs, so this rejects nothing legitimate.
String _requireHttpsUrl(Map<String, Object?> json, String key) {
  final value = _requireString(json, key);
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) {
    throw UpdateManifestFormatException('$key must be an https URL');
  }
  return value;
}
