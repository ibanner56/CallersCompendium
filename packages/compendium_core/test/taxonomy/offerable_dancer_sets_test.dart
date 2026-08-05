import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  // The domain used in most tests: the full pair/group dancer set (no sentinel).
  final domain = ParamVocab.pairDancerSets;

  group('offerableDancerSets — mixer: true', () {
    test('returns full domain when mixer is true', () {
      final result = offerableDancerSets(domain, mixer: true);
      expect(result, domain);
    });

    test('all five partner-series tokens present when mixer is true', () {
      final result = offerableDancerSets(domain, mixer: true);
      for (final token in ParamVocab.mixerPartnerSeries) {
        expect(result, contains(token), reason: 'expected $token when mixer');
      }
    });
  });

  group('offerableDancerSets — mixer: false, no currentValue', () {
    test('all five partner-series tokens absent when mixer is false', () {
      final result = offerableDancerSets(domain, mixer: false);
      for (final token in ParamVocab.mixerPartnerSeries) {
        expect(
          result,
          isNot(contains(token)),
          reason: 'expected $token absent when not mixer',
        );
      }
    });

    test('partners (P1) always present when mixer is false', () {
      final result = offerableDancerSets(domain, mixer: false);
      expect(result, contains('partners'));
    });

    test('everyone always present when mixer is false', () {
      final result = offerableDancerSets(domain, mixer: false);
      expect(result, contains('everyone'));
    });
  });

  group('offerableDancerSets — mixer: false, stored partner-series value', () {
    // THE NON-NEGOTIABLE TEST.
    //
    // A non-mixer dance whose figure stores `nextPartners` must keep that value
    // in the offered list so FigureParamEditor._dropdown's reconciliation path
    // keeps `selectable.contains(value)` true, preventing the write-back that
    // would silently rewrite the stored value to the spec default.
    //
    // Falsification target: remove the `|| token == currentValue` guard from
    // `offerableDancerSets` — the naive version a future simplification would
    // produce. Without it, `nextPartners` is absent from the result, the
    // dropdown reconciliation falls through to the spec default, `current !=
    // value` holds, and the write-back fires. Confirm this test goes red with
    // that mutation before calling the PR ready.
    test('nextPartners retained when currentValue is nextPartners '
        '(non-mixer dance, stored value preservation)', () {
      final result = offerableDancerSets(
        domain,
        mixer: false,
        currentValue: 'nextPartners',
      );
      expect(result, contains('nextPartners'));
    });

    test(
      'other four partner tokens still absent when only nextPartners stored',
      () {
        final result = offerableDancerSets(
          domain,
          mixer: false,
          currentValue: 'nextPartners',
        );
        expect(result, isNot(contains('prevPartners')));
        expect(result, isNot(contains('thirdPartners')));
        expect(result, isNot(contains('fourthPartners')));
        expect(result, isNot(contains('fifthPartners')));
      },
    );

    test('prevPartners retained when currentValue is prevPartners', () {
      final result = offerableDancerSets(
        domain,
        mixer: false,
        currentValue: 'prevPartners',
      );
      expect(result, contains('prevPartners'));
      expect(result, isNot(contains('nextPartners')));
    });

    test('thirdPartners retained when currentValue is thirdPartners', () {
      final result = offerableDancerSets(
        domain,
        mixer: false,
        currentValue: 'thirdPartners',
      );
      expect(result, contains('thirdPartners'));
    });

    test('fourthPartners retained when currentValue is fourthPartners', () {
      final result = offerableDancerSets(
        domain,
        mixer: false,
        currentValue: 'fourthPartners',
      );
      expect(result, contains('fourthPartners'));
    });

    test('fifthPartners retained when currentValue is fifthPartners', () {
      final result = offerableDancerSets(
        domain,
        mixer: false,
        currentValue: 'fifthPartners',
      );
      expect(result, contains('fifthPartners'));
    });

    test(
      'partners (P1) still present even when a partner-series token stored',
      () {
        final result = offerableDancerSets(
          domain,
          mixer: false,
          currentValue: 'nextPartners',
        );
        expect(result, contains('partners'));
      },
    );
  });

  group('offerableDancerSets — non-partner currentValue', () {
    test('all five absent when currentValue is a non-partner token', () {
      final result = offerableDancerSets(
        domain,
        mixer: false,
        currentValue: 'neighbors',
      );
      for (final token in ParamVocab.mixerPartnerSeries) {
        expect(result, isNot(contains(token)));
      }
    });

    test('non-partner currentValue does not affect regular tokens', () {
      final result = offerableDancerSets(
        domain,
        mixer: false,
        currentValue: 'neighbors',
      );
      expect(result, contains('neighbors'));
      expect(result, contains('partners'));
    });
  });

  group('offerableDancerSets — subset domain (spec.choices)', () {
    test('only offered tokens from a restricted domain, mixer false', () {
      const restricted = ['partners', 'nextPartners', 'neighbors'];
      final result = offerableDancerSets(restricted, mixer: false);
      expect(result, ['partners', 'neighbors']);
    });

    test('all retained from restricted domain when mixer true', () {
      const restricted = ['partners', 'nextPartners', 'neighbors'];
      final result = offerableDancerSets(restricted, mixer: true);
      expect(result, restricted);
    });
  });

  group('mixerPartnerSeries constant', () {
    test('contains exactly the five v24 tokens', () {
      expect(ParamVocab.mixerPartnerSeries, [
        'prevPartners',
        'nextPartners',
        'thirdPartners',
        'fourthPartners',
        'fifthPartners',
      ]);
    });

    test('does NOT contain partners (P1)', () {
      expect(ParamVocab.mixerPartnerSeries, isNot(contains('partners')));
    });

    test('all five are present in pairDancerSets', () {
      for (final token in ParamVocab.mixerPartnerSeries) {
        expect(
          ParamVocab.pairDancerSets,
          contains(token),
          reason: '$token should be in pairDancerSets',
        );
      }
    });
  });
}
