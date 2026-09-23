import 'dart:convert';
import 'dart:math';

class AthenaeumConfig {
  AthenaeumConfig({
    required this.dataDirectory,
    required List<int> pepper,
    this.host = '127.0.0.1',
    this.port = 33333,
    this.trustForwardedHeadersFromLoopback = true,
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
  }

  factory AthenaeumConfig.fromEnvironment({
    required String dataDirectory,
    String? pepper,
    String host = '127.0.0.1',
    int port = 33333,
    bool trustForwardedHeadersFromLoopback = true,
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
    );
  }

  final String dataDirectory;
  final List<int> pepper;
  final String host;
  final int port;

  /// Forwarded client-address headers are trusted only when the socket peer is
  /// loopback. This is enabled for the Apache-on-host deployment topology.
  final bool trustForwardedHeadersFromLoopback;

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
