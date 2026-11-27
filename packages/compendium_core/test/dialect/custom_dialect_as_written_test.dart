import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// A caller's own dialect is kept as they wrote it, gendered role words
/// included: the maintainer's ruling of 2026-11-27, "don't overwrite a user's
/// dialect" (ADR-006 §9.1, point 7). The app's own presets stay gender-free.
void main() {
  /// A caller's dialect written with gendered words.
  Dialect gendered() => Dialect(
    name: 'Gents & Ladies',
    roles: const {
      'role1': RoleTerm('Gent', plural: 'Gents'),
      'role2': RoleTerm('Lady', plural: 'Ladies'),
    },
    moves: const {'chain': 'ladies chain', 'do_si_do': 'dosido'},
    dancers: const {'onesRole1': 'first man', 'twosRole2': 'second woman'},
    moveWordings: const {'swing': '{who} swing the lady'},
    moveWordingBranches: const {
      'promenade': {'ordinary': '{who} {move} with the gents'},
    },
  );

  /// What [gendered] is stored as, at the current schema version, so a read
  /// that keeps everything writes it back unchanged.
  Map<String, Object?> storedGendered() => gendered().toJson();

  group('Dialect.fromJson keeps a gendered custom dialect as written', () {
    test('role terms, substitutions, wordings and name', () {
      final d = Dialect.fromJson(storedGendered());
      expect(d.name, 'Gents & Ladies');
      expect(d.roles, const {
        'role1': RoleTerm('Gent', plural: 'Gents'),
        'role2': RoleTerm('Lady', plural: 'Ladies'),
      });
      expect(d.moves, {'chain': 'ladies chain', 'do_si_do': 'dosido'});
      expect(d.dancers, {
        'onesRole1': 'first man',
        'twosRole2': 'second woman',
      });
      expect(d.moveWordings, {'swing': '{who} swing the lady'});
      expect(d.moveWordingBranches, {
        'promenade': {'ordinary': '{who} {move} with the gents'},
      });
    });

    test('and writes it back unchanged', () {
      final stored = storedGendered();
      expect(Dialect.fromJson(stored).toJson(), stored);
    });
  });

  test('Dialect.validate does not refuse a gendered word the caller typed', () {
    expect(gendered().validate(), isEmpty);
  });

  group('the shipped presets stay gender-free', () {
    // Every gendered role word the discouraged-term table reads as a role,
    // plus "gentleman", "gentlemen", "man" and "woman".
    const genderedWords = {
      'gent',
      'gents',
      'gentleman',
      'gentlemen',
      'man',
      'men',
      'lady',
      'ladies',
      'woman',
      'women',
    };
    final nonWord = RegExp(r'[^\p{L}\p{M}]+', unicode: true);
    Set<String> genderedWordsIn(Dialect d) => {
      for (final text in [
        d.name,
        for (final term in d.roles.values) ...[term.singular, term.plural],
        ...d.moves.values,
        ...d.dancers.values,
        ...d.moveWordings.values,
        for (final branches in d.moveWordingBranches.values) ...branches.values,
      ])
        for (final word in text.toLowerCase().split(nonWord))
          if (genderedWords.contains(word)) word,
    };

    test('the check finds a gendered word (positive control)', () {
      expect(genderedWordsIn(gendered()), {
        'gents',
        'ladies',
        'gent',
        'lady',
        'man',
        'woman',
      });
    });

    test('no preset holds one', () {
      for (final preset in Dialect.presets) {
        expect(genderedWordsIn(preset), isEmpty, reason: preset.name);
      }
    });
  });
}
