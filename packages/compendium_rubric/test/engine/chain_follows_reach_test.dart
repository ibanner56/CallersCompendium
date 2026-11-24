import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// Heather's Hop Redux (Caller's Box #10172), as the bridge reads it: the
/// chains' "to partner" and "to neighbor N2" are not carried.
Map<String, Object?> heathersHop({String chainDir = 'across'}) => {
  'title': "Heather's Hop Redux",
  'form': 'contra',
  'formation': {'shape': 'dupleProper'},
  'progression': 'double',
  'figures': [
    {
      'move': 'swing',
      'params': {'who': 'ones'},
    },
    {
      'move': 'shoulder_round',
      'params': {'who': 'ones', 'shoulder': 'right', 'travel': 1.0},
    },
    {
      'move': 'swing',
      'params': {'who': 'neighbors', 'prefix': 'balance'},
    },
    {
      'move': 'allemande',
      'params': {'who': 'nextNeighbors', 'hand': 'left', 'travel': 1.5},
    },
    {
      'move': 'chain',
      'params': {'who': 'role2s', 'dir': chainDir},
    },
    {
      'move': 'chain',
      'params': {'who': 'role2s', 'dir': chainDir},
    },
    {
      'move': 'figure_8',
      'params': {'who': 'ones', 'fraction': 'half', 'where': 'above'},
      'progression': true,
    },
  ],
};

/// The figure index of the N2 allemande, and of the two chains after it.
const _allemande = 3;
const _firstChain = 4;
const _secondChain = 5;

/// Folds [record] and returns the formation after every figure.
List<Formation> trace(Map<String, Object?> record, {int? upTo}) {
  final dance = (parseDance(record) as Ok<Dance, DanceParseError>).value;
  final fold = FigureFold();
  var state = dance.instantiate();
  final after = <Formation>[];
  final last = upTo ?? dance.figures.length - 1;
  for (var i = 0; i <= last; i++) {
    final step = fold.step(dance.figures[i], state, index: i);
    expect(step, isA<Ok<Formation, OpError>>(), reason: 'figure $i: $step');
    state = (step as Ok<Formation, OpError>).value;
    after.add(state);
  }
  return after;
}

/// Where the robin of couple [letter] stands in [f].
Position robin(Formation f, String letter) => f
    .stateOf(
      f.dancers.keys.singleWhere(
        (id) => id.role == Role.robin && id.coupleLetter == letter,
      ),
    )
    .position;

