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

  group('JSON round-trip', () {
    test('RoleTerm writes resolved plural and round-trips', () {
      const term = RoleTerm('Lady');
      expect(term.toJson(), {'singular': 'Lady', 'plural': 'Ladies'});
      expect(RoleTerm.fromJson(term.toJson()), term);
    });

    test('a custom dialect round-trips through toJson/fromJson', () {
      final custom = Dialect(
        name: 'Custom',
        roles: const {
          'role1': RoleTerm('Gent'),
          'role2': RoleTerm('Lady'),
        },
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
  });
}
