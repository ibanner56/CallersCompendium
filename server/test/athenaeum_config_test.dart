import 'dart:io';

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

  // Spec §5.1: the pepper is per-deployment runtime configuration. A server
  // MUST NOT ship a built-in, default or example pepper, and MUST refuse to
  // start when none is configured rather than substituting one.
  //
  // This case documents the refusal, and guards the `null` argument
  // `server/bin/athenaeum.dart:22` passes when neither `--pepper` nor the
  // runtime `ATHENAEUM_PEPPER` variable is set. It is deliberately NOT the
  // guard for the compile-time defect below: the removed fallback was
  // `pepper ?? const String.fromEnvironment('ATHENAEUM_PEPPER')`, which
  // evaluates to the empty string in any build without a `-D` define, so the
  // old code threw here too and this case passes against it (#1359).
  test('refuses to build a config when no pepper is configured', () {
    expect(
      () => AthenaeumConfig.fromEnvironment(dataDirectory: '.'),
      throwsArgumentError,
    );
    expect(
      () => AthenaeumConfig.fromEnvironment(dataDirectory: '.', pepper: null),
      throwsArgumentError,
    );
  });

  // The hazard §5.1 forbids is a property of the BUILD, not of any runtime
  // value: `dart compile exe -DATHENAEUM_PEPPER=<secret>` fixes the constant at
  // compile time, so the artifact ships the secret and starts with nothing
  // configured. No test running against this library can observe that — the
  // define would have to be passed to the test binary itself — so asserting on
  // behaviour would be asserting on nothing. The invariant is instead that no
  // source in this package reads a compile-time value at all, which is what
  // this scan checks.
  //
  // It matches the *property* (any `<T>.fromEnvironment` const constructor),
  // not the one symbol the bug used, so renaming the variable or switching to
  // `bool.fromEnvironment` does not evade it. `Platform.environment` is the
  // correct runtime API and is untouched; `AthenaeumConfig.fromEnvironment` is
  // a named constructor, not the compile-time one, and does not match.
  //
  // The match runs over the WHOLE source, not line by line, and tolerates
  // whitespace inside the constructor. A line-at-a-time scan reads as though it
  // matched the property while actually matching one spelling of it: a formatter
  // (or an author) may wrap the expression as `const String\n
  // .fromEnvironment('ATHENAEUM_PEPPER')`, which is the same construct and
  // evades a per-line regex entirely. That was not hypothetical — this test was
  // first written that way, and stayed green with exactly that fallback present
  // in `athenaeum_config.dart`.
  //
  // The scan deliberately does not strip comments: stripping `//` to end of line
  // would also truncate a line holding `//` inside a string literal and could
  // hide a real match after it, and a guard that can fail to see the thing it
  // guards is worse than one that occasionally complains about prose. A comment
  // that spells a compile-time constructor out in full therefore fails here too,
  // and should be reworded.
  test('no source in this package reads compile-time configuration', () {
    final root = Directory('server').existsSync() ? 'server' : '.';
    final pattern = RegExp(
      r'\b(?:String|int|bool|double)\s*\.\s*fromEnvironment\s*\(',
    );
    final offenders = <String>[];
    for (final directory in ['$root/lib', '$root/bin']) {
      for (final entity in Directory(directory).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final match in pattern.allMatches(source)) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length;
          // The match may span lines, so collapse its whitespace before
          // reporting it — otherwise the failure prints a broken fragment.
          final snippet = source
              .substring(match.start, match.end)
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          offenders.add('${entity.path}:${line + 1}: $snippet');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Spec §5.1 forbids a built-in or compiled-in deployment secret. '
          'These read a value fixed at build time; read the runtime '
          'environment instead (see server/bin/athenaeum.dart):\n'
          '${offenders.join('\n')}',
    );
  });

  test('decodes an unambiguous hexadecimal pepper before base64', () {
    final config = AthenaeumConfig.fromEnvironment(
      dataDirectory: '.',
      pepper: '00' * 32,
    );
    expect(config.pepper, List<int>.filled(32, 0));
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

  test('trusts forwarded addresses only from loopback peers by default', () {
    expect(
      AthenaeumConfig(
        dataDirectory: '.',
        pepper: List<int>.filled(32, 0),
      ).trustForwardedHeadersFromLoopback,
      isTrue,
    );
    expect(
      AthenaeumConfig(
        dataDirectory: '.',
        pepper: List<int>.filled(32, 0),
        trustForwardedHeadersFromLoopback: false,
      ).trustForwardedHeadersFromLoopback,
      isFalse,
    );
  });

  test('generatePepper uses a full 256-bit value', () {
    expect(AthenaeumConfig.generatePepper(), hasLength(32));
  });
}
