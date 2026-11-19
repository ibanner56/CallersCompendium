import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// A dialect may never show a gendered role term (ADR-006 §9.1, point 7):
/// [Dialect.validate] refuses one, and [Dialect.fromJson] drops one saved
/// before they were refused.
void main() {
  group('genderedRoleWordIn', () {
    test('finds each gendered role word as a whole word, in any case', () {
      for (final word in genderedRoleWords) {
        expect(genderedRoleWordIn(word), word, reason: word);
        expect(genderedRoleWordIn(word.toUpperCase()), word, reason: word);
        expect(genderedRoleWordIn('first $word'), word, reason: word);
      }
      expect(genderedRoleWordIn("Gent's"), 'gent');
      expect(genderedRoleWordIn('Lady-Bird'), 'lady');
      expect(genderedRoleWordIn('Gents2'), 'gents');
      expect(genderedRoleWordIn('Gents_Night'), 'gents');
    });

    test('ignores words that only contain one', () {
      for (final text in [
        'Robin',
        'Larks',
        'Mandy',
        'salmon',
        'Gentle',
        'Manny',
        'Womanly',
        'ravens',
        '',
      ]) {
        expect(genderedRoleWordIn(text), isNull, reason: text);
      }
    });
  });

  group('man and men', () {
    test('count in a role term but not in prose', () {
      expect(genderedRoleWordIn('men'), 'men');
      expect(genderedRoleWordIn('dann geht man vor', inProse: true), isNull);
      expect(genderedRoleWordIn('men zwaait', inProse: true), isNull);
      expect(genderedRoleWordIn('the ladies chain', inProse: true), 'ladies');
      expect(shownDialectName('Wie man tanzt'), 'Wie man tanzt');
    });

    test('a German wording survives a read and validates', () {
      final d = Dialect.fromJson({
        'name': 'Deutsch',
        'roles': {
          'role1': {'singular': 'Man'},
        },
        'moves': {'swing': 'man swingt'},
        'moveWordings': {'swing': '{who} tauschen, dann geht man vor'},
      });
      expect(d.roles['role1'], Dialect.larksRobins.roles['role1']);
      expect(d.moves['swing'], 'man swingt');
      expect(d.moveWordings['swing'], isNotNull);
      expect(
        d.validate().where((i) => i.code == 'gendered_role_term'),
        isEmpty,
      );
    });
  });

  group('shownDialectName', () {
    test('masks a gendered name and keeps any other', () {
      expect(shownDialectName('Gents & Ladies'), Dialect.customName);
      expect(shownDialectName('Gents & Ladies', replacement: 'X'), 'X');
      expect(shownDialectName('Jays & Wrens'), 'Jays & Wrens');
    });

    test('a synced dialect list is labelled without gendered names', () {
      final entries = syncCollectionEntries('custom_dialects_ecd', [
        {'name': 'Gents & Ladies'},
        {'name': 'Mine'},
      ])!;
      expect(entries.map((e) => e.label), [Dialect.customName, 'Mine']);
      expect(entries.map((e) => e.key), ['Gents & Ladies', 'Mine']);
    });
  });

  group('Dialect.validate', () {
    List<String> gendered(Dialect d) => [
      for (final issue in d.validate())
        if (issue.code == 'gendered_role_term') issue.data['source'] as String,
    ];

    test('refuses a gendered role term, singular or plural', () {
      expect(
        gendered(
          Dialect(
            name: 'X',
            roles: const {
              'role1': RoleTerm('Gent'),
              'role2': RoleTerm('Robin'),
            },
          ),
        ),
        ['role1', 'role1s'],
      );
      expect(
        gendered(
          Dialect(
            name: 'X',
            roles: const {
              'role1': RoleTerm('Lark'),
              'role2': RoleTerm('Robin', plural: 'Women'),
            },
          ),
        ),
        ['role2s'],
      );
    });

    test('refuses a gendered word in a move, dancer or wording', () {
      final d = Dialect(
        name: 'X',
        moves: const {'chain': 'ladies chain'},
        dancers: const {'onesRole1': 'first woman', 'twosRole1': 'first man'},
        moveWordings: const {'swing': '{who} swing the lady'},
        moveWordingBranches: const {
          'promenade': {'ordinary': '{who} {move} with the gents'},
        },
      );
      expect(
        gendered(d),
        unorderedEquals([
          'chain',
          'onesRole1',
          'twosRole1',
          'swing',
          'promenade.ordinary',
        ]),
      );
    });

    test('accepts the shipped presets and role-neutral words', () {
      for (final preset in Dialect.presets) {
        expect(gendered(preset), isEmpty, reason: preset.name);
      }
      expect(
        gendered(
          Dialect(
            name: 'X',
            roles: const {'role1': RoleTerm('Jay'), 'role2': RoleTerm('Wren')},
            dancers: const {'neighbors': 'the others'},
          ),
        ),
        isEmpty,
      );
    });
  });

  group('Dialect.fromJson', () {
    test('shows the default term for a gendered role term saved earlier', () {
      final d = Dialect.fromJson({
        'v': 2,
        'name': 'Old',
        'roles': {
          'role1': {'singular': 'Gent', 'plural': 'Gents'},
          'role2': {'singular': 'Robin', 'plural': 'Women'},
        },
      });
      expect(d.roles, Dialect.larksRobins.roles);
      expect(d.validate(), isEmpty);
    });

    test('keeps a role-neutral role term as saved', () {
      final d = Dialect.fromJson({
        'v': 2,
        'name': 'Birds',
        'roles': {
          'role1': {'singular': 'Jay', 'plural': 'Jays'},
          'role2': {'singular': 'Lady', 'plural': 'Ladies'},
        },
      });
      expect(d.roles['role1'], const RoleTerm('Jay'));
      expect(d.roles['role2'], Dialect.larksRobins.roles['role2']);
    });

    test('drops a move, dancer or wording that holds one', () {
      final d = Dialect.fromJson({
        'v': 2,
        'name': 'Old',
        'moves': {'chain': 'ladies chain', 'do_si_do': 'dosido'},
        'dancers': {
          'onesRole1': 'first woman',
          'twosRole1': 'the men',
          'neighbors': 'the others',
        },
        'moveWordings': {
          'swing': '{who} swing the lady',
          'allemande': '{who} allemande',
        },
        'moveWordingBranches': {
          'promenade': {
            'ordinary': '{who} {move} with the gents',
            'singleFile': '{prefix} {move} {direction} {destination}',
          },
        },
      });
      expect(d.moves, {'do_si_do': 'dosido'});
      expect(d.dancers, {'neighbors': 'the others'});
      expect(d.moveWordings, {'allemande': '{who} allemande'});
      expect(d.moveWordingBranches, {
        'promenade': {
          'singleFile': '{prefix} {move} {direction} {destination}',
        },
      });
      expect(d.validate(), isEmpty);
    });
  });
}
