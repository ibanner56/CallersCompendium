import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The opposites ratchet (#709). The expected table is written out value by
/// value rather than derived, so a misclassification is caught, and it must
/// name every value of every kind's shared vocabulary (plus the sentinel), so
/// a new [ParamKind] or vocabulary value fails here until someone decides its
/// opposite.
void main() {
  const u = ParamVocab.unspecified;

  /// kind → every value → its opposite (null: none). A kind with no shared
  /// vocabulary lists the values it is checked on.
  final expected = <ParamKind, (OppositeCoverage, Map<Object, Object?>)>{
    ParamKind.handedness: (
      OppositeCoverage.total,
      {'right': 'left', 'left': 'right', u: u},
    ),
    ParamKind.shoulder: (
      OppositeCoverage.total,
      {'right': 'left', 'left': 'right', u: u},
    ),
    ParamKind.spinDirection: (
      OppositeCoverage.total,
      {'clockwise': 'counterclockwise', 'counterclockwise': 'clockwise', u: u},
    ),
    ParamKind.direction: (
      OppositeCoverage.partial,
      {
        'along': null,
        'across': null,
        'rightDiagonal': 'leftDiagonal',
        'leftDiagonal': 'rightDiagonal',
        'in': 'out',
        'out': 'in',
        'up': 'down',
        'down': 'up',
        u: u,
      },
    ),
    for (final kind in [ParamKind.dancerSet, ParamKind.dancerPair])
      kind: (
        OppositeCoverage.partial,
        {
          'everyone': null,
          'role1s': 'role2s',
          'role2s': 'role1s',
          'ones': 'twos',
          'twos': 'ones',
          'firstCorners': 'secondCorners',
          'secondCorners': 'firstCorners',
          'partners': null,
          'neighbors': null,
          'sameRoles': null,
          'shadows': null,
          'secondShadows': null,
          'prevNeighbors': null,
          'nextNeighbors': null,
          'thirdNeighbors': null,
          'fourthNeighbors': null,
          'prevPartners': null,
          'nextPartners': null,
          'thirdPartners': null,
          'fourthPartners': null,
          'fifthPartners': null,
          'centers': null,
          'onesRole1': null,
          'onesRole2': null,
          'twosRole1': null,
          'twosRole2': null,
          u: u,
        },
      ),
    ParamKind.fraction: (
      OppositeCoverage.none,
      {for (final f in ParamVocab.fractions) f: null},
    ),
    ParamKind.rotation: (
      OppositeCoverage.none,
      {0.5: null, 1.0: null, u: null},
    ),
    ParamKind.places: (OppositeCoverage.none, {1: null, 4: null}),
    ParamKind.beats: (OppositeCoverage.none, {0: null, 8: null}),
    ParamKind.choice: (OppositeCoverage.none, {'left': null, 'right': null}),
    ParamKind.text: (OppositeCoverage.none, {'anything': null}),
    ParamKind.flag: (OppositeCoverage.none, {true: null, false: null}),
  };

  test('every ParamKind is in the pinned table', () {
    expect(expected.keys.toSet(), ParamKind.values.toSet());
  });

  test('each kind has the pinned coverage', () {
    for (final entry in expected.entries) {
      expect(
        ParamOpposites.coverage(entry.key),
        entry.value.$1,
        reason: entry.key.name,
      );
    }
  });

  test('each value has the pinned opposite', () {
    for (final entry in expected.entries) {
      for (final value in entry.value.$2.entries) {
        expect(
          ParamOpposites.of(entry.key, value.key),
          value.value,
          reason: '${entry.key.name}: ${value.key}',
        );
      }
    }
  });

  test('the table names every value of each shared vocabulary', () {
    // What makes a new vocabulary value fail here rather than silently get
    // "no opposite".
    final vocab = <ParamKind, List<String>>{
      ParamKind.handedness: ParamVocab.sides,
      ParamKind.shoulder: ParamVocab.sides,
      ParamKind.spinDirection: ParamVocab.spins,
      ParamKind.direction: ParamVocab.directions,
      ParamKind.dancerSet: ParamVocab.dancerSets,
      ParamKind.dancerPair: ParamVocab.dancerSets,
      ParamKind.fraction: ParamVocab.fractions,
    };
    for (final entry in vocab.entries) {
      expect(expected[entry.key]!.$2.keys.toSet(), {
        ...entry.value,
        if (entry.key != ParamKind.fraction) u,
      }, reason: entry.key.name);
    }
  });

  test('opposites are an involution', () {
    for (final entry in expected.entries) {
      for (final value in entry.value.$2.keys) {
        final opposite = ParamOpposites.of(entry.key, value);
        if (opposite == null) continue;
        expect(ParamOpposites.of(entry.key, opposite), value);
      }
    }
  });

  test('paired dancers reuse the single pair-inversion source', () {
    for (final who in ParamVocab.dancerSets) {
      expect(
        ParamOpposites.of(ParamKind.dancerSet, who),
        invertPairDancerSet(who),
      );
    }
  });

  group('paramDomain', () {
    test('follows a spec\'s choices, and is null only for free text', () {
      expect(
        paramDomain(
          const ParamSpec(
            ParamKind.dancerSet,
            defaultValue: 'role1s',
            choices: ['role1s', 'role2s'],
          ),
        ),
        {'role1s', 'role2s'},
      );
      expect(
        paramDomain(const ParamSpec(ParamKind.text, defaultValue: '')),
        isNull,
      );
      expect(paramDomain(const ParamSpec(ParamKind.places, defaultValue: 4)), {
        for (var i = 1; i <= 10; i++) i,
      });
    });

    test('a rotation admits the sentinel only when its choices list it', () {
      final plain = paramDomain(
        const ParamSpec(ParamKind.rotation, defaultValue: 1.0),
      )!;
      expect(plain, contains(0.25));
      expect(plain, contains(2.5));
      expect(plain, isNot(contains(u)));
      expect(
        paramDomain(
          const ParamSpec(ParamKind.rotation, defaultValue: u, choices: [u]),
        ),
        contains(u),
      );
    });

    test('every value of every shipped slot domain validates', () {
      for (final move in contraTaxonomy.moves.values) {
        for (final spec in move.params.values) {
          for (final value in paramDomain(spec) ?? const <Object>{}) {
            expect(spec.validate(value), isTrue, reason: '${move.id}: $value');
          }
        }
      }
    });
  });
}
