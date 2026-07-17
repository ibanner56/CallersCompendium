import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  // A saved dialect the user is NOT actively using. Maps role2 → follow, so
  // "follows" should resolve to role2s via enrichment even when inactive.
  final leadsFollows = Dialect(
    name: 'Leads/Follows',
    roles: const {'role1': RoleTerm('lead'), 'role2': RoleTerm('follow')},
  );
  final gentsLadies = Dialect(
    name: 'Gents/Ladies',
    roles: const {'role1': RoleTerm('Gent'), 'role2': RoleTerm('Lady')},
  );
  // A dialect with a move substitution (reversible) and a templated one.
  final movesDialect = Dialect(
    name: 'Moves',
    moves: const {
      'shoulder_round': 'gypsy',
      'right_left_through': '%S right left', // templated → skipped
    },
  );

  group('SearchEnrichment.fromDialects', () {
    test('unions role display terms (singular + plural) → role tokens', () {
      final e = SearchEnrichment.fromDialects([leadsFollows]);
      expect(e.roleSynonyms['lead'], 'role1');
      expect(e.roleSynonyms['leads'], 'role1s');
      expect(e.roleSynonyms['follow'], 'role2');
      expect(e.roleSynonyms['follows'], 'role2s');
    });

    test('unions move substitutions and skips templated (%S) ones', () {
      final e = SearchEnrichment.fromDialects([movesDialect]);
      expect(e.moveSynonyms['gypsy'], 'shoulder_round');
      expect(e.moveSynonyms.containsKey('%s right left'), isFalse);
      expect(e.moveSynonyms.length, 1);
    });

    test('keeps a display term shared by two dialects with the SAME token', () {
      final other = Dialect(
        name: 'Also follows',
        roles: const {'role2': RoleTerm('follow')},
      );
      final e = SearchEnrichment.fromDialects([leadsFollows, other]);
      expect(e.roleSynonyms['follow'], 'role2');
    });

    test('drops a display term two dialects map to DIFFERENT tokens', () {
      final a = Dialect(
        name: 'A',
        roles: const {'role1': RoleTerm('star', plural: 'stars')},
      );
      final b = Dialect(
        name: 'B',
        roles: const {'role2': RoleTerm('star', plural: 'stars')},
      );
      final e = SearchEnrichment.fromDialects([a, b]);
      expect(e.roleSynonyms.containsKey('star'), isFalse);
      expect(e.roleSynonyms.containsKey('stars'), isFalse);
    });

    test('drops a display term identical to a canonical role token', () {
      final weird = Dialect(
        name: 'Weird',
        roles: const {'role1': RoleTerm('role2', plural: 'role2s')},
      );
      final e = SearchEnrichment.fromDialects([weird]);
      expect(e.roleSynonyms.containsKey('role2'), isFalse);
      expect(e.roleSynonyms.containsKey('role2s'), isFalse);
    });

    test('empty input yields an empty enrichment', () {
      expect(SearchEnrichment.fromDialects(const []).isEmpty, isTrue);
    });
  });

  group('canonicalize with extraRoleSynonyms (search enrichment)', () {
    test('resolves a term from a NON-active saved dialect', () {
      final e = SearchEnrichment.fromDialects([leadsFollows]);
      // Active dialect is larksRobins; "follows" is not one of its terms nor a
      // legacy synonym — it only resolves via the union enrichment.
      expect(
        canonicalizeText(
          'follows chain',
          Dialect.larksRobins,
          extraRoleSynonyms: e.roleSynonyms,
        ),
        'role2s chain',
      );
    });

    test('legacy synonyms win over the enrichment on overlap', () {
      // Enrichment tries to map "men" → role2s (wrong); legacy men → role1s.
      final e = SearchEnrichment(roleSynonyms: const {'men': 'role2s'});
      expect(
        canonicalizeText(
          'men',
          Dialect.canonical,
          extraRoleSynonyms: e.roleSynonyms,
        ),
        'role1s',
      );
    });

    test('active dialect wins over the enrichment on overlap', () {
      // Active larksRobins maps role1 → lark; an enrichment claiming lark →
      // role2 must not override the active dialect.
      final e = SearchEnrichment(roleSynonyms: const {'lark': 'role2'});
      expect(
        canonicalizeText(
          'lark',
          Dialect.larksRobins,
          extraRoleSynonyms: e.roleSynonyms,
        ),
        'role1',
      );
    });

    test('empty enrichment leaves output identical to the no-arg call', () {
      const text = 'the Larks lead a robin swing men women follows';
      for (final d in [Dialect.canonical, Dialect.larksRobins, gentsLadies]) {
        expect(
          canonicalizeText(text, d, extraRoleSynonyms: const {}),
          canonicalizeText(text, d),
        );
      }
    });
  });

  group('FilterCompiler with SearchEnrichment', () {
    test('FullText resolves a role term from a non-active dialect', () {
      final e = SearchEnrichment.fromDialects([leadsFollows]);
      final c = FilterCompiler(
        Dialect.larksRobins,
        e,
      ).compile(const FullTextFilter('follows'));
      expect(c.binds.single, '"role2s"');
    });

    test('figure move name resolves via enriched move synonyms', () {
      final e = SearchEnrichment.fromDialects([movesDialect]);
      final c = FilterCompiler(
        Dialect.canonical,
        e,
      ).compile(FigureFilter.leaf('gypsy'));
      expect(c.binds.first, 'shoulder_round');
    });

    test('active dialect move substitution wins over the enrichment', () {
      final e = SearchEnrichment(moveSynonyms: const {'gypsy': 'swing'});
      final active = Dialect(
        name: 'Active',
        moves: const {'shoulder_round': 'gypsy'},
      );
      final c = FilterCompiler(active, e).compile(FigureFilter.leaf('gypsy'));
      expect(c.binds.first, 'shoulder_round');
    });

    test('no enrichment behaves exactly as before', () {
      final withEmpty = FilterCompiler(
        Dialect.larksRobins,
        SearchEnrichment.empty,
      ).compile(const FullTextFilter('robins allemande'));
      final without = FilterCompiler(
        Dialect.larksRobins,
      ).compile(const FullTextFilter('robins allemande'));
      expect(withEmpty.binds, without.binds);
    });
  });

  group('SearchEnrichment value equality', () {
    test('a same instance equals itself', () {
      final e = SearchEnrichment.fromDialects([leadsFollows]);
      expect(e, equals(e));
    });

    test('empty equals a freshly constructed enrichment', () {
      expect(SearchEnrichment.empty, equals(const SearchEnrichment()));
      expect(
        SearchEnrichment.empty.hashCode,
        const SearchEnrichment().hashCode,
      );
    });

    test('value-equal instances are == and share a hashCode', () {
      const a = SearchEnrichment(
        roleSynonyms: {'lead': 'role1', 'follow': 'role2'},
        moveSynonyms: {'gypsy': 'shoulder_round'},
      );
      const b = SearchEnrichment(
        roleSynonyms: {'lead': 'role1', 'follow': 'role2'},
        moveSynonyms: {'gypsy': 'shoulder_round'},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test(
      'two independently-built value-identical enrichments compare equal',
      () {
        // Mirrors the real concern: a caller building enrichment inline (no
        // cache) on each rebuild must produce an == result so widgets that
        // compare by value do not spuriously re-search.
        final a = SearchEnrichment.fromDialects([leadsFollows, movesDialect]);
        final b = SearchEnrichment.fromDialects([leadsFollows, movesDialect]);
        expect(identical(a, b), isFalse);
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      },
    );

    test('differing roleSynonyms are not equal', () {
      const a = SearchEnrichment(roleSynonyms: {'lead': 'role1'});
      const b = SearchEnrichment(roleSynonyms: {'lead': 'role2'});
      expect(a, isNot(equals(b)));
    });

    test('differing moveSynonyms are not equal', () {
      const a = SearchEnrichment(moveSynonyms: {'gypsy': 'shoulder_round'});
      const b = SearchEnrichment(moveSynonyms: {'gypsy': 'swing'});
      expect(a, isNot(equals(b)));
    });

    test('an extra map entry breaks equality', () {
      const a = SearchEnrichment(roleSynonyms: {'lead': 'role1'});
      const b = SearchEnrichment(
        roleSynonyms: {'lead': 'role1', 'follow': 'role2'},
      );
      expect(a, isNot(equals(b)));
    });
  });
}
