import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// ADR-006 §12.1 F5: the opt-in migration of an English dance stored with
/// contra moves.

Figure _f(String move, [Map<String, Object?> params = const {}]) =>
    testFigure(move: move, params: params);

Figure? _twin(String move, [Map<String, Object?> params = const {}]) =>
    ecdTwinOfContraMove(_f(move, params));

void main() {
  group('a contra move with a clear ECD twin becomes it', () {
    final cases =
        <(String, Map<String, Object?>), (String, Map<String, Object?>)>{
          ('circle', {'direction': 'left', 'places': 3, 'beats': 8}): (
            'ecd_circle',
            {'direction': 'left', 'places': 3, 'beats': 8},
          ),
          ('star', {'hand': 'right', 'grip': 'none'}): (
            'ecd_star',
            {'hand': 'right'},
          ),
          ('allemande', {'who': 'partners', 'hand': 'left', 'travel': 1.5}): (
            'ecd_hand_turn',
            {
              'who': ['partners'],
              'hand': 'left',
              'travel': 1.5,
            },
          ),
          ('do_si_do', {'who': 'neighbors'}): (
            'ecd_back_to_back',
            {
              'who': ['neighbors'],
            },
          ),
          ('see_saw', {'who': 'partners'}): (
            'ecd_back_to_back',
            {
              'who': ['partners'],
              'shoulder': 'left',
            },
          ),
          ('swing', {'who': 'partners', 'prefix': 'none'}): (
            'ecd_swing',
            {
              'who': ['partners'],
            },
          ),
          ('chain', {'who': 'role2s', 'where': 'across'}): (
            'ecd_chain',
            {
              'who': ['role2s'],
              'where': 'across',
            },
          ),
          ('long_lines', {'beats': 8}): (
            'ecd_forward_and_back',
            {'beats': 8, 'goBack': true, 'distance': 'double'},
          ),
          (
            'forward_and_back',
            {'formation': 'linesOfThree', 'goBack': false},
          ): (
            'ecd_forward_and_back',
            {
              'formation': 'linesOfThree',
              'goBack': false,
              'distance': 'double',
              // A forward with no back is 4 beats in contra.
              'beats': 4,
            },
          ),
          ('balance_the_ring', {}): ('ecd_balance_ring', {}),
        };
    for (final c in cases.entries) {
      test('${c.key.$1} ${c.key.$2}', () {
        final twin = _twin(c.key.$1, c.key.$2);
        expect(twin, isNotNull);
        expect(twin!.move, c.value.$1);
        expect(twin.params, c.value.$2);
      });
    }
  });

  test('a contra default is never stored on the twin (R2)', () {
    // Contra's allemande defaults to neighbors, right, 1½; none is stated.
    final twin = _twin('allemande')!;
    expect(twin.params, isEmpty);
    expect(ecdTaxonomy.effectiveParams(twin)['who'], ['unspecified']);
  });

  test('an assumed subject is not carried (R2)', () {
    final assumed = Figure(
      move: 'swing',
      params: const {'who': 'partners'},
      assumedSubject: true,
    );
    final twin = ecdTwinOfContraMove(assumed)!;
    expect(twin.params.containsKey('who'), isFalse);
    expect(twin.assumedSubject, isFalse);
  });

  test(
    'a move with no twin, or a value the twin cannot hold, stays contra',
    () {
      expect(_twin('hey', {'pass1': 'role2s'}), isNull);
      expect(_twin('poussette'), isNull);
      expect(_twin('petronella'), isNull);
      expect(_twin('california_twirl'), isNull);
      // `who` names the pair in front, passing first or facing in, which is
      // not ECD's subject.
      expect(_twin('mad_robin', {'who': 'role2s'}), isNull);
      expect(_twin('circular_hey', {'who': 'neighbors'}), isNull);
      expect(_twin('form_long_waves', {'who': 'role1s'}), isNull);
      // Short-wave parts the ECD short wave does not show.
      expect(_twin('form_short_waves', {'axis': 'across'}), isNull);
      // A wrist-grip star: the ECD star has no grip.
      expect(_twin('star', {'hand': 'right', 'grip': 'wristGrip'}), isNull);
      // A balance-and-swing: the ECD swing has no balance before it.
      expect(_twin('swing', {'prefix': 'balance'}), isNull);
      // A swing ending facing along: not an ECD ending.
      expect(_twin('swing', {'endFacing': 'along'}), isNull);
      // Forward and back in squares: not an ECD formation.
      expect(_twin('forward_and_back', {'formation': 'inSquares'}), isNull);
      // ECD moves and customs are not contra moves.
      expect(_twin('ecd_circle'), isNull);
      expect(ecdTwinOfContraMove(customFigure('circle left')), isNull);
    },
  );

  test('a value the move name states is not in the way', () {
    // The editor stores a see saw's left shoulder and a turn alone's empty
    // text; neither stops the conversion.
    expect(
      _twin('see_saw', {'who': 'partners', 'shoulder': 'left'}),
      _f('ecd_back_to_back', {
        'who': ['partners'],
        'shoulder': 'left',
      }),
    );
    expect(
      _twin('contra_corners', {'who': 'ones', 'custom': ''}),
      _f('ecd_contra_corners', {
        'who': ['ones'],
      }),
    );
    expect(
      _twin('turn_alone', {'custom': 'to the right', 'beats': 4}),
      _f('ecd_turn_alone', {'custom': 'to the right', 'beats': 4}),
    );
  });

  test('a figure with no count keeps its contra length', () {
    // A pass through is 2 beats in contra and 4 in ECD.
    expect(
      contraTaxonomy.resolve('pass_through')!.params['beats']!.defaultValue,
      isNot(
        ecdTaxonomy.resolve('ecd_pass_through')!.params['beats']!.defaultValue,
      ),
    );
    expect(
      _twin('pass_through')!.params['beats'],
      contraTaxonomy.resolve('pass_through')!.params['beats']!.defaultValue,
    );
    // A count that follows what the figure states: a forward and back that
    // does not go back is 4 beats in contra.
    expect(_twin('long_lines', {'goBack': false})!.params['beats'], 4);
    expect(_twin('long_lines')!.params.containsKey('beats'), isFalse);
    // A stated count is kept as stated.
    expect(_twin('pass_through', {'beats': 4})!.params['beats'], 4);
  });

  group('a contra move with no twin is read from its words', () {
    test('when its words read as an ECD figure', () {
      // A contra promenade has no twin; "partner promenade" reads in ECD.
      expect(_twin('promenade', {'who': 'partners'}), isNull);
      final read = ecdReadingOfContraWording(
        _f('promenade', {'who': 'partners', 'beats': 8}),
      )!;
      expect(read.move, 'ecd_promenade');
      expect(read.params['who'], ['partners']);
      expect(read.params['beats'], 8);
    });

    test('keeping its note and progression mark', () {
      final read = ecdReadingOfContraWording(
        testFigure(
          move: 'promenade',
          params: {'who': 'partners'},
          note: 'slowly',
          progression: true,
        ),
      )!;
      expect(read.note, 'slowly');
      expect(read.progression, isTrue);
    });

    test('not when its words mean something else in ECD', () {
      // A contra petronella's words hide whether it includes the balance.
      expect(ecdReadingOfContraWording(_f('petronella')), isNull);
      expect(ecdReadingOfContraWording(_f('poussette')), isNull);
      expect(
        ecdReadingOfContraWording(_f('mad_robin', {'who': 'role2s'})),
        isNull,
      );
    });

    test('not when its words do not read in full', () {
      expect(
        ecdReadingOfContraWording(_f('california_twirl', {'who': 'partners'})),
        isNull,
      );
    });

    test('from its own words, never its wording override', () {
      // The override names another move; the promenade stays a promenade.
      final read = ecdReadingOfContraWording(
        Figure(
          move: 'promenade',
          params: const {'who': 'partners'},
          wordingOverride: 'gents chain',
        ),
      )!;
      expect(read.move, 'ecd_promenade');
      expect(read.wordingOverride, 'gents chain');
    });

    test('with the values its words show, never fewer', () {
      // The list shows "neighbor balance & pull by right": the balance is
      // read too (a balance, then the pull by), never dropped.
      final read = ecdReadingOfContraWording(
        _f('pull_by', {
          'who': 'neighbors',
          'balance': true,
          'hand': 'right',
          'beats': 4,
        }),
      )!;
      expect(read.subFigures.map((f) => f.move), [
        'ecd_balance',
        'ecd_pull_by',
      ]);
      expect(read.params['beats'], 4);
    });

    test('not when its words hide a value it states', () {
      // "partner promenade" does not show who it ends with.
      expect(
        ecdReadingOfContraWording(
          _f('promenade', {'who': 'partners', 'destination': 'neighbors'}),
        ),
        isNull,
      );
    });

    test('not when its reading drops a value the contra editor stored', () {
      // The contra editor seeds every param, defaults included: a promenade
      // entered by hand stores where it goes and which way. "partner
      // promenade" reads in ECD without either, and a promenade has no twin
      // to say they mean the same there, so it stays contra.
      final promenade = _f('promenade', {
        ...contraTaxonomy.entryParams('promenade'),
        'beats': 8,
      });
      expect(ecdReadingOfContraWording(promenade), isNull);
      final out = migrateEcdDance(
        figures: [promenade],
        formation: const Formation(FormationShape.dupleMinor),
      );
      expect(out.figures.single.move, 'promenade');
      expect(out.movesConverted, 0);
      // A short wave is never re-read. Not yet exercised: its contra words
      // spell out its center and sides, which the ECD grammar does not read
      // today, so this passes without the deny list too. It guards a grammar
      // that later does.
      expect(
        ecdReadingOfContraWording(
          _f(
            'form_short_waves',
            contraTaxonomy.entryParams('form_short_waves'),
          ),
        ),
        isNull,
      );
    });

    test('carries a hidden value its twin carries onto the twin step', () {
      // A balance and swing entered by hand stores the swing's `endFacing:
      // in`, which its words hide; the swing's twin carries it.
      final swing = _f('swing', {
        ...contraTaxonomy.entryParams('swing'),
        'prefix': 'balance',
        'beats': 16,
      });
      final read = ecdReadingOfContraWording(swing)!;
      expect(read.subFigures.map((f) => f.move), ['ecd_balance', 'ecd_swing']);
      expect(read.subFigures.last.params['endFacing'], 'in');
      expect(read.subFigures.first.params.containsKey('endFacing'), isFalse);
    });

    test('a value the reading holds under another key is not dropped', () {
      // Side couples forward and back: the ECD move's `formation` has no
      // side couples, and the reading says who instead.
      final read = ecdReadingOfContraWording(
        _f('forward_and_back', {
          'formation': 'sideCouples',
          'goBack': true,
          'beats': 8,
        }),
      )!;
      expect(read.move, 'ecd_forward_and_back');
      expect(read.params['who'], ['sideCouples']);
      // A figure 8's `where: none` states no direction, so there is nothing
      // to keep. (One entered by hand also stores the editor's `lead`, which
      // its words hide and the ECD figure eight has no place for, so it
      // stays contra.)
      expect(
        ecdReadingOfContraWording(
          _f('figure_8', {'who': 'ones', 'where': 'none'}),
        )?.move,
        'ecd_figure_eight',
      );
      expect(
        ecdReadingOfContraWording(
          _f('figure_8', {...contraTaxonomy.entryParams('figure_8')}),
        ),
        isNull,
      );
    });

    test('not when its reading states a value it stores as another', () {
      // "role2s 1¼ figure 8 across" reads in ECD as the 1st role2 doing a
      // quarter figure eight: the dancers and the amount both change.
      expect(
        ecdReadingOfContraWording(
          _f('figure_8', {
            'who': 'role2s',
            'where': 'across',
            'fraction': 'other',
            'amount': 1.25,
            'beats': 8,
          }),
        ),
        isNull,
      );
    });

    test('a value carried onto the twin step takes its ECD form', () {
      // A turn alone's seeded `who: everyone` is carried as ECD's list.
      final read = ecdReadingOfContraWording(
        _f('turn_alone', contraTaxonomy.entryParams('turn_alone')),
      )!;
      expect(read.move, 'ecd_turn_alone');
      expect(read.params['who'], ['everyone']);
    });

    test('as a sequence at the top level only', () {
      // "partner balance & swing" reads as an ECD balance then swing, and
      // keeps the 16 beats the contra balance and swing danced.
      final swing = _f('swing', {'who': 'partners', 'prefix': 'balance'});
      final read = ecdReadingOfContraWording(swing)!;
      expect(read.isSequence, isTrue);
      expect(read.subFigures.map((f) => f.move), ['ecd_balance', 'ecd_swing']);
      expect(read.params['beats'], 16);
      final top = migrateEcdDance(
        figures: [swing],
        formation: const Formation(FormationShape.dupleMinor),
      );
      expect(top.figures.single.isSequence, isTrue);
      // Inside a sequence it stays contra: containers never nest.
      final nested = migrateEcdDance(
        figures: [
          Figure.sequence(figures: [swing, _f('circle')], beats: 24),
        ],
        formation: const Formation(FormationShape.dupleMinor),
      );
      expect(nested.figures.single.subFigures.map((f) => f.move), [
        'swing',
        'ecd_circle',
      ]);
    });

    test('not when its subject was assumed (R2)', () {
      expect(
        ecdReadingOfContraWording(
          testFigure(
            move: 'promenade',
            params: {'who': 'partners'},
            assumedSubject: true,
          ),
        ),
        isNull,
      );
    });

    test('migrateEcdDance counts it as a converted move', () {
      final figures = [
        _f('promenade', {'who': 'partners', 'beats': 8}),
      ];
      const formation = Formation(FormationShape.dupleMinor);
      final out = migrateEcdDance(figures: figures, formation: formation);
      expect(out.movesConverted, 1);
      expect(out.figures.single.move, 'ecd_promenade');
    });
  });

  test('note, progression and overrides are kept', () {
    final f = Figure(
      move: 'circle',
      params: const {'direction': 'left'},
      note: 'slowly',
      progression: true,
      walkthroughOverride: 'w',
      wordingOverride: 'o',
    );
    final twin = ecdTwinOfContraMove(f)!;
    expect(twin.note, 'slowly');
    expect(twin.progression, isTrue);
    expect(twin.walkthroughOverride, 'w');
    expect(twin.wordingOverride, 'o');
  });

  group('migrateEcdDance', () {
    test('converts moves, re-reads gap lines, maps the shape', () {
      final figures = [
        _f('circle', {'direction': 'left', 'beats': 8}),
        customFigure(
          'partners set and turn single',
          origin: CustomOrigin.importGap,
        ),
        customFigure('my own words'),
        _f('hey', {'pass1': 'role2s'}),
        Figure.sequence(
          figures: [
            _f('balance', {'who': 'neighbors'}),
            _f('swing', {'who': 'neighbors'}),
          ],
          beats: 16,
        ),
      ];
      final out = migrateEcdDance(
        figures: figures,
        formation: const Formation(FormationShape.dupleImproper),
      );
      expect(out.movesConverted, 3);
      expect(out.linesReread, 1);
      expect(
        out.formation,
        const Formation(FormationShape.dupleMinor, improper: true),
      );
      expect(out.figures[0].move, 'ecd_circle');
      expect(out.figures[1].move, 'sequence');
      expect(out.figures[1].subFigures.map((f) => f.move), [
        'ecd_set',
        'ecd_turn_single',
      ]);
      // A custom the caller typed is theirs: untouched.
      expect(out.figures[2], figures[2]);
      expect(out.figures[3], figures[3]);
      expect(out.figures[4].subFigures.map((f) => f.move), [
        'ecd_balance',
        'ecd_swing',
      ]);
      expect(out.figures[4].beats, 16);
      expect(
        out.changes(const Formation(FormationShape.dupleImproper)),
        isTrue,
      );
    });

    test('a dance already in ECD terms has nothing to change', () {
      final figures = [
        _f('ecd_circle', {'direction': 'left'}),
      ];
      const formation = Formation(FormationShape.dupleMinor);
      final out = migrateEcdDance(figures: figures, formation: formation);
      expect(out.changes(formation), isFalse);
      expect(identical(out.figures, figures), isTrue);
    });

    test('every twin converts the figure the contra editor seeds', () {
      // A guard that every twin-table entry can convert something: each move
      // as picked in the contra editor (its entry params, as stored) must
      // become a valid ECD figure. ecdTwinOfContraMove returns null for an
      // invalid twin, so a non-null twin is a valid one.
      final c = contraTaxonomy;
      for (final id in ecdMigratableContraMoves) {
        final seeded = c.entryParams(id);
        final move = c.resolvedMoveId(testFigure(move: id, params: seeded));
        final params = c.withoutListedAliasPins(move, seeded);
        final twin = ecdTwinOfContraMove(
          testFigure(move: move, params: params),
        );
        expect(twin, isNotNull, reason: '$id stored as $move $params');
        expect(
          ecdTaxonomy
              .validateFigure(twin!)
              .where((i) => i.severity == ValidationSeverity.error),
          isEmpty,
          reason: id,
        );
      }
    });
  });
}