void main() {
  group('a chain across straight after an N2 figure chains with N2', () {
    test('R1-A and R2-D swap in the first chain', () {
      // User-ruled 2026-11-24, note on #10172: "R1-A and R2-D should be the
      // ones who swap in the chain", and on #10173 "mapped forward through
      // the remainder of the other pairs of robins".
      final after = trace(heathersHop(), upTo: _firstChain);
      final before = after[_allemande];
      final chained = after[_firstChain];
      expect(robin(chained, 'A'), robin(before, 'D'));
      expect(robin(chained, 'D'), robin(before, 'A'));
      expect(robin(chained, 'C'), robin(before, 'F'));
      expect(robin(chained, 'F'), robin(before, 'C'));
    });

    test('a chain with a figure between it and the reach does not follow', () {
      final record = heathersHop();
      final figures = [...record['figures']! as List<Object?>];
      figures.insert(_firstChain, {
        'move': 'stand_still',
        'params': <String, Object?>{},
      });
      final after = trace({
        ...record,
        'figures': figures,
      }, upTo: _firstChain + 1);
      final before = after[_firstChain];
      final chained = after[_firstChain + 1];
      // Danced where the set was handed back: R1-A trades with R2-F.
      expect(robin(chained, 'A'), robin(before, 'F'));
      expect(robin(chained, 'D'), robin(before, 'D'));
    });

    test('a flagged chain does not follow', () {
      final record = heathersHop();
      final figures = [
        for (final figure in record['figures']! as List<Object?>)
          Map<String, Object?>.of(figure! as Map<String, Object?>)
            ..remove('progression'),
      ];
      figures[_firstChain]['progression'] = true;
      final after = trace({...record, 'figures': figures}, upTo: _firstChain);
      expect(
        robin(after[_firstChain], 'D'),
        isNot(robin(after[_allemande], 'A')),
      );
    });

    test('a diagonal chain does not follow', () {
      // Whatever the diagonal does here, the fold must do exactly what the
      // chain does on the set as the reach handed it back.
      final record = heathersHop(chainDir: 'leftDiagonal');
      final dance = (parseDance(record) as Ok<Dance, DanceParseError>).value;
      final fold = FigureFold();
      var state = dance.instantiate();
      for (var i = 0; i < _firstChain; i++) {
        state =
            (fold.step(dance.figures[i], state, index: i)
                    as Ok<Formation, OpError>)
                .value;
      }
      final folded = fold.step(
        dance.figures[_firstChain],
        state,
        index: _firstChain,
      );
      final direct = dance.figures[_firstChain].operation.apply(
        state,
        progressions: fold.progressions,
      );
      expect('$folded', '$direct');
      expect(
        dance.figures[_firstChain].operation
            .apply(toggleBandPhase(state), progressions: fold.progressions)
            .toString(),
        isNot('$direct'),
        reason: 'the test can tell the two phases apart',
      );
    });

    test('the set is handed back in the phase it was in', () {
      final after = trace(heathersHop(), upTo: _secondChain);
      bool anyOut(Formation f) => f.dancers.values.any((d) => d.waitingOut);
      expect(anyOut(after[_allemande]), isFalse);
      expect(anyOut(after[_firstChain]), isFalse);
      expect(anyOut(after[_secondChain]), isFalse);
    });
  });

  group('a hey straight after an N2 figure dances with N2', () {
    /// The opening of Hey-ja Vu (Caller's Box #10136) as the bridge reads
    /// it: a balanced long wave and Rory O'More, the N2 swing, the half hey.
    Map<String, Object?> heyJaVu({
      bool flagHey = false,
      String pass1 = 'role1s',
      String pass2 = 'partners',
    }) => {
      'title': 'Hey-ja Vu',
      'form': 'contra',
      'formation': {'shape': 'dupleImproper'},
      'progression': 'single',
      'figures': [
        {
          'move': 'form_long_waves',
          'params': {
            'whom': 'neighbors',
            'whomHand': 'right',
            'who': 'role2s',
            'balance': true,
          },
        },
        {
          'move': 'rory_o_more',
          'params': {'balance': false, 'slide': 'right'},
        },
        {
          'move': 'swing',
          'params': {'who': 'nextNeighbors'},
        },
        {
          'move': 'hey',
          'params': {
            'length': 'half',
            'pass1': pass1,
            'shoulder': 'left',
            'pass2': pass2,
          },
          if (flagHey) 'progression': true,
        },
      ],
    };
    const hey = 3;

    Result<Formation, OpError> heyStep(Map<String, Object?> record) {
      final dance = (parseDance(record) as Ok<Dance, DanceParseError>).value;
      final fold = FigureFold();
      var state = dance.instantiate();
      for (var i = 0; i < hey; i++) {
        state =
            (fold.step(dance.figures[i], state, index: i)
                    as Ok<Formation, OpError>)
                .value;
      }
      return fold.step(dance.figures[hey], state, index: hey);
    }

    test('the half hey runs in the N2 grouping and hands the set back', () {
      // Agent's call, 2026-11-24, from Hudson's notes on #10129 and #10136:
      // the half hey is with the couple just swung. In the grouping handed
      // back after the N2 swing two larks stand on one line and it refuses.
      final step = heyStep(heyJaVu());
      expect(step, isA<Ok<Formation, OpError>>(), reason: '$step');
      final after = (step as Ok<Formation, OpError>).value;
      expect(after.dancers.values.any((d) => d.waitingOut), isFalse);
    });

    test('a flagged hey does not follow', () {
      expect(heyStep(heyJaVu(flagHey: true)), isA<Err<Formation, OpError>>());
    });

    test('a hey whose second pass names neighbours does not follow', () {
      final step = heyStep(heyJaVu(pass2: 'neighbors'));
      final direct = heyStep(heyJaVu(pass2: 'partners'));
      expect(direct, isA<Ok<Formation, OpError>>(), reason: 'control');
      expect(step, isA<Err<Formation, OpError>>());
    });

    test('a hey whose second pass names the N2 couple follows', () {
      // A distance set is checked by where the couples started, so it reads
      // the same couple one grouping over (Waylaid in Tulsa, #4960: "Hey 1/2
      // (MR;N0L;WR)" after an N0 allemande).
      expect(
        heyStep(heyJaVu(pass2: 'nextNeighbors')),
        isA<Ok<Formation, OpError>>(),
      );
    });

    test('a hey naming neighbours does not follow', () {
      // One grouping over, `neighbors` would accept the N2 couple in their
      // place. *(Agent's call.)*
      final step = heyStep(heyJaVu(pass1: 'neighbors', pass2: 'role1s'));
      expect(step, isA<Err<Formation, OpError>>());
      expect(
        (step as Err<Formation, OpError>).error.kind,
        ErrorKind.unresolvableDancerSet,
      );
    });

    test('a followed hey is linted where it is danced', () {
      // The robins cannot be the second pass of this hey in the N2 grouping;
      // linted in the grouping handed back, the hey could not be read at all
      // and the warning was lost.
      // A flagged figure after the hey, so the record compiles at all.
      final record = heyJaVu(pass2: 'role2s');
      final dance =
          (parseDance({
                    ...record,
                    'figures': [
                      ...record['figures']! as List<Object?>,
                      {
                        'move': 'stand_still',
                        'params': <String, Object?>{},
                        'progression': true,
                      },
                    ],
                  })
                  as Ok<Dance, DanceParseError>)
              .value;
      final warnings = switch (compile(dance)) {
        Compiled(:final warnings) => warnings,
        Mismatch(:final warnings) => warnings,
        CompileError(:final warnings) => warnings,
      };
      expect(
        warnings.where(
          (w) => w.kind == WarningKind.anchorMismatch && w.opIndex == hey,
        ),
        isNotEmpty,
      );
    });
  });
}
