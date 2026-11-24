import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// Taxonomy v40 merged pass by into pass through (`passType`, with `pass_by`
/// an alias that means `who: neighbors`, `where: unspecified` by an omitted
/// param), gave a pass through a `who`, and let a bare "form long wave" state
/// `who: unspecified`. How this compiler reads each.

Operation? _figure(String move, Map<String, Object?> params) => parseDance({
  'title': 'v40 probe',
  'formation': {'shape': 'dupleImproper'},
  'progression': 'single',
  'figures': [
    {'move': move, 'params': params},
  ],
}).valueOrNull?.figures.single.operation;

DanceParseError _error(String move, Map<String, Object?> params) =>
    (parseDance({
              'title': 'v40 probe',
              'formation': {'shape': 'dupleImproper'},
              'progression': 'single',
              'figures': [
                {'move': move, 'params': params},
              ],
            })
            as Err<Dance, DanceParseError>)
        .error;

void main() {
  group('pass by, now an alias of pass through', () {
    test('a bare pass by is still the neighbours swapping', () {
      expect(_figure('pass_by', const {}), const PassBy());
    });

    test('a pass through stating passType by is a pass by', () {
      expect(
        _figure('pass_through', const {'passType': 'by', 'who': 'partners'}),
        const PassBy(who: WhoSet.partners),
      );
    });

    test('a pass by stating a direction is deferred, not ignored', () {
      final error = _error('pass_by', const {'where': 'across'});
      expect(error.deferred, isTrue);
      expect(error.path, endsWith('.where'));
    });
  });

  group('who passes through', () {
    test('a pairing is kept as a description and danced as before', () {
      expect(
        _figure('pass_through', const {'who': 'neighbors'}),
        const PassThrough(who: WhoSet.neighbors),
      );
      // Not checked against the pairs and not reached for: the pass trades
      // every pair facing along, as a pass through always did.
      final set = startingFormation(FormationType.dupleImproper, handsFour: 2);
      const named = PassThrough(who: WhoSet.nextNeighbors);
      expect(named.dancerSets.whereType<WhoSet>(), isEmpty);
      expect(
        (named.apply(set) as Ok<Formation, OpError>).value,
        (const PassThrough().apply(set) as Ok<Formation, OpError>).value,
      );
    });

    for (final role in ['role1s', 'role2s', 'ones', 'twos']) {
      test('$role passing on their own is deferred', () {
        final error = _error('pass_through', {'who': role});
        expect(error.deferred, isTrue);
        expect(error.path, endsWith('.who'));
      });
    }
  });

  test('a bare "form long wave" reads as role1s facing in, as before', () {
    expect(
      _figure('form_long_waves', const {'who': 'unspecified'}),
      _figure('form_long_waves', const {}),
    );
  });
}
