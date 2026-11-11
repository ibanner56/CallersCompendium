import 'dart:convert';
import 'dart:math';

/// The default free-space floor: blob and manifest writes are refused with
/// `507` once the data directory's filesystem has less than this available
/// (spec §5.4). 1 GiB is four times what the large-body requests in flight at
/// once can write under [defaultMaxLargeBodiesInFlight] (16 × 16 MiB), so
/// writes already past the check cannot take the disk to zero, and what is
/// left keeps SQLite's journal, the `last_seen` write every request makes, and
/// the deletes that free space working.
const int defaultMinFreeBytes = 1024 * 1024 * 1024;

/// The default number of large-body requests the server handles at once,
/// across every client (spec §5.4). Each can hold up to 16 MiB of decoded body
/// in memory while it is read, decoded and stored.
const int defaultMaxLargeBodiesInFlight = 16;

/// The default number of large-body requests one client address (an IPv4
/// address, or an IPv6 /64) may have in flight at once (spec §5.4). The
/// reference client sends one request at a time, so this leaves room for a
/// few devices behind one address syncing together.
const int defaultMaxLargeBodiesInFlightPerIp = 4;

/// The default time a large-body request's body has to arrive whole before
/// the server gives up on it and closes the connection (spec §5.4). Twice the reference client's 30-second
/// request deadline, so it never cuts off a request that client is still
/// waiting on; its job is to stop a client that trickles a body from holding a
/// large-body slot indefinitely.
const Duration defaultLargeBodyReadTimeout = Duration(seconds: 60);

class AthenaeumConfig {
  AthenaeumConfig({
    required this.dataDirectory,
    required List<int> pepper,
    this.host = '127.0.0.1',
    this.port = 33333,
    this.trustForwardedHeadersFromLoopback = true,
    this.minFreeBytes = defaultMinFreeBytes,
    this.maxLargeBodiesInFlight = defaultMaxLargeBodiesInFlight,
    this.maxLargeBodiesInFlightPerIp = defaultMaxLargeBodiesInFlightPerIp,
    this.largeBodyReadTimeout = defaultLargeBodyReadTimeout,
  }) : pepper = List.unmodifiable(pepper) {
    if (this.pepper.length < 32) {
      throw ArgumentError.value(
        this.pepper.length,
        'pepper',
        'must contain at least 256 bits',
      );
    }
    if (!const {'127.0.0.1', 'localhost'}.contains(host.toLowerCase()) ||
        port < 1 ||
        port > 65535) {
      throw ArgumentError('invalid listener configuration');
    }
    if (minFreeBytes < 0) {
      throw ArgumentError.value(minFreeBytes, 'minFreeBytes', 'must be >= 0');
    }
    if (maxLargeBodiesInFlight < 1) {
      throw ArgumentError.value(
        maxLargeBodiesInFlight,
        'maxLargeBodiesInFlight',
        'must be >= 1',
      );
    }
    if (largeBodyReadTimeout <= Duration.zero) {
      throw ArgumentError.value(
        largeBodyReadTimeout,
        'largeBodyReadTimeout',
        'must be positive',
      );
    }
    if (maxLargeBodiesInFlightPerIp < 1) {
      throw ArgumentError.value(
        maxLargeBodiesInFlightPerIp,
        'maxLargeBodiesInFlightPerIp',
        'must be >= 1',
      );
    }
  }

  factory AthenaeumConfig.fromEnvironment({
    required String dataDirectory,
    String? pepper,
    String host = '127.0.0.1',
    int port = 33333,
    bool trustForwardedHeadersFromLoopback = true,
    int minFreeBytes = defaultMinFreeBytes,
    int maxLargeBodiesInFlight = defaultMaxLargeBodiesInFlight,
    int maxLargeBodiesInFlightPerIp = defaultMaxLargeBodiesInFlightPerIp,
  }) {
    // Runtime configuration only. There is deliberately no compile-time
    // environment default behind this: a `-DATHENAEUM_PEPPER=…` define is baked
    // in by `dart compile exe`, so the binary would carry its deployment secret
    // inside the artifact and start with no pepper configured at all — the
    // built-in pepper, and the failure to refuse, that spec §5.1 forbids
    // (#1359). The runtime environment is read by the caller
    // (`server/bin/athenaeum.dart`) and arrives here as [pepper].
    // `athenaeum_config_test.dart` scans this package's source for the
    // compile-time constructors, so reintroducing one fails there.
    if (pepper == null || pepper.isEmpty) {
      throw ArgumentError('ATHENAEUM_PEPPER or --pepper is required');
    }
    final decoded = _decodePepper(pepper);
    return AthenaeumConfig(
      dataDirectory: dataDirectory,
      pepper: decoded,
      host: host,
      port: port,
      trustForwardedHeadersFromLoopback: trustForwardedHeadersFromLoopback,
      minFreeBytes: minFreeBytes,
      maxLargeBodiesInFlight: maxLargeBodiesInFlight,
      maxLargeBodiesInFlightPerIp: maxLargeBodiesInFlightPerIp,
    );
  }

  final String dataDirectory;
  final List<int> pepper;
  final String host;
  final int port;

  /// Forwarded client-address headers are trusted only when the socket peer is
  /// loopback. This is enabled for the Apache-on-host deployment topology.
  /// When trusted, the *rightmost* `X-Forwarded-For` entry is used, because it
  /// is the one the proxy added; earlier entries are client-supplied. Proxies
  /// must still overwrite the header (single hop), as the deployment docs say.
  final bool trustForwardedHeadersFromLoopback;

  /// Blob and manifest writes are refused with `507` while the filesystem
  /// holding [dataDirectory] has fewer bytes than this available, except a
  /// manifest no larger than the one that device already has, so a user can
  /// still shrink a device's share. Reads and deletes are never refused by it.
  /// Zero turns the floor off. See [defaultMinFreeBytes].
  final int minFreeBytes;

  /// How many large-body requests — a manifest `PUT`, a blob `PUT` single or
  /// batched, and `POST /v1/blobs/missing` — the server handles at once. One
  /// more is answered `503` with `Retry-After`. See
  /// [defaultMaxLargeBodiesInFlight].
  final int maxLargeBodiesInFlight;

  /// How many of those one client address may have in flight at once. One
  /// more is answered `429` with `Retry-After`. See
  /// [defaultMaxLargeBodiesInFlightPerIp].
  final int maxLargeBodiesInFlightPerIp;

  /// How long a large-body request's body has to arrive whole before the
  /// server gives up on it and closes the connection. See
  /// [defaultLargeBodyReadTimeout].
  final Duration largeBodyReadTimeout;

  static List<int> _decodePepper(String value) {
    if (RegExp(r'^(?:[0-9a-fA-F]{2}){32,}$').hasMatch(value)) {
      final result = <int>[];
      for (var index = 0; index < value.length; index += 2) {
        result.add(int.parse(value.substring(index, index + 2), radix: 16));
      }
      if (result.length >= 32) return result;
    }
    try {
      final bytes = base64.decode(value);
      if (bytes.length >= 32) return bytes;
    } on FormatException {
      // A hexadecimal deployment secret is also accepted for shell-friendly
      // configuration, but neither representation has a built-in fallback.
    }
    throw const FormatException(
      'pepper must be at least 32-byte base64 or hex',
    );
  }

  static List<int> generatePepper() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }
}
