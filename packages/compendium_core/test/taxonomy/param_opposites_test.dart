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

  test(
    'every choice slot that spells a pair is pinned, and has no opposite',
    () {
      // A choice slot is free-form, so it gets no opposite (#709: a named
      // limitation, e.g. circle direction cannot take a compound's `hand`).
      // Any slot whose choices hold both halves of a pair the registry inverts
      // is listed here, so a new one fails until someone decides whether it
      // should get an opposite of its own.
      // Every pair the registry inverts among the kinds that have opposites
      // (pinned in the table above), read from it rather than listed, so a
      // pair one of those kinds gains is checked here too.
      final pairs = {
        for (final MapEntry(key: kind, value: vocabulary) in {
          ParamKind.handedness: ParamVocab.sides,
          ParamKind.spinDirection: ParamVocab.spins,
          ParamKind.direction: ParamVocab.directions,
          ParamKind.dancerSet: ParamVocab.dancerSets,
        }.entries)
          for (final value in vocabulary)
            if (ParamOpposites.of(kind, value) case final String opposite
                when opposite != value)
              (value, opposite),
      };
      final spelled = {
        for (final move in contraTaxonomy.moves.values)
          for (final MapEntry(key: slot, value: spec) in move.params.entries)
            if (spec.kind == ParamKind.choice &&
                pairs.any(
                  (pair) =>
                      (spec.choices ?? const []).contains(pair.$1) &&
                      (spec.choices ?? const []).contains(pair.$2),
                ))
              '${move.id}.$slot',
      };
      expect(spelled, {
        'swing.endFacing',
        'slide_along_set.slide',
        'gate.direction',
        'gate.endFacing',
        'zig_zag.slide',
        'slice.slice',
        'rory_o_more.slide',
        'circle.direction',
      });
      expect(ParamOpposites.coverage(ParamKind.choice), OppositeCoverage.none);
    },
  );

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

    test('is exactly what the validator accepts, past both ends of every '
        'range, for every shipped slot', () {
      // paramDomain filters its enumeration through validate, so a value it
      // holds always validates; the hazard is an enumeration too narrow. Probe
      // beyond each numeric range and across every vocabulary in both
      // directions. Numbers are probed in the kind's own type: a Dart set
      // finds 4.0 in {4}, which validate (rightly) refuses for an int kind.
      final quarters = {for (var q = -4; q <= 16; q++) q / 4};
      final ints = {for (var i = -2; i <= 70; i++) i};
      final words = <Object>{
        ...ParamVocab.dancerSets,
        ...ParamVocab.sides,
        ...ParamVocab.spins,
        ...ParamVocab.fractions,
        ...ParamVocab.directions,
        u,
        'bogus',
        true,
        false,
      };
      for (final move in contraTaxonomy.moves.values) {
        for (final MapEntry(key: slot, value: spec) in move.params.entries) {
          final domain = paramDomain(spec);
          if (domain == null) continue;
          final numbers = spec.kind == ParamKind.rotation ? quarters : ints;
          for (final value in {...words, ...numbers, ...?spec.choices}) {
            expect(
              domain.contains(value),
              spec.validate(value),
              reason: '${move.id}.$slot: $value',
            );
          }
        }
      }
    });

    test('numeric ranges stop at their bounds', () {
      final rotation = paramDomain(
        const ParamSpec(ParamKind.rotation, defaultValue: 1.0),
      )!;
      expect(rotation, hasLength(10));
      expect(rotation, containsAll([0.25, 2.5]));
      expect(rotation, isNot(contains(0)));
      expect(rotation, isNot(contains(2.75)));
      final places = paramDomain(
        const ParamSpec(ParamKind.places, defaultValue: 4),
      )!;
      expect(places, isNot(contains(0)));
      expect(places, isNot(contains(11)));
      final beats = paramDomain(
        const ParamSpec(ParamKind.beats, defaultValue: 8),
      )!;
      expect(beats, hasLength(65));
      expect(beats, containsAll([0, 64]));
      expect(beats, isNot(contains(65)));
    });
  });
}
