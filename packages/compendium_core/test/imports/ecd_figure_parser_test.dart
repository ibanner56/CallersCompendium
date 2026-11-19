import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../figures_support.dart';

/// ADR-006 workstream W6: an English Country Dance's typed and imported lines
/// are read by the ECD grammar into ECD moves, never into contra moves.

final Taxonomy _ecd = shippedTaxonomies.forForm(DanceForm.ecd);

List<Figure> _typed(
  String line, {
  FormationShape? shape = FormationShape.dupleMinor,
  Dialect? dialect,
  ShorthandMappings? shorthands,
}) => parseFreeTextFigureEntry(
  line,
  taxonomy: _ecd,
  formationShape: shape,
  dialect: dialect,
  shorthands: shorthands,
);

Figure _one(String line, {FormationShape? shape = FormationShape.dupleMinor}) {
  final figures = _typed(line, shape: shape);
  expect(figures, hasLength(1), reason: line);
  return figures.single;
}

/// Every leaf of [figures], containers opened.
Iterable<Figure> _leaves(Iterable<Figure> figures) sync* {
  for (final f in figures) {
    if (f.isContainer) {
      yield* _leaves(f.subFigures);
    } else {
      yield f;
    }
  }
}

void main() {
  group('ECD typed entry reads ECD moves', () {
    final cases = <String, (String, Map<String, Object?>)>{
      'Circle left': ('ecd_circle', {'direction': 'left'}),
      'Circle L halfway': ('ecd_circle', {'direction': 'left', 'places': 2}),
      'star left': ('ecd_star', {'hand': 'left'}),
      'R hand star once': ('ecd_star', {'hand': 'right', 'places': 4}),
      'Partners back-to-back': (
        'ecd_back_to_back',
        {
          'who': ['partners'],
        },
      ),
      'Partner R shoulder round': (
        'ecd_shoulder_round',
        {
          'who': ['partners'],
          'shoulder': 'right',
        },
      ),
      'Neighbors arm right once around': (
        'ecd_arm_turn',
        {
          'who': ['neighbors'],
          'hand': 'right',
          'travel': 1.0,
        },
      ),
      '1st corners turn by the right hand halfway': (
        'ecd_hand_turn',
        {
          'who': ['firstCorners'],
          'hand': 'right',
          'travel': 0.5,
        },
      ),
      'Partners 2 hand turn 1½': (
        'ecd_two_hand_turn',
        {
          'who': ['partners'],
          'travel': 1.5,
        },
      ),
      '1s ½ figure 8 down through 2s': (
        'ecd_figure_eight',
        {
          'who': ['ones'],
          'whom': 'twos',
          'where': 'down',
          'fraction': 'half',
        },
      ),
      '1s and 2s set to partner': (
        'ecd_set',
        {
          'who': ['ones', 'twos'],
          'whom': 'partners',
        },
      ),
      'Robins chain': (
        'ecd_chain',
        {
          'who': ['role2s'],
        },
      ),
      'Cloverleaf turn single': ('ecd_turn_single', {'shoulder': 'cloverleaf'}),
      'turn single back to place': (
        'ecd_turn_single',
        {'destination': 'place'},
      ),
      '1s cast down to 2nd place': (
        'ecd_cast',
        {
          'who': ['ones'],
          'where': 'down',
          'destination': 'secondPlace',
        },
      ),
      'All up a double and back': (
        'ecd_forward_and_back',
        {
          'who': ['everyone'],
          'where': 'up',
          'distance': 'double',
          'goBack': true,
        },
      ),
      'Larks change by the L': (
        'ecd_change_places',
        {
          'who': ['role1s'],
          'hand': 'left',
        },
      ),
      'Partner R hand pull by': (
        'ecd_pull_by',
        {
          'who': ['partners'],
          'hand': 'right',
        },
      ),
      'swat the flea': ('ecd_swat_the_flea', {}),
      'set and link': ('ecd_set_and_link', {}),
      'Single file circle ¾ clockwise to progressed places': (
        'ecd_circle',
        {
          'direction': 'clockwise',
          'places': 3,
          'singleFile': true,
          'destination': 'progressedPlace',
        },
      ),
      'With neighbor, half poussette, robins push': (
        'ecd_poussette',
        {
          'who': ['role2s'],
          'whom': 'neighbors',
          'fraction': 'half',
          'style': 'push',
        },
      ),
      'hey for 6 halfway': ('ecd_hey_for_six', {'fraction': 'half'}),
      'contra corners': ('ecd_contra_corners', {}),
    };
    for (final MapEntry(key: line, value: (move, params)) in cases.entries) {
      test(line, () {
        final figure = _one(line);
        expect(figure.move, move);
        expect(figure.params, params);
        expect(figure.note, isNull);
        expect(_ecd.validateFigure(figure), isEmpty);
      });
    }
  });

  test('no line in an ECD dance becomes a contra move', () {
    // Each of these is a contra move when typed in a contra dance.
    const lines = [
      'Circle left',
      'star left',
      'Neighbors swing',
      'Robins chain',
      'poussette',
      'gypsy partner',
      'balance and swing',
      'Partners right shoulder round',
      'Right and left through',
      'Mad robin',
      'Box the gnat',
      'pass through',
      'Hey for four',
    ];
    for (final line in lines) {
      expect(
        parseFreeTextFigureEntry(
          line,
          taxonomy: shippedTaxonomies.forForm(DanceForm.contra),
        ).any((f) => !f.isCustom),
        isTrue,
        reason: 'contra reads "$line"',
      );
      final figures = _typed(line);
      for (final leaf in _leaves(figures)) {
        expect(
          leaf.isCustom || leaf.move.startsWith('ecd_'),
          isTrue,
          reason: '"$line" became ${leaf.move}',
        );
      }
      expect(_leaves(figures).any((f) => f.isCustom), isFalse, reason: line);
    }
  });

  test('states nothing the line leaves out (R2)', () {
    // The contra grammar reads this as a swing with `who = partners` and a
    // balance prefix. ECD's swing has no prefix (§7.2): it is a sequence.
    final balanceAndSwing = _one('balance and swing');
    expect(balanceAndSwing.isSequence, isTrue);
    expect(balanceAndSwing.subFigures.map((f) => f.move), [
      'ecd_balance',
      'ecd_swing',
    ]);
    expect(balanceAndSwing.subFigures.map((f) => f.params), [{}, {}]);
    // Contra fills in the chain's right hand; ECD leaves it unstated.
    expect(_one('Robins chain').params.containsKey('hand'), isFalse);
    // An unstated subject is not stored, so it reads as unspecified.
    final circle = _one('circle left');
    expect(_ecd.effectiveParams(circle)['who'], ['unspecified']);
  });

  test('a forward and back with no distance is a double (§9.1)', () {
    expect(_one('forward and back').params, {
      'distance': 'double',
      'goBack': true,
    });
    expect(_one('lines forward and back').params, {
      'distance': 'double',
      'goBack': true,
    });
  });

  test('`up` alone is a direction of travel, not a forward and back', () {
    expect(_one('robin up').isCustom, isTrue);
    expect(_one('up a double').move, 'ecd_forward_and_back');
  });

  group('sequences (§5.4)', () {
    test('a subject is shared by the steps of its line (§8.1)', () {
      final f = _one('1st corners set forward and turn single back to place');
      expect(f.isSequence, isTrue);
      expect(f.subFigures.map((s) => s.params), [
        {
          'who': ['firstCorners'],
          'where': 'forward',
        },
        {
          'who': ['firstCorners'],
          'destination': 'place',
        },
      ]);
      // One span for the line; the steps state no timing (§5.5).
      expect(f.beats, 8);
      expect(f.subFigures.every((s) => !s.params.containsKey('beats')), isTrue);
    });

    test('a line count is the sequence span', () {
      final f = _one('1st corners set and turn right halfway (12)');
      expect(f.isSequence, isTrue);
      expect(f.beats, 12);
    });

    test('`and back` after a star is a star back to place (§8.1)', () {
      final f = _one('Right hands across and back by the left');
      expect(f.subFigures.map((s) => [s.move, s.params]), [
        [
          'ecd_star',
          {'hand': 'right'},
        ],
        [
          'ecd_star',
          {'hand': 'left', 'destination': 'place'},
        ],
      ]);
    });

    test('a step naming other dancers stops the subject being shared', () {
      final f = _one('1s cast and 2s cross up, double figure 8');
      expect(f.subFigures.last.move, 'ecd_figure_eight');
      expect(f.subFigures.last.params, {'double': true});
    });

    test('`as` makes a meanwhile of its two sides', () {
      final f = _one('1s cast down as 2s lead up');
      expect(f.isMeanwhile, isTrue);
      expect(f.subFigures.map((s) => [s.move, s.params]), [
        [
          'ecd_cast',
          {
            'who': ['ones'],
            'where': 'down',
          },
        ],
        [
          'ecd_lead',
          {
            'who': ['twos'],
            'where': 'up',
          },
        ],
      ]);
    });

    test('`, bending the line` makes a modifier', () {
      final f = _one('up a double and back, bending the line');
      expect(f.isModifier, isTrue);
      expect(f.subFigures.map((s) => s.move), [
        'ecd_forward_and_back',
        'ecd_bend_line',
      ]);
    });

    test('`balance and box the gnat` is the gnat\'s balance flag', () {
      expect(_one('balance and box the gnat').params, {'balance': true});
    });
  });

  group('a ring\'s fraction (§7.3)', () {
    test('is two places in a duple minor, three in a triple minor', () {
      expect(_one('circle left half way').params['places'], 2);
      expect(
        _one(
          'circle left half way',
          shape: FormationShape.tripleMinor,
        ).params['places'],
        3,
      );
    });

    test('is the named couples\' ring when the subject names some', () {
      expect(
        _one(
          '1s and 2s circle left half way',
          shape: FormationShape.tripleMinor,
        ).params['places'],
        2,
      );
    });

    test('stays a note when the ring is unknown', () {
      final f = _one('circle left half way', shape: null);
      expect(f.params, {'direction': 'left'});
      expect(f.note, 'half way');
    });
  });

  group('lines it does not read', () {
    test('stay custom with their text, and are import gaps', () {
      final f = _one('1s lead down the middle and back, 2s move up (8)');
      expect(f.isCustom, isTrue);
      expect(f.customOrigin, CustomOrigin.importGap);
      expect(
        f.params['text'],
        '1s lead down the middle and back, 2s move up (8)',
      );
      expect(f.beats, 8);
    });

    test('a bare `hey` names no number of dancers, so it is not guessed', () {
      expect(_one('hey').isCustom, isTrue);
    });

    test('Heywood\'s back to back for four is unsupported (§9.1)', () {
      expect(_one('back to back for four').isCustom, isTrue);
    });

    test('a turn that names no hand is not a guess between turns', () {
      expect(_one('partners turn').isCustom, isTrue);
    });
  });

  test('a bracketed aside is kept as a note', () {
    final f = _one('Neighbor (on the side) back-to-back');
    expect(f.move, 'ecd_back_to_back');
    expect(f.note, 'on the side');
  });

  test('a leading number that is part of the figure is not a count', () {
    expect(_one('2 changes of rights and lefts').params, {'changes': 2});
    expect(_one('2 hand turn').move, 'ecd_two_hand_turn');
    expect(_one('8 circle left').params, {'direction': 'left', 'beats': 8});
  });

  test('the dialect\'s role words are read', () {
    final f = _typed('Follows chain', dialect: Dialect.leadsFollows).single;
    expect(f.move, 'ecd_chain');
    expect(f.params['who'], ['role2s']);
  });

  test('a `;` line reads clause by clause, all or nothing', () {
    expect(_typed('circle left; turn single').map((f) => f.move), [
      'ecd_circle',
      'ecd_turn_single',
    ]);
    final missed = _typed('circle left; wiggle about');
    expect(missed.single.isCustom, isTrue);
  });

  test('a contra dance still reads contra moves', () {
    final f = parseFreeTextFigureEntry(
      'circle left',
      taxonomy: shippedTaxonomies.forForm(DanceForm.contra),
    ).single;
    expect(f.move, 'circle');
  });

  test('parseEcdFigureLine never throws and only structures valid figures', () {
    final words = [
      '1s',
      'and',
      'circle',
      'left',
      ',',
      'back',
      'half',
      'by',
      'the',
      'right',
      'turn',
      'single',
      '(x',
      ')',
      'as',
      'with',
      'partner',
      'to',
      'place',
      'up',
      'a',
      'double',
      'hey',
      'for',
      'three',
      '½',
      'then',
      'star',
      'robins',
      'push',
      'poussette',
      'bending the line',
    ];
    var seed = 7;
    int next(int n) => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) % n;
    for (var i = 0; i < 3000; i++) {
      final line = [
        for (var k = 0; k < 1 + next(9); k++) words[next(words.length)],
      ].join(' ');
      final f = parseEcdFigureLine(line, ringDancers: 4);
      if (f == null || f.isCustom) continue;
      for (final leaf in _leaves([f])) {
        expect(
          ecdTaxonomy
              .validateFigure(leaf)
              .where((issue) => issue.severity == ValidationSeverity.error),
          isEmpty,
          reason: line,
        );
      }
    }
  });

  group('ecdFormationFromContra', () {
    test('maps the contra shapes an English dance was given', () {
      expect(
        ecdFormationFromContra(const Formation(FormationShape.dupleProper)),
        const Formation(FormationShape.dupleMinor),
      );
      expect(
        ecdFormationFromContra(const Formation(FormationShape.dupleImproper)),
        const Formation(FormationShape.dupleMinor, improper: true),
      );
      expect(
        ecdFormationFromContra(const Formation(FormationShape.triplet)),
        const Formation(FormationShape.threeCoupleLongways),
      );
    });

    test('keeps a shape with no clear ECD counterpart', () {
      const becket = Formation(FormationShape.becketCw, detail: 'x');
      expect(ecdFormationFromContra(becket), becket);
    });
  });

  group('Caller\'s Companion English dances', () {
    CcDanceRecord record(String type) => CcDanceRecord(
      name: 'D',
      type: type,
      formation: 'Duple Improper',
      body: [
        CcBodySection(label: 'A1', lines: ['(8) Circle left', '(8) Star left']),
      ],
    );

    test('read their lines with the ECD grammar and take an ECD shape', () {
      final dance = mapCallersCompanionDance(record('English')).dance;
      expect(dance.form, DanceForm.ecd);
      expect(dance.formation.shape, FormationShape.dupleMinor);
      expect(dance.formation.improper, isTrue);
      expect(figuresOf(dance).map((f) => [f.move, f.params]), [
        [
          'ecd_circle',
          {'direction': 'left', 'beats': 8},
        ],
        [
          'ecd_star',
          {'hand': 'left', 'beats': 8},
        ],
      ]);
    });

    test('keep English and contra lines apart in the line cache', () {
      final cache = CcFigureLineCache();
      final english = mapCallersCompanionDance(
        record('English'),
        lineCache: cache,
      ).dance;
      final contra = mapCallersCompanionDance(
        record('Contra'),
        lineCache: cache,
      ).dance;
      final again = mapCallersCompanionDance(
        record('English'),
        lineCache: cache,
      ).dance;
      expect(figuresOf(english).first.move, 'ecd_circle');
      expect(figuresOf(contra).first.move, 'circle');
      expect(contra.formation.shape, FormationShape.dupleImproper);
      expect(figuresOf(again).first.move, 'ecd_circle');
    });

    test('a compound prefix keeps each part on its step', () {
      final dance = mapCallersCompanionDance(
        CcDanceRecord(
          name: 'D',
          type: 'English',
          body: [
            CcBodySection(lines: ['(4,4) Set and turn single']),
          ],
        ),
      ).dance;
      final f = figuresOf(dance).single;
      expect(f.isSequence, isTrue);
      expect(f.beats, 8);
      expect(f.subFigures.map((s) => s.beats), [4, 4]);
    });
  });

  group('re-parsing custom figures', () {
    Figure gap(String text) =>
        customFigure(text, origin: CustomOrigin.importGap);

    test('an English dance\'s custom is re-read as ECD', () {
      final outcome = reparseImportGapFigures([
        gap('star left'),
      ], taxonomy: _ecd);
      expect(outcome.upgradedCount, 1);
      expect(outcome.figures.single.move, 'ecd_star');
    });

    test('a contra dance\'s custom is still re-read as contra', () {
      final outcome = reparseImportGapFigures([
        gap('star left'),
      ], taxonomy: shippedTaxonomies.forForm(DanceForm.contra));
      expect(outcome.figures.single.move, 'star');
    });
  });
}
