import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('RoleTerm pluralization', () {
    test('default +s', () {
      expect(const RoleTerm('Lark').plural, 'Larks');
    });
    test('y -> ies', () {
      expect(const RoleTerm('Lady').plural, 'Ladies');
    });
    test('explicit plural wins', () {
      expect(
        const RoleTerm('Gentlespoon', plural: 'Gentlespoons').plural,
        'Gentlespoons',
      );
    });
  });

  group('shipped presets', () {
    test('larksRobins maps the two roles', () {
      expect(Dialect.larksRobins.roles['role1']!.singular, 'Lark');
      expect(Dialect.larksRobins.roles['role2']!.plural, 'Robins');
    });

    test('canonical has no role mappings', () {
      expect(Dialect.canonical.roles, isEmpty);
    });

    test('only role-neutral presets are shipped (no gendered presets)', () {
      final names = Dialect.presets.map((d) => d.name).toSet();
      expect(names, isNot(contains('Gents/Ladies')));
      expect(names, isNot(contains('Ladles/Gentlespoons')));
      expect(names, isNot(contains('Men/Women')));
      expect(names, isNot(contains('Larks/Ravens')));
    });

    test('discouraged terms are lowercased', () {
      expect(Dialect.larksRobins.discouragedTerms, contains('gypsy'));
      expect(
        Dialect.larksRobins.discouragedTerms,
        everyElement(predicate<String>((t) => t == t.toLowerCase())),
      );
    });
  });

  group('validate', () {
    test('a clean dialect has no issues', () {
      expect(Dialect.larksRobins.validate(), isEmpty);
    });

    test('two roles mapping to the same word collide', () {
      final d = Dialect(
        name: 'bad',
        roles: const {'role1': RoleTerm('Dancer'), 'role2': RoleTerm('Dancer')},
      );
      final issues = d.validate();
      expect(issues.single.code, 'dialect_collision');
    });

    test('an empty substitution is rejected', () {
      final d = Dialect(name: 'bad', roles: const {'role1': RoleTerm('')});
      expect(d.validate().single.code, 'empty_substitution');
    });

    test('%S is ignored when checking move-substitution collisions', () {
      final d = Dialect(
        name: 'ok',
        moves: const {
          'shoulder_round': '%S shoulder round',
          'do_si_do': 'dosido',
        },
      );
      expect(d.validate(), isEmpty);
    });
  });

  group('presets list', () {
    test('contains exactly 3 entries', () {
      expect(Dialect.presets.length, 3);
    });

    test('first entry is canonical', () {
      expect(Dialect.presets.first, same(Dialect.canonical));
    });

    test('contains canonical, larksRobins, leadsFollows', () {
      final names = Dialect.presets.map((d) => d.name).toSet();
      expect(
        names,
        containsAll(['Canonical', 'Larks/Robins', 'Leads/Follows']),
      );
    });

    test('every preset validates cleanly', () {
      for (final preset in Dialect.presets) {
        expect(preset.validate(), isEmpty, reason: preset.name);
      }
    });

    test('forName returns the matching preset', () {
      for (final preset in Dialect.presets) {
        expect(Dialect.forName(preset.name), same(preset));
      }
    });

    test('forName returns null for an unknown name', () {
      expect(Dialect.forName('NotADialect'), isNull);
    });
  });

  group('resolveByName', () {
    final custom = Dialect(
      name: 'My Dialect',
      roles: const {'role1': RoleTerm('Jet'), 'role2': RoleTerm('Ruby')},
    );

    test('finds a custom dialect from the candidates', () {
      expect(
        Dialect.resolveByName('My Dialect', candidates: [custom]),
        same(custom),
      );
    });

    test('falls back to a shipped preset when no candidate matches', () {
      expect(
        Dialect.resolveByName('Larks/Robins', candidates: [custom]),
        same(Dialect.larksRobins),
      );
    });

    test('a custom dialect wins over a preset of the same name', () {
      final shadow = Dialect(
        name: 'Larks/Robins',
        roles: const {'role1': RoleTerm('Blue'), 'role2': RoleTerm('Green')},
      );
      expect(
        Dialect.resolveByName('Larks/Robins', candidates: [shadow]),
        same(shadow),
      );
    });

    test('returns null for a null or unknown name', () {
      expect(Dialect.resolveByName(null, candidates: [custom]), isNull);
      expect(Dialect.resolveByName('Nope', candidates: [custom]), isNull);
    });
  });

  group('JSON round-trip', () {
    test('RoleTerm writes resolved plural and round-trips', () {
      const term = RoleTerm('Lady');
      expect(term.toJson(), {'singular': 'Lady', 'plural': 'Ladies'});
      expect(RoleTerm.fromJson(term.toJson()), term);
    });

    test('RoleTerm.fromJson tolerates malformed data', () {
      expect(RoleTerm.fromJson({'singular': 123}), isNull);
      expect(RoleTerm.fromJson({'singular': ''}), isNull);
      expect(RoleTerm.fromJson({}), isNull);
      expect(
        RoleTerm.fromJson({'singular': 'Lark', 'plural': 42}),
        const RoleTerm('Lark'),
      );
    });

    test('Dialect.fromJson tolerates malformed data', () {
      final d = Dialect.fromJson({
        'name': 99,
        'roles': {
          'role1': {'singular': 'Lark', 'plural': 'Larks'},
          'role2': {'singular': 42},
          'bad': 'not-a-map',
        },
        'moves': {'swing': 'swing', 'bad': 7},
        'dancers': {'neighbors': 'others', 'bad': 7},
        'discouragedTerms': ['gypsy', 8],
      });
      expect(d.name, Dialect.customName);
      expect(d.roles.keys, ['role1']);
      expect(d.moves, {'swing': 'swing'});
      expect(d.dancers, {'neighbors': 'others'});
      expect(d.discouragedTerms, ['gypsy']);
    });

    test('a custom dialect round-trips through toJson/fromJson', () {
      final custom = Dialect(
        name: 'Custom',
        roles: const {'role1': RoleTerm('Gent'), 'role2': RoleTerm('Lady')},
        moves: const {'shoulder_round': '%S shoulder round'},
        discouragedTerms: const ['gypsy', 'gents'],
      );
      expect(Dialect.fromJson(custom.toJson()), custom);
    });

    test('every shipped preset round-trips', () {
      for (final preset in Dialect.presets) {
        expect(Dialect.fromJson(preset.toJson()), preset, reason: preset.name);
      }
    });

    test('fromJson tolerates missing sections', () {
      final d = Dialect.fromJson(const {'name': 'Sparse'});
      expect(d.name, 'Sparse');
      expect(d.roles, isEmpty);
      expect(d.moves, isEmpty);
      expect(d.dancers, isEmpty);
      expect(d.discouragedTerms, isEmpty);
    });

    test('fromJson defaults a missing name to Custom', () {
      expect(Dialect.fromJson(const {}).name, Dialect.customName);
    });
  });

  group('value equality', () {
    test('equal dialects compare equal', () {
      expect(
        Dialect(name: 'x', roles: const {'role1': RoleTerm('A')}),
        Dialect(name: 'x', roles: const {'role1': RoleTerm('A')}),
      );
    });
    test('differing roles compare unequal', () {
      expect(
        Dialect(name: 'x', roles: const {'role1': RoleTerm('A')}),
        isNot(Dialect(name: 'x', roles: const {'role1': RoleTerm('B')})),
      );
    });
    test('differing dancers compare unequal', () {
      expect(
        Dialect(name: 'x', dancers: const {'neighbors': 'partners'}),
        isNot(Dialect(name: 'x', dancers: const {'neighbors': 'others'})),
      );
    });
    test('equal dancers compare equal (and hash equally)', () {
      final a = Dialect(name: 'x', dancers: const {'neighbors': 'the others'});
      final b = Dialect(name: 'x', dancers: const {'neighbors': 'the others'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('dancer substitutions', () {
    test(
      'presets ship an empty dancers map (no gendered/positional presets)',
      () {
        for (final preset in Dialect.presets) {
          expect(preset.dancers, isEmpty, reason: preset.name);
        }
      },
    );

    test('dancers default to empty and are unmodifiable', () {
      final d = Dialect(name: 'x');
      expect(d.dancers, isEmpty);
      expect(() => d.dancers['neighbors'] = 'x', throwsUnsupportedError);
    });

    test('copyWith replaces dancers', () {
      final base = Dialect(name: 'x', dancers: const {'neighbors': 'others'});
      final updated = base.copyWith(dancers: const {'ones': 'actives'});
      expect(updated.dancers, {'ones': 'actives'});
      expect(base.dancers, {'neighbors': 'others'});
    });

    test('dancers round-trip through toJson/fromJson', () {
      final custom = Dialect(
        name: 'Custom',
        dancers: const {
          'neighbors': 'the others',
          'nextNeighbors': 'the next couple',
        },
      );
      expect(custom.toJson()['dancers'], {
        'neighbors': 'the others',
        'nextNeighbors': 'the next couple',
      });
      expect(Dialect.fromJson(custom.toJson()), custom);
    });

    test('fromJson keeps only String dancer values', () {
      final d = Dialect.fromJson({
        'name': 'x',
        'dancers': {'neighbors': 'others', 'bad': 7, 'alsoBad': null},
      });
      expect(d.dancers, {'neighbors': 'others'});
    });

    test('fromJson tolerates a non-map dancers section', () {
      final d = Dialect.fromJson({'name': 'x', 'dancers': 'nope'});
      expect(d.dancers, isEmpty);
    });

    test('validate rejects an empty dancer substitution', () {
      final d = Dialect(name: 'bad', dancers: const {'neighbors': '  '});
      expect(d.validate().single.code, 'empty_substitution');
    });

    test('validate rejects two dancer tokens mapping to the same word', () {
      final d = Dialect(
        name: 'bad',
        dancers: const {'neighbors': 'others', 'shadows': 'others'},
      );
      expect(d.validate().single.code, 'dialect_collision');
    });

    test('validate flags collisions across moves and dancers', () {
      final d = Dialect(
        name: 'bad',
        moves: const {'swing': 'twirl'},
        dancers: const {'neighbors': 'twirl'},
      );
      expect(d.validate().single.code, 'dialect_collision');
    });

    test('a clean dancers map validates', () {
      final d = Dialect(
        name: 'ok',
        dancers: const {'neighbors': 'the others', 'ones': 'the actives'},
      );
      expect(d.validate(), isEmpty);
    });
  });
}
