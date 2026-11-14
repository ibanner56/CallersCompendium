import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// The third and fourth couples' dancers (taxonomy v39): `threesRole1`,
/// `threesRole2`, `foursRole1` and `foursRole2`, after the ones and twos at
/// the end of the dancer vocabulary.
void main() {
  const added = ['threesRole1', 'threesRole2', 'foursRole1', 'foursRole2'];
  final renderer = FigureRenderer(contraTaxonomy);
  final dialects = [Dialect.canonical, ...Dialect.presets];

  test('they end the dancer list, after the ones and twos', () {
    expect(ParamVocab.singleDancers, [
      'onesRole1',
      'onesRole2',
      'twosRole1',
      'twosRole2',
      ...added,
    ]);
    expect(
      ParamVocab.dancerSets.sublist(ParamVocab.dancerSets.length - 4),
      added,
    );
  });

  test('any dancer param takes them, and so do the single-dancer params', () {
    // Maintainer decision: the figure 8's lead and the dolphin hey's dolphin
    // name any single dancer, the third and fourth couples' included.
    const any = ParamSpec(ParamKind.dancerSet, defaultValue: 'role1s');
    for (final token in added) {
      expect(any.validate(token), isTrue, reason: token);
      for (final (move, param) in [
        ('figure_8', 'lead'),
        ('dolphin_hey', 'whom'),
      ]) {
        expect(
          contraTaxonomy.moves[move]!.params[param]!.validate(token),
          isTrue,
          reason: '$move.$param $token',
        );
      }
    }
  });

  test('a figure naming one reads back from its own display, '
      'under every shipped dialect', () {
    // Mutation caught: dropping a reader's third/fourth entry (the free-text
    // parser, the typed-name table or the display-subject reader), or
    // `fourth` from the role canonicalizer's determiners, which leaves
    // "fourth follow" a verb under Leads/Follows.
    final figures = [
      testFigure(move: 'swing', params: {'who': 'threesRole1'}),
      testFigure(move: 'allemande', params: {'who': 'foursRole2'}),
      testFigure(move: 'do_si_do', params: {'who': 'threesRole2'}),
      testFigure(move: 'pass_by', params: {'who': 'foursRole1'}),
      testFigure(move: 'orbit', params: {'who': 'threesRole1'}),
      testFigure(
        move: 'gate',
        params: {'who': 'foursRole1', 'whom': 'threesRole2'},
      ),
      testFigure(
        move: 'figure_8',
        params: {'who': 'ones', 'where': 'above', 'lead': 'threesRole2'},
      ),
      testFigure(
        move: 'figure_8',
        params: {'who': 'ones', 'where': 'above', 'lead': 'foursRole1'},
      ),
      testFigure(
        move: 'dolphin_hey',
        params: {'who': 'ones', 'whom': 'foursRole2'},
      ),
      testFigure(
        move: 'dolphin_hey',
        params: {'who': 'ones', 'whom': 'threesRole1'},
      ),
      testFigure(
        move: 'starburst',
        params: {
          'direction': 'clockwise',
          'travel': 2,
          'who': 'threesRole1',
          'whom': 'foursRole2',
        },
      ),
    ];
    for (final dialect in dialects) {
      for (final figure in figures) {
        final line = renderer.renderSummary(figure, dialect);
        final read = parseFreeTextFigureEntry(line, dialect: dialect);
        final reason = '${dialect.name}: $line';
        expect(read, hasLength(1), reason: reason);
        expect(read.single.isCustom, isFalse, reason: reason);
        expect(read.single.move, figure.move, reason: reason);
        for (final key in ['who', 'whom', 'lead']) {
          if (figure.params[key] case final String token) {
            expect(read.single.params[key], token, reason: reason);
          }
        }
      }
    }
  });

  test('one in front of a bare move name reads as its subject', () {
    // Mutation caught: dropping a third/fourth entry from the typed-name
    // table, which leaves `fourth robin mad robin` custom text.
    for (final dialect in dialects) {
      for (final token in added) {
        final dancer = FigureRenderer.singleDancerDefaultTerm(token, dialect)!;
        for (final (name, move) in [
          ('arch and dive', 'arch_and_dive'),
          ('mad robin', 'mad_robin'),
          ('gate', 'gate'),
        ]) {
          final line = '$dancer $name';
          final read = parseFreeTextFigureEntry(line, dialect: dialect);
          final reason = '${dialect.name}: $line';
          expect(read, hasLength(1), reason: reason);
          expect(read.single.move, move, reason: reason);
          expect(read.single.params['who'], token, reason: reason);
        }
      }
    }
  });

  test("The Caller's Box's M3/W3/M4/W4 are the third and fourth couples'", () {
    // Maintainer decision: read as M1/W1/M2/W2 are, by couple number.
    for (final (code, token) in [
      ('M3', 'threesRole1'),
      ('W3', 'threesRole2'),
      ('M4', 'foursRole1'),
      ('W4', 'foursRole2'),
    ]) {
      final f = parseFigureLine(
        '$code figure eight up',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f?.move, 'figure_8', reason: code);
      expect(f?.params['who'], token, reason: code);
    }
  });

  test('re-checking an import kept as text reads an M3 line', () {
    // The changelog's promise: an earlier import's custom text upgrades.
    final result = reparseImportGapFigures([
      customFigure('W4 figure eight up', origin: CustomOrigin.importGap),
    ]);
    expect(result.upgradedCount, 1);
    expect(result.figures.single.move, 'figure_8');
    expect(result.figures.single.params['who'], 'foursRole2');
  });

  test('they display as the third and fourth couple', () {
    final larks = Dialect.presets.singleWhere((d) => d.name == 'Larks/Robins');
    expect(
      renderer.renderSummary(
        testFigure(
          move: 'gate',
          params: {'who': 'foursRole1', 'whom': 'threesRole2'},
        ),
        larks,
      ),
      'fourth lark gate third robin',
    );
  });
}
