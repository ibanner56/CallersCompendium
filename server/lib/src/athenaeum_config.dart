import 'dart:convert';
import 'dart:math';

class AthenaeumConfig {
  AthenaeumConfig({
    required this.dataDirectory,
    required List<int> pepper,
    this.host = '127.0.0.1',
    this.port = 33333,
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
  }) {
    final encoded = pepper ?? const String.fromEnvironment('ATHENAEUM_PEPPER');
    if (encoded.isEmpty) {
      throw ArgumentError('ATHENAEUM_PEPPER or --pepper is required');
    }
    final decoded = _decodePepper(encoded);
    return AthenaeumConfig(
      dataDirectory: dataDirectory,
      pepper: decoded,
      host: host,
      port: port,
    );
  }

  final String dataDirectory;
  final List<int> pepper;
  final String host;
  final int port;

  static List<int> _decodePepper(String value) {
    try {
      final bytes = base64.decode(value);
      if (bytes.length >= 32) return bytes;
    } on FormatException {
      // A hexadecimal deployment secret is also accepted for shell-friendly
      // configuration, but neither representation has a built-in fallback.
    }
    if (RegExp(r'^[0-9a-fA-F]{64,}$').hasMatch(value)) {
      final result = <int>[];
      for (var index = 0; index < value.length; index += 2) {
        result.add(int.parse(value.substring(index, index + 2), radix: 16));
      }
      if (result.length >= 32) return result;
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
