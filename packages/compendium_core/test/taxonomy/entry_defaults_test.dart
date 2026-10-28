import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// `ParamSpec.entryDefault` / `Taxonomy.entryParams` (taxonomy v38): what the
/// figure editor seeds on picking a move, where it differs from what a stored
/// figure that omits the param means.
void main() {
  final tax = contraTaxonomy;

  // Every param whose entry value differs from its default, and the entry
  // value. Anything not listed here must seed exactly its default.
  const expectedEntryOverrides = <String, Map<String, Object?>>{
    'box_the_gnat': {'balance': true, 'beats': 8},
    'box_circulate': {'balance': true, 'beats': 8},
    'pass_the_ocean': {'balance': true, 'beats': 8},
    'form_long_waves': {'balance': true, 'beats': 4},
  };

  test('entry seeds the default for every param except the listed ones', () {
    for (final id in tax.moves.keys) {
      final effective = tax.effectiveParams(testFigure(move: id));
      final entry = tax.entryParams(id);
      final overrides = expectedEntryOverrides[id] ?? const {};
      expect(
        entry,
        {...effective, ...overrides},
        reason:
            '$id: entry params should be its defaults plus '
            '${overrides.isEmpty ? 'nothing' : overrides}',
      );
    }
  });

  group('a figure that omits balance is still unbalanced', () {
    for (final id in expectedEntryOverrides.keys) {
      test(id, () {
        expect(tax.effectiveParams(testFigure(move: id))['balance'], isFalse);
        expect(tax.resolve(id)!.params['balance']!.defaultValue, isFalse);
        // And an explicit stored `false` is untouched by entry defaults.
        expect(
          tax.effectiveParams(
            testFigure(move: id, params: {'balance': false}),
          )['balance'],
          isFalse,
        );
      });
    }
  });

  group('the entry state is one the editor itself would produce', () {
    for (final entry in expectedEntryOverrides.entries) {
      final id = entry.key;

      test('$id: entry values raise no validation issue', () {
        // Catches an entry `beats` that `goodBeats` would flag as atypical.
        final issues = tax.validateFigure(
          testFigure(move: id, params: tax.entryParams(id)),
        );
        expect(issues, isEmpty);
      });

      test('$id: unticking balance gives the plain default beats back', () {
        final params = tax.entryParams(id);
        final plainBeats = tax.effectiveParams(testFigure(move: id))['beats'];
        applyParamChange(
          tax,
          move: id,
          params: params,
          key: 'balance',
          value: false,
          beatsTouched: false,
          aggressiveBeats: false,
        );
        expect(params['balance'], isFalse);
        expect(params['beats'], plainBeats);
      });

      test('$id: editing another param keeps the entry beats', () {
        final params = tax.entryParams(id);
        final entryBeats = params['beats'];
        applyParamChange(
          tax,
          move: id,
          params: params,
          key: 'who',
          value: 'role1s',
          beatsTouched: false,
          aggressiveBeats: false,
        );
        expect(params['beats'], entryBeats);
      });
    }
  });

  test('an unknown move seeds only what effectiveParams gives', () {
    expect(
      tax.entryParams('not_a_move'),
      // invalid-fixture: deliberately unknown move — pins the graceful fallback
      tax.effectiveParams(Figure(move: 'not_a_move')),
    );
  });

  group('v38 stored-figure defaults', () {
    final expected = <(String, String), Object?>{
      ('roll_away', 'who'): 'role1s',
      ('orbit', 'who'): 'role1s',
      ('arch_and_dive', 'who'): 'twos',
      ('box_the_gnat', 'who'): 'neighbors',
      ('figure_8', 'where'): 'above',
    };
    expected.forEach((key, value) {
      test('${key.$1}.${key.$2} is $value', () {
        expect(tax.effectiveParams(testFigure(move: key.$1))[key.$2], value);
      });
    });
  });
}
