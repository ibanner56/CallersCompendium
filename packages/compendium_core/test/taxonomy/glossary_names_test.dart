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
