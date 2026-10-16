import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Name collisions for a user's own glossary entry (#709).
void main() {
  Set<GlossaryNameSource> check(
    String name, {
    Iterable<Dialect> dialects = const [],
    Iterable<String> shorthands = const [],
    Iterable<String> entries = const [],
  }) => glossaryNameCollisions(
    name,
    taxonomy: contraTaxonomy,
    dialects: dialects,
    shorthandTokens: shorthands,
    userEntryNames: entries,
  );

  test('shipped names and ids collide, case- and space-insensitively', () {
    expect(check('Pull  By'), {GlossaryNameSource.shippedFigure});
    expect(check('pull_by'), {GlossaryNameSource.shippedFigure});
    expect(check('Seesaw'), {GlossaryNameSource.shippedFigure});
    expect(check('see saw'), {GlossaryNameSource.shippedKeyword});
  });

  test('any run of Unicode whitespace is one space', () {
    expect(normalizeGlossaryName('Pull\t  By'), 'pull by');
    expect(normalizeGlossaryName('Pull\u00A0By'), 'pull by');
    expect(check('pull\nby'), {GlossaryNameSource.shippedFigure});
  });

  test('an alias id collides, as the alias name does', () {
    expect(check('see_saw'), {GlossaryNameSource.shippedFigure});
  });

  test('the placeholder custom move is not a name that is taken', () {
    expect(check('custom'), isEmpty);
  });

  test('shipped search keywords collide', () {
    expect(check('Gypsy'), {GlossaryNameSource.shippedKeyword});
  });

  test('a dialect move rename collides, its placeholder ignored', () {
    final dialect = Dialect.larksRobins.copyWith(
      name: 'mine',
      moves: {'swing': 'twirl %s'},
    );
    expect(check('Twirl', dialects: [dialect]), {
      GlossaryNameSource.dialectMove,
    });
  });

  test('a rename\'s placeholder is ignored in either case', () {
    final dialect = Dialect.larksRobins.copyWith(
      name: 'mine',
      moves: {'swing': 'twirl %S'},
    );
    expect(check('Twirl', dialects: [dialect]), {
      GlossaryNameSource.dialectMove,
    });
  });

  test(
    'a rename written in role words collides with the same words as typed',
    () {
      final dialect = Dialect.larksRobins.copyWith(
        name: 'mine',
        moves: {'chain': 'robins chain'},
      );
      expect(check('Robins chain', dialects: [dialect]), {
        GlossaryNameSource.dialectMove,
      });
    },
  );

  test('an empty entry name or an empty rename is not a taken name', () {
    final dialect = Dialect.larksRobins.copyWith(
      name: 'mine',
      moves: {'swing': '%s'},
    );
    expect(check('  ', dialects: [dialect], entries: ['', ' \t']), isEmpty);
  });

  test('a dialect\'s name for a figure of your own collides with another '
      'entry, but not with the figure it names (#1023)', () {
    final dialect = Dialect.larksRobins.copyWith(
      name: 'mine',
      moves: {userFigureKeyFor('zoom-id'): 'whizz'},
    );
    expect(check('Whizz', dialects: [dialect]), {
      GlossaryNameSource.dialectMove,
    });
    expect(
      glossaryNameCollisions(
        'whizz',
        taxonomy: contraTaxonomy,
        dialects: [dialect],
        exceptUserFigureId: 'zoom-id',
      ),
      isEmpty,
    );
  });

  test('a stored, canonical name collides with a rename or a shorthand '
      'that says it in role words', () {
    final dialect = Dialect.larksRobins.copyWith(
      name: 'mine',
      moves: {'chain': 'robins chain'},
    );
    final stored = canonicalizeGlossaryText('Robins chain', dialect);
    expect(stored, 'role2s chain');
    expect(check(stored, dialects: [dialect]), {
      GlossaryNameSource.dialectMove,
    });
    expect(
      check(
        canonicalizeGlossaryText('Larks loop', dialect),
        dialects: [dialect],
        shorthands: ['larks loop'],
      ),
      {GlossaryNameSource.shorthand},
    );
  });

  test('shorthand tokens and other entries collide', () {
    expect(check('GRL', shorthands: ['grl']), {GlossaryNameSource.shorthand});
    expect(check('Grand right and left', entries: ['grand right AND left']), {
      GlossaryNameSource.userEntry,
    });
  });

  test('a free name, or an empty one, collides with nothing', () {
    expect(check('grand right and left'), isEmpty);
    expect(check('   '), isEmpty);
  });
}
