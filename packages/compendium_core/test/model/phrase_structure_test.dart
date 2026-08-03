import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

void main() {
  group('PhraseStructure.parse', () {
    test('empty string is the standard 4x16 structure', () {
      final s = PhraseStructure.parse('');
      expect(s, same(PhraseStructure.standard));
      expect(s.phraseCount, 4);
      expect(s.beatsPerPhrase, 16);
      expect(s.totalBeats, 64);
      expect(s.labels, ['A1', 'A2', 'B1', 'B2']);
    });

    test('whitespace-only string is standard too', () {
      expect(PhraseStructure.parse('  '), PhraseStructure.standard);
    });

    test('explicit 4*8*2 equals the standard structure', () {
      expect(PhraseStructure.parse('4*8*2'), PhraseStructure.standard);
    });

    test('parses TCB convention for a 48-bar dance', () {
      final s = PhraseStructure.parse('6*8*2');
      expect(s.phraseCount, 6);
      expect(s.beatsPerPhrase, 16);
      expect(s.totalBeats, 96);
      expect(s.labels, ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']);
    });

    test(
      'odd phrase counts label the trailing phrase with the next letter',
      () {
        expect(PhraseStructure.parse('3*8*2').labels, ['A1', 'A2', 'B1']);
      },
    );

    test('rejects malformed input', () {
      for (final bad in ['4*8', '4*8*2*1', 'abc', '4*x*2', '0*8*2', '-4*8*2']) {
        expect(
          () => PhraseStructure.parse(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('round-trips its raw representation', () {
      expect(PhraseStructure.parse('6*8*2').raw, '6*8*2');
      expect(PhraseStructure.standard.raw, '');
    });
  });

  group('labelAtBeat', () {
    final std = PhraseStructure.standard;

    test('maps beats to phrases', () {
      expect(std.labelAtBeat(0), 'A1');
      expect(std.labelAtBeat(15), 'A1');
      expect(std.labelAtBeat(16), 'A2');
      expect(std.labelAtBeat(32), 'B1');
      expect(std.labelAtBeat(63), 'B2');
    });

    test('wraps past the end (dance repeats to the tune)', () {
      expect(std.labelAtBeat(64), 'A1');
      expect(std.labelAtBeat(80), 'A2');
    });

    test('rejects negative beats', () {
      expect(() => std.labelAtBeat(-1), throwsArgumentError);
    });
  });

  group('deriveSections', () {
    Figure fig(int beats) =>
        testFigure(move: 'swing', params: {'beats': beats});

    test('assigns start beats and labels cumulatively', () {
      final sections = deriveSections([
        fig(8),
        fig(8),
        fig(16),
        fig(16),
        fig(16),
      ], PhraseStructure.standard);
      expect(sections.map((s) => s.startBeat), [0, 8, 16, 32, 48]);
      expect(sections.map((s) => s.label), ['A1', 'A1', 'A2', 'B1', 'B2']);
      expect(sections.map((s) => s.index), [0, 1, 2, 3, 4]);
    });

    test('figure spanning a boundary is labeled by its start phrase', () {
      final sections = deriveSections([
        fig(12),
        fig(8),
      ], PhraseStructure.standard);
      expect(sections[1].label, 'A1'); // starts at beat 12, spans into A2
    });

    test('exact fit produces no issues', () {
      final issues = <ValidationIssue>[];
      deriveSections(
        [fig(32), fig(32)],
        PhraseStructure.standard,
        issues: issues,
      );
      expect(issues, isEmpty);
    });

    test('overflow is a warning, never an error', () {
      final issues = <ValidationIssue>[];
      deriveSections(
        [fig(32), fig(40)],
        PhraseStructure.standard,
        issues: issues,
      );
      expect(issues, hasLength(1));
      expect(issues.single.severity, ValidationSeverity.warning);
      expect(issues.single.code, 'phrase_overflow');
    });

    test('underflow is a warning', () {
      final issues = <ValidationIssue>[];
      deriveSections([fig(32)], PhraseStructure.standard, issues: issues);
      expect(issues.single.code, 'phrase_underflow');
    });

    test('empty figure list yields no sections and no issues', () {
      final issues = <ValidationIssue>[];
      expect(
        deriveSections([], PhraseStructure.standard, issues: issues),
        isEmpty,
      );
      expect(issues, isEmpty);
    });
  });
}
