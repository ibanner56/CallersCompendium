import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final larks = Dialect.larksRobins;
  // Gendered dialects are no longer shipped presets; canonicalization must
  // still handle a user's custom gendered role terms, so build them inline.
  final gents = Dialect(
    name: 'Gents/Ladies',
    roles: const {'role1': RoleTerm('Gent'), 'role2': RoleTerm('Lady')},
    discouragedTerms: Dialect.defaultDiscouragedTerms,
  );
  final ladles = Dialect(
    name: 'Ladles/Gentlespoons',
    roles: const {'role1': RoleTerm('Gentlespoon'), 'role2': RoleTerm('Ladle')},
    discouragedTerms: Dialect.defaultDiscouragedTerms,
  );
  final renderer = FigureRenderer(contraTaxonomy);

  group('canonicalize maps dialect terms back to role tokens', () {
    test('active dialect role terms', () {
      expect(canonicalizeText('the Larks lead', larks), 'the role1s lead');
      expect(canonicalizeText('a Robin swings', larks), 'a role2 swings');
    });

    test('legacy synonyms resolve regardless of active dialect', () {
      expect(canonicalizeText('gentlespoons cross', larks), 'role1s cross');
      expect(
        canonicalizeText('ladles chain', Dialect.canonical),
        'role2s chain',
      );
    });

    test('is case-insensitive on input but emits canonical tokens', () {
      expect(canonicalizeText('LARKS and robins', larks), 'role1s and role2s');
    });

    test('leaves unknown prose untouched (conservative)', () {
      expect(
        canonicalizeText('swing your neighbor', larks),
        'swing your neighbor',
      );
    });

    test('respects word boundaries', () {
      expect(canonicalizeText('Larkspur blooms', larks), 'Larkspur blooms');
    });
  });

  group('discouraged terms are flagged', () {
    test('reported as spans (from the original input)', () {
      final result = canonicalize('those gents over there', larks);
      // "gents" is a legacy synonym, so it is also canonicalized to role1s...
      expect(result.text, 'those role1s over there');
      // ...and independently flagged as discouraged for the lingo line.
      expect(result.discouraged.map((d) => d.text), contains('gents'));
    });

    test('a purely discouraged term is flagged but left as typed', () {
      // "men" is discouraged but not a role synonym → not rewritten.
      final result = canonicalize('the men bow', larks);
      expect(result.text, 'the men bow');
      expect(result.discouraged.map((d) => d.text), contains('men'));
    });
  });

  group('round-trip property: canonicalize(render(token)) == token', () {
    final dialects = {
      'larksRobins': larks,
      'gentsLadies': gents,
      'leadsFollows': Dialect.leadsFollows,
      'ladlesGentlespoons': ladles,
    };

    for (final entry in dialects.entries) {
      for (final token in ['role1', 'role2', 'role1s', 'role2s']) {
        test('${entry.key} / $token', () {
          final display = renderer.renderFreeText(token, entry.value);
          expect(canonicalizeText(display, entry.value), token);
        });
      }
    }
  });

  group('roleSpans', () {
    test('finds legacy role synonyms in original text', () {
      final spans = roleSpans('the larks lead off', Dialect.canonical);
      expect(spans, hasLength(1));
      expect(spans.first.text.toLowerCase(), 'larks');
      expect(spans.first.start, 4);
    });

    test('finds dialect role terms when dialect provided', () {
      final spans = roleSpans('Gents cross', gents);
      expect(spans, hasLength(1));
      expect(spans.first.text, 'Gents');
      expect(spans.first.start, 0);
    });

    test('finds canonical role tokens typed directly', () {
      final spans = roleSpans('role1 and role2s', Dialect.canonical);
      expect(spans.map((s) => s.text), containsAll(['role1', 'role2s']));
    });

    test('returns empty for text with no role terms', () {
      final spans = roleSpans('swing your neighbor', Dialect.canonical);
      expect(spans, isEmpty);
    });

    test('returns empty for empty string', () {
      expect(roleSpans('', Dialect.canonical), isEmpty);
    });

    test('offsets are correct in mid-string match', () {
      // "hello larks world" — larks starts at offset 6.
      final spans = roleSpans('hello larks world', Dialect.canonical);
      final larkSpan = spans.firstWhere((s) => s.text.toLowerCase() == 'larks');
      expect(larkSpan.start, 6);
    });

    test('is case-insensitive', () {
      final spans = roleSpans('the LARKS lead', Dialect.canonical);
      expect(spans, isNotEmpty);
      expect(spans.first.text, 'LARKS');
    });

    test('respects word boundaries (no false positives in substrings)', () {
      final spans = roleSpans('Larkspur field', Dialect.canonical);
      expect(spans.where((s) => s.text.toLowerCase() == 'larks'), isEmpty);
    });
  });

  group('moveKeywordSpans', () {
    test('finds a single-word move name (swing)', () {
      final spans = moveKeywordSpans('neighbors swing', contraTaxonomy);
      expect(spans, hasLength(1));
      expect(spans.first.text.toLowerCase(), 'swing');
      expect(spans.first.start, 10);
    });

    test('finds a single-word move name at the start of the string', () {
      final spans = moveKeywordSpans('swing your partner', contraTaxonomy);
      expect(spans, hasLength(1));
      expect(spans.first.text.toLowerCase(), 'swing');
      expect(spans.first.start, 0);
    });

    test('finds a multi-word display name (do si do) as a phrase', () {
      final spans = moveKeywordSpans('neighbors do si do', contraTaxonomy);
      final doSiDo = spans.firstWhere(
        (s) => s.text.toLowerCase() == 'do si do',
        orElse: () => (text: '', start: -1),
      );
      expect(doSiDo.text.toLowerCase(), 'do si do');
      expect(doSiDo.start, 10);
    });

    test('finds a multi-word display name (right left through)', () {
      final spans = moveKeywordSpans(
        'right left through across',
        contraTaxonomy,
      );
      final rlt = spans.firstWhere(
        (s) => s.text.toLowerCase() == 'right left through',
        orElse: () => (text: '', start: -1),
      );
      expect(rlt.text.toLowerCase(), 'right left through');
      expect(rlt.start, 0);
    });

    test('finds a legacy search keyword (gypsy → shoulder_round)', () {
      final spans = moveKeywordSpans('gypsy one and a half', contraTaxonomy);
      final gypsy = spans.firstWhere(
        (s) => s.text.toLowerCase() == 'gypsy',
        orElse: () => (text: '', start: -1),
      );
      expect(gypsy.text.toLowerCase(), 'gypsy');
      expect(gypsy.start, 0);
    });

    test('is case-insensitive', () {
      final spans = moveKeywordSpans('SWING your partner', contraTaxonomy);
      expect(spans, isNotEmpty);
      expect(spans.first.text, 'SWING');
    });

    test('is case-insensitive for a multi-word phrase', () {
      final spans = moveKeywordSpans('Do Si Do', contraTaxonomy);
      final doSiDo = spans.firstWhere(
        (s) => s.text.toLowerCase() == 'do si do',
        orElse: () => (text: '', start: -1),
      );
      expect(doSiDo.text, 'Do Si Do');
    });

    test('respects word boundaries — no false positive in "swinging"', () {
      // "swinging" shares the prefix "swing" but is not a word-boundary match.
      final spans = moveKeywordSpans(
        'they were swinging around',
        contraTaxonomy,
      );
      expect(spans.where((s) => s.text.toLowerCase() == 'swing'), isEmpty);
    });

    test('respects word boundaries — no false positive in "petronellas"', () {
      // "petronellas" is not in the taxonomy (only "petronella").
      final spans = moveKeywordSpans('two petronellas', contraTaxonomy);
      expect(spans.where((s) => s.text.toLowerCase() == 'petronella'), isEmpty);
    });

    test('finds alias display name (see saw)', () {
      final spans = moveKeywordSpans('see saw instead', contraTaxonomy);
      final seeSaw = spans.firstWhere(
        (s) => s.text.toLowerCase() == 'see saw',
        orElse: () => (text: '', start: -1),
      );
      expect(seeSaw.text.toLowerCase(), 'see saw');
    });

    test('returns empty for text with no known moves', () {
      final spans = moveKeywordSpans('hello world', contraTaxonomy);
      expect(spans, isEmpty);
    });

    test('returns empty for empty string', () {
      expect(moveKeywordSpans('', contraTaxonomy), isEmpty);
    });

    test('does not match the custom move displayName ("custom")', () {
      final spans = moveKeywordSpans('my custom step', contraTaxonomy);
      expect(spans.where((s) => s.text.toLowerCase() == 'custom'), isEmpty);
    });

    test('finds petronella with correct offset in mid-string', () {
      final spans = moveKeywordSpans('do a petronella here', contraTaxonomy);
      final pet = spans.firstWhere(
        (s) => s.text.toLowerCase() == 'petronella',
        orElse: () => (text: '', start: -1),
      );
      expect(pet.start, 5);
    });

    test('finds multiple moves in one string', () {
      final spans = moveKeywordSpans('swing then petronella', contraTaxonomy);
      final texts = spans.map((s) => s.text.toLowerCase()).toList();
      expect(texts, containsAll(['swing', 'petronella']));
    });
  });
}
