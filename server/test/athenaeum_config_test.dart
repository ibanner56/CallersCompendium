import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:test/test.dart';

void main() {
  test('requires a 256-bit pepper', () {
    expect(
      () =>
          AthenaeumConfig(dataDirectory: '.', pepper: List<int>.filled(31, 0)),
      throwsArgumentError,
    );
    expect(
      () => AthenaeumConfig.fromEnvironment(dataDirectory: '.', pepper: ''),
      throwsArgumentError,
    );
    expect(
      () =>
          AthenaeumConfig.fromEnvironment(dataDirectory: '.', pepper: 'a' * 65),
      throwsFormatException,
    );
  });

  test('only allows loopback listener hosts', () {
    expect(
      () => AthenaeumConfig(
        dataDirectory: '.',
        pepper: List<int>.filled(32, 0),
        host: '0.0.0.0',
      ),
      throwsArgumentError,
    );
    expect(
      () => AthenaeumConfig(
        dataDirectory: '.',
        pepper: List<int>.filled(32, 0),
        host: '127.0.0.1',
      ),
      returnsNormally,
    );
  });

  test('generatePepper uses a full 256-bit value', () {
    expect(AthenaeumConfig.generatePepper(), hasLength(32));
  });
}
