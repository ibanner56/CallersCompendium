import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// Taxonomy v40: the previous and next neighbors' role1s and role2s
/// (`prevRole1s`, `prevRole2s`, `nextRole1s`, `nextRole2s`), each placed
/// straight after its neighbors entry in the dancer-set picker.
void main() {
  const added = ['prevRole1s', 'prevRole2s', 'nextRole1s', 'nextRole2s'];
  final renderer = FigureRenderer(contraTaxonomy);

  test('each sits straight after its neighbors, in picker order', () {
    final sets = ParamVocab.pairDancerSets;
    final start = sets.indexOf('prevNeighbors');
    expect(start, isNonNegative);
    expect(sets.sublist(start, start + 7), [
      'prevNeighbors',
      'prevRole1s',
      'prevRole2s',
      'nextNeighbors',
      'nextRole1s',
      'nextRole2s',
      'thirdNeighbors',
    ]);
  });

  test('no third or fourth role set is offered yet', () {
    for (final token in ParamVocab.dancerSets) {
      expect(token, isNot(matches(RegExp('^(third|fourth)Role'))));
    }
  });

  test('they are pair sets, so any dancer param takes them', () {
    const any = ParamSpec(ParamKind.dancerSet, defaultValue: 'role1s');
    for (final token in added) {
      expect(ParamVocab.dancerSets, contains(token), reason: token);
      expect(any.validate(token), isTrue, reason: token);
      expect(
        contraTaxonomy.moves['swing']!.params['who']!.validate(token),
        isTrue,
        reason: 'swing.who $token',
      );
    }
  });

  test(
    'each reads in the dialect\'s role words, and canonical keeps the token',
    () {
      final swing = Figure(move: 'swing', params: {'who': 'nextRole1s'});
      expect(
        renderer.renderCanonical(swing),
        contains('next role1s'),
        reason: 'the stored line keeps the canonical role token',
      );
      final larks = Dialect.larksRobins;
      final expected = {
        'prevRole1s': 'prev larks',
        'prevRole2s': 'prev robins',
        'nextRole1s': 'next larks',
        'nextRole2s': 'next robins',
      };
      for (final MapEntry(key: token, value: words) in expected.entries) {
        expect(
          FigureRenderer.displayToken(token, null, larks).toLowerCase(),
          words,
          reason: token,
        );
        expect(
          renderer.dancerTerms(larks),
          contains(words),
          reason: 'calling-card terms: $token',
        );
      }
      final leads = Dialect.leadsFollows;
      expect(
        FigureRenderer.displayToken('prevRole2s', null, leads).toLowerCase(),
        'prev follows',
      );
    },
  );

  test('a plural subject reads them in the dialect\'s role words too', () {
    // `hey.pass1` and `revolving_door.who` take the plural path, where the verb
    // agrees with the group ("next robins start a hey").
    final larks = Dialect.larksRobins;
    final hey = renderer.renderSummary(
      testFigure(move: 'hey', params: {'pass1': 'nextRole2s'}),
      larks,
    );
    expect(hey, startsWith('next robins start'));
    final door = renderer.renderSummary(
      testFigure(move: 'revolving_door', params: {'who': 'prevRole1s'}),
      larks,
    );
    expect(door, contains('prev larks take'));
  });

  test('a wording condition names each by the dialect\'s role words', () {
    final vocabulary = renderer.moveWordingVocabulary(
      'swing',
      Dialect.larksRobins,
    );
    final who = vocabulary['who']!;
    expect(who.wordFor('prevRole1s'), 'prev larks');
    expect(who.wordFor('prevRole2s'), 'prev robins');
    expect(who.wordFor('nextRole1s'), 'next larks');
    expect(who.wordFor('nextRole2s'), 'next robins');
  });

  test('the display\'s own words read back to the token', () {
    for (final dialect in [Dialect.canonical, ...Dialect.presets]) {
      for (final token in added) {
        final text = renderer.renderSummary(
          testFigure(move: 'swing', params: {'who': token}),
          dialect,
        );
        final read = parseFreeTextFigureEntry(text, dialect: dialect);
        expect(read, hasLength(1), reason: '${dialect.name}: $text');
        expect(
          read.single.params['who'],
          token,
          reason: '${dialect.name}: $text',
        );
      }
    }
  });

  test('a dialect may still reword one, as it can a neighbors entry', () {
    final dialect = Dialect(
      name: 'Reworded',
      roles: Dialect.larksRobins.roles,
      dancers: const {'nextRole1s': 'the next gents'},
    );
    final spec = contraTaxonomy.moves['swing']!.params['who'];
    expect(
      FigureRenderer.displayToken('nextRole1s', spec, dialect),
      'the next gents',
    );
  });

  test('they have no pair inverse and no opposite, as v38\'s corners', () {
    for (final kind in [ParamKind.dancerSet, ParamKind.dancerPair]) {
      for (final token in added) {
        expect(ParamOpposites.of(kind, token), isNull, reason: token);
      }
    }
    for (final token in added) {
      expect(invertPairDancerSet(token), isNull, reason: token);
    }
  });
}
