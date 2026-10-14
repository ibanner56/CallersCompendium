import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('figureGlossaryEntries', () {
    final entries = figureGlossaryEntries(contraTaxonomy);

    test('lists every move and alias except the free-text custom move', () {
      expect(entries.map((e) => e.id), [
        for (final id in contraTaxonomy.moves.keys)
          if (id != customMoveId) id,
        ...contraTaxonomy.aliases.keys,
      ]);
    });

    test('an alias resolves to its target and omits the params it pins', () {
      final seeSaw = entries.singleWhere((e) => e.id == 'see_saw');
      final alias = contraTaxonomy.aliases['see_saw']!;
      expect(seeSaw.isAlias, isTrue);
      expect(seeSaw.targetMoveId, alias.targetMove);
      expect(alias.pinnedParams.keys, isNotEmpty);
      for (final pinned in alias.pinnedParams.keys) {
        expect(seeSaw.params, isNot(contains(pinned)));
      }
      expect(seeSaw.params, [
        for (final k in contraTaxonomy.moves[alias.targetMove]!.params.keys)
          if (!alias.pinnedParams.containsKey(k)) k,
      ]);
    });

    test('a move is its own target and keeps all its params', () {
      final swing = entries.singleWhere((e) => e.id == 'swing');
      expect(swing.isAlias, isFalse);
      expect(swing.params, contraTaxonomy.moves['swing']!.params.keys);
    });

    test('attaches a definition by id, and none when there is none', () {
      const def = FigureDefinition(definition: 'd', description: 'x');
      final withDef = figureGlossaryEntries(
        contraTaxonomy,
        definitions: const {'swing': def},
      );
      expect(withDef.singleWhere((e) => e.id == 'swing').definition, def);
      expect(withDef.singleWhere((e) => e.id == 'chain').definition, isNull);
    });
  });

  group('contraFigureDefinitions', () {
    final ids = {...contraTaxonomy.moves.keys, ...contraTaxonomy.aliases.keys}
      ..remove(customMoveId);

    test('defines only figures the glossary lists', () {
      for (final id in contraFigureDefinitions.keys) {
        expect(ids, contains(id), reason: '"$id" is not a glossary figure');
      }
    });

    // Shipped text is rendered through the user's dialect, so it must carry
    // the canonical role tokens rather than any dialect's role words, and
    // must not use a term the app flags as discouraged.
    test('uses role tokens, never role words or discouraged terms', () {
      for (final MapEntry(key: id, value: def)
          in contraFigureDefinitions.entries) {
        for (final text in [def.definition, def.description]) {
          expect(text.trim(), isNotEmpty, reason: '"$id" has empty text');
          expect(
            offendingWords(text),
            isEmpty,
            reason: '"$id": write role tokens (role1, role2s…) instead',
          );
        }
      }
    });
  });

  // The checker the test above runs over the shipped map, exercised on fixed
  // text so it can be seen to fail before any definition ships.
  group('offendingWords', () {
    test('flags role words, discouraged terms and their possessives', () {
      expect(offendingWords('Larks turn robins.'), ['larks', 'robins']);
      expect(offendingWords('The gent swings the lady.'), ['gent', 'lady']);
      expect(
        offendingWords("The robin's right hand goes to the lark's left."),
        ['robin', 'lark'],
      );
      expect(offendingWords("The gent's partner and the ladies' line."), [
        'gent',
        'ladies',
      ]);
      expect(offendingWords('Walk around a gypsy or gyre.'), ['gypsy', 'gyre']);
    });

    test('accepts role tokens, figure names, and lead/follow as verbs', () {
      expect(offendingWords('Role2s cross; the role1s turn them in.'), isEmpty);
      expect(offendingWords("The role1's right hand."), isEmpty);
      expect(offendingWords('Ends in a mad robin.'), isEmpty);
      expect(
        offendingWords('Usually follows a balance; role1s lead role2s in.'),
        isEmpty,
      );
    });
  });
}

/// Words in [text] that are a dialect's role word or a discouraged term,
/// lowercased and stripped of a possessive ending.
///
/// "lead(s)" and "follow(s)" are left out: they are the Leads/Follows preset's
/// role words, but also everyday verbs ("a balance usually follows"), and a
/// checker that cannot tell the two apart would reject ordinary prose. Text
/// that uses them as nouns for dancers has to be caught in review.
List<String> offendingWords(String text) {
  const verbs = {'lead', 'leads', 'follow', 'follows'};
  final flagged = <String>{
    for (final d in Dialect.presets)
      for (final term in d.roles.values) ...[term.singular, term.plural],
    ...Dialect.defaultDiscouragedTerms,
  }.map((w) => w.toLowerCase()).where((w) => !verbs.contains(w)).toSet();
  // A role word inside a figure's own name ("mad robin") names the figure,
  // not a dancer. Longest names first, so a long name is removed whole.
  final figureNames = [
    for (final m in contraTaxonomy.moves.values) m.displayName.toLowerCase(),
    for (final a in contraTaxonomy.aliases.values) a.displayName.toLowerCase(),
  ]..sort((a, b) => b.length.compareTo(a.length));
  var prose = text.toLowerCase();
  for (final name in figureNames) {
    prose = prose.replaceAll(name, ' ');
  }
  return [
    for (final m in RegExp(r"[a-z][a-z'’-]*").allMatches(prose))
      if (m.group(0)!.replaceFirst(RegExp(r"['’]s?$"), '') case final word
          when flagged.contains(word))
        word,
  ];
}
