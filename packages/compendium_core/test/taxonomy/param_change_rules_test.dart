import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Core's [applyParamChange] (#709): the rules the dance editor applies when a
/// param changes, shared with compound expansion. The editor's own widget tests
/// (`app/test/widgets/figure_list_editor_test.dart`) pin the same rules from
/// the UI side; these pin them where expansion will call them.
void main() {
  final taxonomy = contraTaxonomy;

  ({String move, Map<String, Object?> params}) change(
    String move,
    Map<String, Object?> params,
    String key,
    Object? value, {
    bool beatsTouched = false,
    bool aggressiveBeats = false,
  }) {
    final next = Map<String, Object?>.of(params);
    final resolved = applyParamChange(
      taxonomy,
      move: move,
      params: next,
      key: key,
      value: value,
      beatsTouched: beatsTouched,
      aggressiveBeats: aggressiveBeats,
    );
    return (move: resolved, params: next);
  }

  Map<String, Object?> defaults(String move) =>
      taxonomy.effectiveParams(Figure(move: move));

  group('hey length (#576)', () {
    test('a full or half length drops a stale meetTarget', () {
      for (final length in ['half', 'full']) {
        final result = change(
          'hey',
          {...defaults('hey'), 'length': 'lessThanHalf', 'meetTarget': 'x'},
          'length',
          length,
        );
        expect(result.params.containsKey('meetTarget'), isFalse);
      }
    });

    test('a partial length keeps it', () {
      final result = change(
        'hey',
        {...defaults('hey'), 'meetTarget': 'neighbors'},
        'length',
        'betweenHalfAndFull',
      );
      expect(result.params['meetTarget'], 'neighbors');
    });
  });

  group('promenade where (#989)', () {
    test('a rotationless destination writes the unspecified sentinel', () {
      for (final where in ['in', 'out', 'up', 'down']) {
        final result = change(
          'promenade',
          {...defaults('promenade'), 'direction': 'clockwise'},
          'where',
          where,
        );
        expect(
          result.params['direction'],
          ParamVocab.unspecified,
          reason: where,
        );
      }
    });

    test('a destination with a rotation leaves direction alone', () {
      final result = change(
        'promenade',
        {...defaults('promenade'), 'direction': 'clockwise'},
        'where',
        'across',
      );
      expect(result.params['direction'], 'clockwise');
    });
  });

  group('balance flag', () {
    test('on adds 4 beats and off removes them, from the current count', () {
      final on = change(
        'pull_by',
        {...defaults('pull_by'), 'beats': 2},
        'balance',
        true,
      );
      expect(on.params['beats'], 6);
      final off = change('pull_by', on.params, 'balance', false);
      expect(off.params['beats'], 2);
    });

    test('shifts a manual override too, and stays within 0..64', () {
      final high = change(
        'pull_by',
        {...defaults('pull_by'), 'beats': 62},
        'balance',
        true,
        beatsTouched: true,
      );
      expect(high.params['beats'], 64);
      final low = change(
        'pull_by',
        {...defaults('pull_by'), 'balance': true, 'beats': 2},
        'balance',
        false,
        beatsTouched: true,
      );
      expect(low.params['beats'], 0);
    });

    test('setting it to the value it already has changes nothing else', () {
      final result = change(
        'pull_by',
        {...defaults('pull_by'), 'beats': 2},
        'balance',
        false,
      );
      expect(result.params['beats'], 2);
    });
  });

  group('chain who (#976)', () {
    test('rewrites the role-implied hand', () {
      final role1s = change(
        'chain',
        {...defaults('chain'), 'hand': 'right'},
        'who',
        'role1s',
      );
      expect(role1s.params['hand'], 'left');
      final role2s = change('chain', role1s.params, 'who', 'role2s');
      expect(role2s.params['hand'], 'right');
    });

    test('seedChainHand is a no-op for another move or an unknown role', () {
      final params = <String, Object?>{'who': 'role1s', 'hand': 'right'};
      seedChainHand('allemande', params);
      expect(params['hand'], 'right');
      final unknown = <String, Object?>{'who': 'partners', 'hand': 'right'};
      seedChainHand('chain', unknown);
      expect(unknown['hand'], 'right');
    });
  });

  group('inverse pairs', () {
    test('a changed shoulder reroutes do si do to see saw and back', () {
      final seeSaw = change(
        'do_si_do',
        defaults('do_si_do'),
        'shoulder',
        'left',
      );
      expect(seeSaw.move, 'see_saw');
      final back = change(seeSaw.move, seeSaw.params, 'shoulder', 'right');
      expect(back.move, 'do_si_do');
    });
  });

  group('beats reconciliation (#262, #689)', () {
    test('a change that leaves the default put keeps an existing count', () {
      final result = change(
        'circle',
        {...defaults('circle'), 'beats': 12},
        'direction',
        'right',
      );
      expect(result.params['beats'], 12);
    });

    test('a missing beats is seeded with the canonical default', () {
      final params = defaults('circle')..remove('beats');
      final result = change('circle', params, 'direction', 'right');
      expect(result.params['beats'], defaults('circle')['beats']);
    });

    test('a manual override is kept unless aggressive mode is on and the '
        'default moved', () {
      // A swing's `prefix` shifts its canonical default from 8 to 16.
      final base = {...defaults('swing'), 'beats': 10};
      final kept = change(
        'swing',
        base,
        'prefix',
        'balance',
        beatsTouched: true,
      );
      expect(kept.params['beats'], 10);
      final aggressive = change(
        'swing',
        base,
        'prefix',
        'balance',
        beatsTouched: true,
        aggressiveBeats: true,
      );
      expect(
        aggressive.params['beats'],
        canonicalBeatsFor(taxonomy, 'swing', aggressive.params),
      );
      expect(aggressive.params['beats'], isNot(10));
    });

    test('an unowned count snaps to a moved default', () {
      final result = change(
        'swing',
        {...defaults('swing'), 'beats': 8},
        'prefix',
        'balance',
      );
      expect(
        result.params['beats'],
        canonicalBeatsFor(taxonomy, 'swing', result.params),
      );
      expect(result.params['beats'], isNot(8));
    });
  });
}
