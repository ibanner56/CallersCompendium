import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// How the Caller's Box bridge treats a near miss, a reading that compiled
/// only one column off ([WarningKind.endedColumnOffset]): it tries the
/// record's next placement, and takes that placement only if it compiles and
/// is not a near miss too (agent's call). A compile from an allemande's short
/// waves ([WarningKind.allemandeWaveRetry]) is a plain pass *(user-ruled
/// 2026-11-25)*.
void main() {
  const offset = [Warning(WarningKind.endedColumnOffset, detail: 'x')];
  const none = <Warning>[];

  group('triesAnotherReading', () {
    test('after a near miss', () {
      expect(triesAnotherReading(DanceOutcome.compiled, offset), isTrue);
    });

    test('not after an exact compile', () {
      expect(triesAnotherReading(DanceOutcome.compiled, none), isFalse);
    });

    test('not after a compile that needed an allemande\'s short waves', () {
      const waves = [Warning(WarningKind.allemandeWaveRetry, detail: 'x')];
      expect(triesAnotherReading(DanceOutcome.compiled, waves), isFalse);
    });

    test('after a mismatch, but never after a crash', () {
      expect(triesAnotherReading(DanceOutcome.mismatch, none), isTrue);
      expect(triesAnotherReading(DanceOutcome.crashed, none), isFalse);
    });
  });

  group('retryReplaces', () {
    test('an exact retry replaces a near miss', () {
      expect(
        retryReplaces(
          current: (DanceOutcome.compiled, offset),
          retry: (DanceOutcome.compiled, none),
        ),
        isTrue,
      );
    });

    test('a near-miss retry does not replace a near miss', () {
      expect(
        retryReplaces(
          current: (DanceOutcome.compiled, offset),
          retry: (DanceOutcome.compiled, offset),
        ),
        isFalse,
      );
    });

    test('a near-miss retry replaces a mismatch', () {
      expect(
        retryReplaces(
          current: (DanceOutcome.mismatch, none),
          retry: (DanceOutcome.compiled, offset),
        ),
        isTrue,
      );
    });

    test('a retry that does not compile replaces nothing', () {
      expect(
        retryReplaces(
          current: (DanceOutcome.compiled, offset),
          retry: (DanceOutcome.mismatch, none),
        ),
        isFalse,
      );
    });
  });
}
