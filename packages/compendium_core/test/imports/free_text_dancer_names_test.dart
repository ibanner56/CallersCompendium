import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Free text reads a dancer in front of a move's name, and a name followed by
/// punctuation (#1857), on top of the whole-line name lookup of #1826.
void main() {
  Figure only(String line, {Dialect? dialect}) {
    final fs = parseFreeTextFigureEntry(line, dialect: dialect);
    expect(fs, hasLength(1), reason: line);
    return fs.single;
  }

  group('a dancer and a move name', () {
    test('`neighbor pass by` and `ones arch and dive` read as the move', () {
      final pass = only('neighbor pass by');
      expect(pass.isCustom, isFalse);
      expect(pass.move, 'pass_by');
      expect(pass.params['who'], 'neighbors');
      expect(pass.assumedSubject, isFalse);
      expect(pass.note, isNull);

      final arch = only('ones arch and dive');
      expect(arch.move, 'arch_and_dive');
      expect(arch.params['who'], 'ones');
      expect(arch.assumedSubject, isFalse);
    });

    test('is case-insensitive and takes a count', () {
      final f = only('(8) Partner MAD ROBIN');
      expect(f.move, 'mad_robin');
      expect(f.params, {'who': 'partners', 'beats': 8});
    });

    test('a name with punctuation after a dancer reads too', () {
      expect(only('Ones arch & dive.').params['who'], 'ones');
    });

    test('a role word is read by its meaning, as in `ravens chain`', () {
      for (final dialect in [null, ...Dialect.presets]) {
        final f = only('ravens mad robin', dialect: dialect);
        expect(f.isCustom, isFalse, reason: dialect?.name);
        expect(f.move, 'mad_robin', reason: dialect?.name);
        expect(f.params['who'], 'role2s', reason: dialect?.name);
      }
      final ravensLarks = Dialect(
        name: 'Custom',
        roles: const {'role1': RoleTerm('raven'), 'role2': RoleTerm('lark')},
      );
      expect(
        only('ravens mad robin', dialect: ravensLarks).params['who'],
        'role1s',
      );
    });

    test('stays custom when the words are not a dancer and a name', () {
      for (final line in [
        // An unknown word in the dancer's place.
        'frobnicators pass by',
        'neighbours pass by',
        // A dancer the move does not take: `slice` has no subject, and
        // `hey` names its dancers in `pass1`, not `who`.
        'neighbor slice',
        'ones hey',
        'ravens hey',
        // A dancer alone, a dancer twice, anything else on the line.
        'neighbor',
        'neighbor neighbor pass by',
        'neighbor pass by twice',
        'then neighbor pass by',
        'neighbor pass by?',
        'ones, arch and dive',
      ]) {
        expect(only(line).isCustom, isTrue, reason: line);
        expect(only(line).params['text'], line, reason: line);
      }
    });
  });

  group('a name followed by punctuation', () {
    test('`hey.` reads as the move', () {
      for (final line in ['hey.', 'Hey!', 'hey,', 'hey;', 'hey...', 'hey .']) {
        final f = only(line);
        expect(f.isCustom, isFalse, reason: line);
        expect(f.move, 'hey', reason: line);
        // `hey` names its dancers in `pass1`, not `who`: nothing is assumed.
        expect(f.params, isEmpty, reason: line);
      }
      expect(only('mad robin.').assumedSubject, isTrue);
      expect(only('mad robin.').move, 'mad_robin');
      expect(only('arch & dive.').move, 'arch_and_dive');
    });

    test('only trailing punctuation is dropped', () {
      for (final line in [
        '.hey',
        'he.y',
        'hey?',
        '"hey"',
        '(hey)',
        '.',
        '!!',
      ]) {
        expect(only(line).isCustom, isTrue, reason: line);
      }
    });
  });

  group('imports and re-check are unchanged', () {
    test('the import fan-out keeps both custom', () {
      for (final line in ['neighbor pass by', 'ones arch and dive', 'hey.']) {
        expect(parseFigureLinesFanOut(line).single.isCustom, isTrue);
      }
    });

    test('Re-check custom figures keeps them custom', () {
      final outcome = reparseImportGapFigures([
        for (final line in ['neighbor pass by', 'ones arch and dive', 'hey.'])
          customFigure(line, origin: CustomOrigin.importGap),
      ]);
      expect(outcome.upgradedCount, 0);
      expect(outcome.figures.every((f) => f.isCustom), isTrue);
    });
  });
}
