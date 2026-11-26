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
          'direction': 'down',
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
    expect(balanceAndSwing.subFigures.map((f) => f.params), [
      <String, Object?>{},
      <String, Object?>{},
    ]);
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
            'direction': 'down',
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

  group('states only what the line says (review guards)', () {
    test('a count over the beats range leaves the line custom, as typed', () {
      for (final line in [
        'circle left 65 beats',
        'circle left (100)',
        'set and turn single (100)',
        '1s cast down as 2s lead up (100)',
      ]) {
        final f = _one(line);
        expect(f.isCustom, isTrue, reason: line);
        expect(f.params['text'], line, reason: line);
      }
      expect(parseEcdFigureLine('circle left', beats: 100)!.isCustom, isTrue);
      final imported = mapCallersCompanionDance(
        CcDanceRecord(
          name: 'D',
          type: 'English',
          body: [
            CcBodySection(lines: ['(100) Circle left']),
          ],
        ),
      ).dance;
      expect(figuresOf(imported).single.isCustom, isTrue);
      // Control: 64 is the last count read.
      expect(_one('circle left (64)').params['beats'], 64);
    });

    test('a step naming dancers before and after a movement is not read', () {
      for (final line in [
        '1s turn 2s by the right',
        'partners turn neighbors by the right',
        '1s swing 2s',
        'partners back to back neighbors',
      ]) {
        expect(_one(line).isCustom, isTrue, reason: line);
      }
      // Controls: one group of dancers, on either side, still reads.
      expect(_one('partners turn by the right').move, 'ecd_hand_turn');
      expect(_one('turn partner by the right').params['who'], ['partners']);
    });

    test('a preposition the movement does not show is not read as `whom`', () {
      for (final line in [
        '1s cast to 2s',
        '1s lead with 2s',
        '1s cast through 2s',
        '1s mad robin with 2s',
        'fall back to partner',
        'hey for three with 2s',
      ]) {
        expect(_one(line).isCustom, isTrue, reason: line);
      }
      // Controls: each movement's own word.
      expect(_one('1s cast around 2s').params['whom'], 'twos');
      expect(_one('1s lead through 2s').params['whom'], 'twos');
      expect(_one('fall back with partner').params['whom'], 'partners');
    });

    test('a cast reads contra cast\'s shape (ADR-006 §9.4)', () {
      Map<String, Object?> cast(String line) {
        final f = _one(line);
        expect(f.move, 'ecd_cast', reason: line);
        return f.params;
      }

      // "Cast off" is down one place unless a count is stated.
      expect(cast('1s cast off'), {
        'who': ['ones'],
        'direction': 'down',
        'places': 1,
      });
      expect(cast('1s cast off two places'), {
        'who': ['ones'],
        'direction': 'down',
        'places': 2,
      });
      expect(cast('1s cast up one place'), {
        'who': ['ones'],
        'direction': 'up',
        'places': 1,
      });
      // A bare side is the shoulder turned over.
      expect(cast('1s cast left'), {
        'who': ['ones'],
        'direction': 'left',
      });
      expect(cast('1s cast down to the bottom'), {
        'who': ['ones'],
        'direction': 'down',
        'destination': 'bottom',
      });
      expect(cast('cast to top'), {'destination': 'top'});
      // A way round is the shoulder: clockwise over the right.
      expect(cast('1s cast clockwise'), {
        'who': ['ones'],
        'direction': 'right',
      });
      expect(cast('1s cast counterclockwise around 2s'), {
        'who': ['ones'],
        'direction': 'left',
        'whom': 'twos',
      });
      // A role never implies a shoulder (§9.4).
      expect(cast('robins cast back'), {
        'who': ['role2s'],
      });
      expect(cast('1s cast to the top'), {
        'who': ['ones'],
        'destination': 'top',
      });
      // A cast off that says where it ends states no count.
      expect(cast('1s cast off to the bottom'), {
        'who': ['ones'],
        'direction': 'down',
        'destination': 'bottom',
      });
      expect(cast('1s cast off to 3rd place'), {
        'who': ['ones'],
        'direction': 'down',
        'destination': 'thirdPlace',
      });
      // What a cast displays reads back in: `back` states nothing.
      expect(cast('ones cast back'), {
        'who': ['ones'],
      });
      expect(cast('ones cast back left'), {
        'who': ['ones'],
        'direction': 'left',
      });
      expect(cast('ones cast back around twos'), {
        'who': ['ones'],
        'whom': 'twos',
      });
      // Other movements still read `to top` as dancers.
      expect(_one('1s set to top').params['whom'], 'top');
      expect(_one('2s honour to bottom couple').move, 'ecd_honor');
      // `the top` is no dancer phrase, so only a cast reads it.
      expect(_one('1s set to the top').isCustom, isTrue);
      expect(cast('1s cast'), {
        'who': ['ones'],
      });
      // A way to travel is not a shoulder; a shoulder and a way up or down
      // can't both be held; the ends of the set are a cast's alone.
      for (final line in [
        '1s cast to the left',
        '1s cast down right',
        '1s cast back down',
        '1s cast left clockwise',
        '1s cast around',
        '1s cast to the bottom to 2nd place',
        '1s lead down to the bottom',
      ]) {
        expect(_one(line).isCustom, isTrue, reason: line);
      }
    });

    test('a hand cast is a gate by its own name (ADR-006 §9.4)', () {
      final f = _one('1s hand cast 2s');
      expect(f.move, 'ecd_hand_cast');
      expect(f.params, {
        'who': ['ones'],
        'whom': 'twos',
      });
      expect(_one('hand cast').move, 'ecd_hand_cast');
    });

    test('a stated ring size with no fraction to hold it is not read', () {
      for (final line in ['circle six', 'circle left 8', 'star right 6']) {
        expect(_one(line).isCustom, isTrue, reason: line);
      }
      expect(_one('4 hands across').isCustom, isTrue);
      // Control: with a fraction, the size gives the places.
      expect(_one('circle six left half way').params['places'], 3);
    });

    test('`to the right` is a way to travel, never a hand', () {
      expect(_one('turn to the right').isCustom, isTrue);
      expect(_one('star to the left').isCustom, isTrue);
      expect(_one('circle to the left').params['direction'], 'left');
      // A turn single's side is the side turned to.
      expect(_one('turn single to the right').params['shoulder'], 'right');
    });

    test('a ring movement does not take an earlier step\'s subject', () {
      final f = _one('1s set and circle left');
      expect(f.isSequence, isTrue);
      expect(f.subFigures.first.params['who'], ['ones']);
      expect(f.subFigures.last.params.containsKey('who'), isFalse);
      final star = _one(
        '1s set and right hands across half way',
        shape: FormationShape.tripleMinor,
      ).subFigures.last;
      expect(star.params.containsKey('who'), isFalse);
      expect(star.params['places'], 3);
    });

    test('a poussette\'s subject is not stored as the dancers who push', () {
      expect(_one('1s and 2s half poussette').isCustom, isTrue);
      expect(_one('all once poussette').params.containsKey('who'), isFalse);
      expect(_one('half poussette, 2s push').params['who'], ['twos']);
    });

    test('a bare `improper` is not read as everyone ending improper', () {
      expect(_one('1s cross, improper').isCustom, isTrue);
      expect(
        _one('1s cross, ending improper').params['destination'],
        'allImproper',
      );
    });

    test('gentleman and gentlemen are read as role words, never shown', () {
      final f = _one('gentlemen cross');
      expect(f.move, 'ecd_cross');
      expect(f.params['who'], ['role1s']);
      final kept = _one('1st gentleman cast a double figure eight');
      expect(kept.toString().toLowerCase(), isNot(contains('gentlem')));
    });

    test(
      'an English dance\'s start is improper only when the source says so',
      () {
        CcDanceRecord rec({String? formation, bool usr = false}) =>
            CcDanceRecord(
              name: 'D',
              type: 'English',
              formation: formation,
              formationFamily: usr ? 'Duple Minor' : null,
              contraForm: usr ? '' : null,
              fromUsrColumns: usr,
              body: const [],
            );
        final empty = mapCallersCompanionDance(rec(formation: '')).dance;
        expect(empty.formation.improper, isFalse);
        final usr = mapCallersCompanionDance(rec(usr: true)).dance;
        expect(usr.formation.shape, FormationShape.dupleMinor);
        expect(usr.formation.improper, isFalse);
        final text = mapCallersCompanionDance(rec(formation: 'Duple Minor'));
        expect(text.dance.formation.shape, FormationShape.dupleMinor);
        // Control: a stated improper start is kept.
        final stated = mapCallersCompanionDance(
          rec(formation: 'Duple Improper'),
        ).dance;
        expect(stated.formation.improper, isTrue);
        final other = mapCallersCompanionDance(
          CcDanceRecord(
            name: 'D',
            type: 'English',
            formationOther: 'Duple Improper',
            fromUsrColumns: true,
            body: const [],
          ),
        ).dance;
        expect(other.formation.improper, isTrue);
      },
    );

    test('the line cache keeps a line apart per ring size', () {
      final cache = CcFigureLineCache();
      Dance dance(String formation) => mapCallersCompanionDance(
        CcDanceRecord(
          name: 'D',
          type: 'English',
          formation: formation,
          body: [
            CcBodySection(lines: ['(8) circle left half way']),
          ],
        ),
        lineCache: cache,
      ).dance;
      expect(figuresOf(dance('Duple Proper')).single.params['places'], 2);
      expect(figuresOf(dance('Triple Minor')).single.params['places'], 3);
    });
  });

  group('a caller\'s library wordings (Caller\'s Companion, English)', () {
    // Single-figure lines a real caller's library writes, which fell back to
    // custom text before the grammar read them. Each case is the move, its
    // params and the figure's note.
    final cases = <String, (String, Map<String, Object?>, String?)>{
      // `trade` is `change`: `by right` reads as `change by the L` does.
      'First corners trade by right': (
        'ecd_change_places',
        {
          'who': ['firstCorners'],
          'hand': 'right',
        },
        null,
      ),
      'Second corners trade by right': (
        'ecd_change_places',
        {
          'who': ['secondCorners'],
          'hand': 'right',
        },
        null,
      ),
      'Second corners trade by LEFT': (
        'ecd_change_places',
        {
          'who': ['secondCorners'],
          'hand': 'left',
        },
        null,
      ),
      'Second diagonals trade by right': (
        'ecd_change_places',
        {
          'who': ['secondDiagonals'],
          'hand': 'right',
        },
        null,
      ),
      // Change places' `hand` is the side passed, so a shoulder is that
      // side (the maintainer, 26 November 2026).
      'trade by right shoulder': ('ecd_change_places', {'hand': 'right'}, null),
      'role1s change by R shoulder': (
        'ecd_change_places',
        {
          'who': ['role1s'],
          'hand': 'right',
        },
        null,
      ),
      'role1s change by the left shoulder': (
        'ecd_change_places',
        {
          'who': ['role1s'],
          'hand': 'left',
        },
        null,
      ),
      // `pass ... by` a side is the shoulder passed.
      'Pass P by L': (
        'ecd_pass_through',
        {
          'who': ['partners'],
          'shoulder': 'left',
        },
        null,
      ),
      'Pass P by R': (
        'ecd_pass_through',
        {
          'who': ['partners'],
          'shoulder': 'right',
        },
        null,
      ),
      'Pass Partner by Right': (
        'ecd_pass_through',
        {
          'who': ['partners'],
          'shoulder': 'right',
        },
        null,
      ),
      'Pass Partner by Left': (
        'ecd_pass_through',
        {
          'who': ['partners'],
          'shoulder': 'left',
        },
        null,
      ),
      'Pass N by R': (
        'ecd_pass_through',
        {
          'who': ['neighbors'],
          'shoulder': 'right',
        },
        null,
      ),
      // `all`/`everyone` adds no dancers to a pair named after it.
      'Everyone Partner two-hand turn': (
        'ecd_two_hand_turn',
        {
          'who': ['partners'],
        },
        null,
      ),
      'All Partner Set': (
        'ecd_set',
        {
          'who': ['partners'],
        },
        null,
      ),
      'All Turn single left': (
        'ecd_turn_single',
        {
          'who': ['everyone'],
          'shoulder': 'left',
        },
        null,
      ),
      'Partners all 2-hand turn': (
        'ecd_two_hand_turn',
        {
          'who': ['partners'],
        },
        null,
      ),
      'Partner Set Right and Left advancing': (
        'ecd_set',
        {
          'who': ['partners'],
          'direction': 'right',
          'where': 'forward',
        },
        null,
      ),
      'First Corner Set R & L': (
        'ecd_set',
        {
          'who': ['firstCorners'],
          'direction': 'right',
        },
        null,
      ),
      'Second Corner Set L & R': (
        'ecd_set',
        {
          'who': ['secondCorners'],
          'direction': 'left',
        },
        null,
      ),
      // A turn single holds no direction of travel: `forward` is the note.
      'Turn single right forward': (
        'ecd_turn_single',
        {'shoulder': 'right'},
        'forward',
      ),
      'Lines of three go forward and back': (
        'ecd_forward_and_back',
        {'formation': 'linesOfThree', 'distance': 'double', 'goBack': true},
        null,
      ),
      // A couple's partner is the couple's own two dancers.
      'Ones Partner Set': (
        'ecd_set',
        {
          'who': ['ones'],
        },
        null,
      ),
      'Ones Partner right-hand turn 1.5': (
        'ecd_hand_turn',
        {
          'who': ['ones'],
          'hand': 'right',
          'travel': 1.5,
        },
        null,
      ),
      // Who follows a cast has no parameter: the words are the note.
      'Second corners cast partner follow': (
        'ecd_cast',
        {
          'who': ['secondCorners'],
        },
        'partner follow',
      ),
    };
    for (final MapEntry(key: line, value: (move, params, note))
        in cases.entries) {
      test(line, () {
        for (final figure in [
          _one(line),
          parseEcdFigureLine(line, ringDancers: 4)!,
        ]) {
          expect(figure.move, move, reason: line);
          expect(figure.params, params, reason: line);
          expect(figure.note, note, reason: line);
          expect(_ecd.validateFigure(figure), isEmpty, reason: line);
        }
      });
    }

    test('`cross and go below` is a trade by the right, then a cast down one '
        'place', () {
      for (final line in const [
        'Ones cross and go below',
        '1s cross & go below',
        'Ones cross over and go below',
        'Ones cross and go outside below',
        'Ones cross and go outside below the twos who move up',
        'Ones cross by Right and go outside below the twos who move up',
        'Ones cross over and go below the Twos 2 moving up',
      ]) {
        final f = _one(line);
        expect(f.isSequence, isTrue, reason: line);
        expect(f.subFigures.map((s) => [s.move, s.params]), [
          [
            'ecd_change_places',
            {
              'who': ['ones'],
              'hand': 'right',
            },
          ],
          [
            'ecd_cast',
            {
              'who': ['ones'],
              'direction': 'down',
              'places': 1,
            },
          ],
        ], reason: line);
      }
    });

    test('the twos moving up after `go below` is the note', () {
      expect(
        _one('Ones cross and go outside below the twos who move up').note,
        'outside below the twos who move up',
      );
      expect(
        _one('Ones cross over and go below the Twos 2 moving up').note,
        'below the Twos 2 moving up',
      );
      expect(
        _one('Ones cross by left and go below').subFigures.first.params['hand'],
        'left',
      );
    });

    test('a side an aside names is the trade\'s side; a cross stating more '
        'stays a cross', () {
      for (final (line, hand) in const [
        ('Ones (take left hands) cross and go below', 'left'),
        ('Ones cross (passing left) and go below', 'left'),
        ('Ones (take right hands) cross and go below', 'right'),
      ]) {
        final first = _one(line).subFigures.first;
        expect(first.move, 'ecd_change_places', reason: line);
        expect(first.params['hand'], hand, reason: line);
      }
      for (final line in const [
        'Ones cross diagonally and go below',
        'Ones cross facing up and go below',
        'Ones cross by right (passing left) and go below',
        'Ones (take left hands, then right) cross and go below',
      ]) {
        expect(_one(line).subFigures.first.move, 'ecd_cross', reason: line);
      }
    });

    test('`go below` words already in an aside are left as they are', () {
      for (final line in const [
        'Ones cross and cast (go outside below)',
        'Ones cross and cast (go below the twos who move up)',
      ]) {
        final f = parseEcdFigureLine(line, beats: 8);
        expect(f?.isCustom, isFalse, reason: line);
      }
    });

    test('a couple passing its own partner by a side trades places', () {
      for (final (line, who, hand) in const [
        ('Ones pass P by R', 'ones', 'right'),
        ('Twos pass partner by left', 'twos', 'left'),
      ]) {
        final f = _one(line);
        expect(f.move, 'ecd_change_places', reason: line);
        expect(f.params, {
          'who': [who],
          'hand': hand,
        }, reason: line);
      }
      // With no couple, a pass of partners is still a pass through.
      expect(_one('Pass P by R').move, 'ecd_pass_through');
    });

    test('`turn single … face P` ends facing them, as its note', () {
      for (final (line, shoulder, note) in const [
        ('Turn single right face P', 'right', 'end facing partners'),
        ('Turn single left face N', 'left', 'end facing neighbors'),
        (
          'Turn single right forward face P',
          'right',
          'forward; end facing partners',
        ),
      ]) {
        final f = _one(line);
        expect(f.move, 'ecd_turn_single', reason: line);
        expect(f.params['shoulder'], shoulder, reason: line);
        expect(f.note, note, reason: line);
      }
      // A move with its own end facing still reads a direction.
      expect(_one('Partners cross face up').params['endFacing'], 'up');
    });

    test('`(PR, NL, …)` names who a rights and lefts or a circular hey starts '
        'with and its first side', () {
      for (final (line, move, side, whom, value) in const [
        (
          '4 changes of Rights & Lefts (PR, NL, PR, NL)',
          'ecd_rights_and_lefts',
          'hand',
          'partners',
          'right',
        ),
        (
          '2 changes of Lefts & Rights (PL, NR)',
          'ecd_rights_and_lefts',
          'hand',
          'partners',
          'left',
        ),
        (
          '3 changes of a Circular Hey (PR,NL,PR)',
          'ecd_circular_hey',
          'shoulder',
          'partners',
          'right',
        ),
        (
          '2 changes of rights and lefts (NL, PR)',
          'ecd_rights_and_lefts',
          'hand',
          'neighbors',
          'left',
        ),
      ]) {
        final f = _one(line);
        expect(f.move, move, reason: line);
        expect(f.params['whom'], whom, reason: line);
        expect(f.params[side], value, reason: line);
        expect(f.note, isNull, reason: line);
      }
      // Beside another aside, or written with semicolons, they still read,
      // and the other aside stays the note.
      final beside = _one('2 changes of Lefts & Rights (PL, NR) (quickly)');
      expect(beside.params['whom'], 'partners');
      expect(beside.params['hand'], 'left');
      expect(beside.note, 'quickly');
      expect(
        _one('2 changes of rights and lefts (PR;NL)').params['whom'],
        'partners',
      );
      final spaced = _one('4 changes of rights and lefts (PR; NL; PR; NL)');
      expect(spaced.params['whom'], 'partners');
      expect(spaced.params['hand'], 'right');
      expect(spaced.note, isNull);
      // Passes that do not alternate, number other than the changes, or are
      // only one pass, stay as written.
      for (final line in const [
        '2 changes of Rights & Lefts (PR, NL,NR hold on)',
        '4 changes of Rights & Lefts (PR, NL)',
        '2 changes of Rights & Lefts (PR, PL)',
        'Rights and lefts (PR)',
      ]) {
        final f = _one(line);
        expect(f.params.containsKey('whom'), isFalse, reason: line);
        expect(f.note, isNotNull, reason: line);
      }
    });

    test('`pass <side> shoulder` before other words and a movement is still '
        'its shoulder', () {
      final hey = _one('1s pass right shoulder half hey for three');
      expect(hey.move, 'ecd_hey_for_three');
      expect(hey.params, {
        'who': ['ones'],
        'shoulder': 'right',
        'fraction': 'half',
      });
      final circular = _one('pass left shoulder 3 changes circular hey');
      expect(circular.move, 'ecd_circular_hey');
      expect(circular.params, {'changes': 3, 'shoulder': 'left'});
    });

    test('`go below` is a cast only after a cross', () {
      for (final line in const [
        '1s cast and go below',
        '1s lead down and go below',
        'half figure eight and go below',
        'go below',
      ]) {
        final f = parseEcdFigureLine(line, beats: 8);
        expect(f?.isCustom, isTrue, reason: line);
      }
    });

    test('a hand and a shoulder that disagree in a change of places are not '
        'read', () {
      final f = parseEcdFigureLine(
        'change places right hand passing left shoulder',
        beats: 8,
      );
      expect(f?.isCustom, isTrue);
    });

    test('a shoulder after other movements reads as their shoulder', () {
      for (final (line, move) in const [
        ('partners cross by the right shoulder', 'ecd_cross'),
        ('1st corners pass by the right shoulder', 'ecd_pass_through'),
      ]) {
        final f = _one(line);
        expect(f.move, move, reason: line);
        expect(f.params['shoulder'], 'right', reason: line);
      }
    });

    test('a couple\'s partner joined to other dancers is not absorbed', () {
      final f = parseEcdFigureLine('Ones partner and twos set', beats: 8);
      expect(f?.isCustom, isTrue);
    });

    test('an imported bar range is the count of a trade', () {
      final f = parseEcdFigureLine(
        '(7-8) Second corners trade by right',
        meter: '2/2',
      )!;
      expect(f.move, 'ecd_change_places');
      expect(f.params, {
        'who': ['secondCorners'],
        'hand': 'right',
        'beats': 4,
      });
    });

    test('`pass right shoulder` before a movement is still its shoulder', () {
      final f = _one('1s pass right shoulder cross');
      expect(f.move, 'ecd_cross');
      expect(f.params, {
        'who': ['ones'],
        'shoulder': 'right',
      });
    });

    test('words these readings could guess at stay custom', () {
      for (final line in const [
        // A pass by a hand is a pull by, not a pass through.
        'Pass P by the right hand',
        // Ones and their neighbors: only a couple's own partner is a trade.
        'Ones pass N by R',
        // A couple's neighbour is other dancers: not the couple's own.
        'Ones Neighbor Set',
        // Who follows a movement other than a cast has nowhere to go.
        'Ones lead down partner follow',
        // What the twos do that is not moving up: two figures.
        'Ones cross and go outside below the twos while the twos WAIT',
        // The passes after a colon rather than in brackets.
        '3 changes of a circular hey: pass PR, NL, PR',
      ]) {
        expect(_typed(line).single.isCustom, isTrue, reason: line);
      }
    });
  });
}
