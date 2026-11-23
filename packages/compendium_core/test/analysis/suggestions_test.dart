import 'dart:isolate';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// The scorer behind the program builder's Suggested sort (#2343).
///
/// Each factor's test puts the candidate the factor should lower FIRST in the
/// plain order, so that a scorer with that factor zeroed (every candidate
/// tied, ties keeping the plain order) fails it.
void main() {
  final stamp = DateTime.utc(2026, 1, 1);
  // A fixed calendar day: no test reads the real clock.
  final today = DateTime.utc(2026, 11, 23);

  Figure fig(
    String move,
    int beats, [
    Map<String, Object?> params = const {},
  ]) => testFigure(move: move, params: {...params, 'beats': beats});

  Dance dance(
    String id,
    List<Figure> figures, {
    DanceForm form = DanceForm.contra,
    FormationShape shape = FormationShape.dupleImproper,
    String? level,
  }) => Dance(
    id: id,
    title: id,
    form: form,
    formation: Formation(shape),
    figures: figures,
    difficultyLevelId: level,
    createdAt: stamp,
    updatedAt: stamp,
  );

  List<ProgramSlot> slotsFor(List<Dance> dances) => [
    for (var i = 0; i < dances.length; i++)
      ProgramSlot(id: 's$i', position: i, danceId: dances[i].id),
  ];

  /// Only [factor] on, at A lot.
  SuggestionSettings only(SuggestionFactor factor) {
    var settings = SuggestionSettings.defaults;
    for (final f in SuggestionFactor.values) {
      settings = settings.withWeight(
        f,
        f == factor ? SuggestionWeight.aLot : SuggestionWeight.off,
      );
    }
    return settings;
  }

  SuggestionRanking rank({
    List<Dance> program = const [],
    List<ProgramSlot>? slots,
    required List<Dance> candidates,
    SuggestionSettings settings = SuggestionSettings.defaults,
    MatrixCollisionMode mode = MatrixCollisionMode.exactBeats,
    bool hasVenue = false,
    Map<String, DateTime?> calledHere = const {},
    List<DifficultyLevel> levels = const [],
  }) => rankSuggestions(
    SuggestionRequest(
      slotsBefore: slots ?? slotsFor(program),
      programDances: {
        for (final d in program) d.id: SuggestionCandidate.fromDance(d),
      },
      candidates: [
        for (final d in candidates) SuggestionCandidate.fromDance(d),
      ],
      settings: settings,
      today: today,
      collisionMode: mode,
      hasVenue: hasVenue,
      calledHere: calledHere,
      levels: levels,
    ),
  );

  List<String> order(SuggestionRanking r) => [
    for (final s in r.order) s.danceId,
  ];
  RankedSuggestion of(SuggestionRanking r, String id) =>
      r.order.singleWhere((s) => s.danceId == id);
  Set<SuggestionReasonKind> kinds(RankedSuggestion s) => {
    for (final r in s.reasons) r.kind,
  };

  group('variety on the matrix', () {
    // The previous dance: a circle in A1 and a partner swing in A2 (beats
    // 16-32).
    final previous = dance('prev', [fig('circle', 16), fig('swing', 16)]);

    test('a candidate whose swing overlaps the previous dance\'s beats ranks '
        'below a clean one', () {
      // Both add do_si_do, the one move new to the program, so only the
      // overlap differs.
      final overlapping = dance('overlap', [
        fig('do_si_do', 16),
        fig('swing', 16),
      ]);
      final clean = dance('clean', [fig('swing', 16), fig('do_si_do', 16)]);
      final r = rank(
        program: [previous],
        candidates: [overlapping, clean],
        settings: only(SuggestionFactor.matrixVariety),
      );
      expect(order(r), ['clean', 'overlap']);
      final reason = of(
        r,
        'overlap',
      ).reasons.firstWhere((x) => x.kind == SuggestionReasonKind.beatOverlap);
      expect(reason.moveKey, 'swing:partner');
      expect(reason.neighbor, SuggestionNeighbor.previous);
      expect(reason.effect, isNegative);
      expect(of(r, 'overlap').headline.first.kind, isNot(isNull));
    });

    test('a candidate that brings new moves ranks above one that does not', () {
      // Neither overlaps the previous dance's beats.
      final familiar = dance('familiar', [fig('swing', 16), fig('circle', 16)]);
      final fresh = dance('fresh', [fig('swing', 16), fig('petronella', 16)]);
      final r = rank(
        program: [previous],
        candidates: [familiar, fresh],
        settings: only(SuggestionFactor.matrixVariety),
      );
      expect(order(r), ['fresh', 'familiar']);
      final reason = of(
        r,
        'fresh',
      ).reasons.singleWhere((x) => x.kind == SuggestionReasonKind.newMoves);
      expect(reason.count, 1);
    });

    test('follows the "Flag exact beat overlap only" setting', () {
      // The previous dance swings on beats 16-24; this one on 24-32. Exact
      // beats do not overlap, but both start in A2.
      final before = dance('before', [fig('circle', 16), fig('swing', 8)]);
      final samePhrase = dance('same-phrase', [
        fig('do_si_do', 24),
        fig('swing', 8),
      ]);
      final elsewhere = dance('elsewhere', [
        fig('swing', 8),
        fig('do_si_do', 24),
      ]);
      final exact = rank(
        program: [before],
        candidates: [samePhrase, elsewhere],
        settings: only(SuggestionFactor.matrixVariety),
      );
      expect(
        kinds(of(exact, 'same-phrase')),
        isNot(contains(SuggestionReasonKind.beatOverlap)),
      );
      final phrase = rank(
        program: [before],
        candidates: [samePhrase, elsewhere],
        settings: only(SuggestionFactor.matrixVariety),
        mode: MatrixCollisionMode.phrase,
      );
      expect(order(phrase), ['elsewhere', 'same-phrase']);
      // Said as a phrase, not beats, under the phrase rule.
      expect(
        kinds(of(phrase, 'same-phrase')),
        allOf(
          contains(SuggestionReasonKind.phraseOverlap),
          isNot(contains(SuggestionReasonKind.beatOverlap)),
        ),
      );
    });

    test('an exact beat overlap is said as beats, and as a phrase under the '
        'phrase rule', () {
      final overlapping = dance('overlap', [
        fig('do_si_do', 16),
        fig('swing', 16),
      ]);
      for (final (mode, kind, other) in [
        (
          MatrixCollisionMode.exactBeats,
          SuggestionReasonKind.beatOverlap,
          SuggestionReasonKind.phraseOverlap,
        ),
        (
          MatrixCollisionMode.phrase,
          SuggestionReasonKind.phraseOverlap,
          SuggestionReasonKind.beatOverlap,
        ),
      ]) {
        final r = rank(
          program: [previous],
          candidates: [overlapping],
          settings: only(SuggestionFactor.matrixVariety),
          mode: mode,
        );
        final reasons = kinds(of(r, 'overlap'));
        expect(reasons, contains(kind), reason: mode.name);
        expect(reasons, isNot(contains(other)), reason: mode.name);
      }
    });

    test('a break separates the candidate from the dance before it, as in '
        'the matrix', () {
      final overlapping = dance('overlap', [
        fig('do_si_do', 16),
        fig('swing', 16),
      ]);
      final r = rank(
        program: [previous],
        slots: [
          ProgramSlot(id: 's0', position: 0, danceId: 'prev'),
          ProgramSlot(id: 's1', position: 1, text: 'Break'),
        ],
        candidates: [overlapping],
        settings: only(SuggestionFactor.matrixVariety),
      );
      expect(
        kinds(of(r, 'overlap')),
        isNot(contains(SuggestionReasonKind.beatOverlap)),
      );
    });

    test('Off removes it from scores and reasons', () {
      final overlapping = dance('overlap', [
        fig('do_si_do', 16),
        fig('swing', 16),
      ]);
      final clean = dance('clean', [fig('swing', 16), fig('do_si_do', 16)]);
      final r = rank(
        program: [previous],
        candidates: [overlapping, clean],
        settings: SuggestionSettings.defaults.withWeight(
          SuggestionFactor.matrixVariety,
          SuggestionWeight.off,
        ),
      );
      for (final s in r.order) {
        expect(
          s.reasons.where((x) => x.factor == SuggestionFactor.matrixVariety),
          isEmpty,
        );
      }
      expect(of(r, 'overlap').score, of(r, 'clean').score);
    });
  });

  group('formation balance', () {
    test('a candidate in the previous dance\'s formation ranks below one in '
        'another', () {
      final previous = dance('prev', [
        fig('circle', 16),
      ], shape: FormationShape.becketCw);
      final becket = dance('becket', [
        fig('circle', 16),
      ], shape: FormationShape.becketCcw);
      final improper = dance('improper', [fig('circle', 16)]);
      final r = rank(
        program: [previous],
        candidates: [becket, improper],
        settings: only(SuggestionFactor.formationBalance),
      );
      expect(order(r), ['improper', 'becket']);
      expect(
        kinds(of(r, 'becket')),
        contains(SuggestionReasonKind.sameFormationAsNeighbor),
      );
      expect(
        kinds(of(r, 'improper')),
        contains(SuggestionReasonKind.firstFormationTonight),
      );
    });

    test('a formation the program already has many of ranks below a new '
        'one', () {
      final program = [
        dance('a', [fig('circle', 16)]),
        dance('b', [fig('circle', 16)]),
        dance('c', [fig('circle', 16)]),
        dance('d', [fig('circle', 16)], shape: FormationShape.triplet),
      ];
      final improper = dance('improper', [fig('circle', 16)]);
      final becket = dance('becket', [
        fig('circle', 16),
      ], shape: FormationShape.becketCw);
      final r = rank(
        program: program,
        candidates: [improper, becket],
        settings: only(SuggestionFactor.formationBalance),
      );
      expect(order(r), ['becket', 'improper']);
      final common = of(r, 'improper').reasons.singleWhere(
        (x) => x.kind == SuggestionReasonKind.formationCommonTonight,
      );
      expect(common.count, 3);
    });
  });

  group('difficulty curve', () {
    final levels = DifficultyLevel.shipped;
    test('build up, then ease off: the first dance of the evening prefers '
        'the easiest level', () {
      final hard = dance('hard', const [], level: DifficultyLevel.advancedId);
      final easy = dance('easy', const [], level: DifficultyLevel.beginnerId);
      final r = rank(
        candidates: [hard, easy],
        settings: only(SuggestionFactor.difficultyCurve),
        levels: levels,
      );
      expect(order(r), ['easy', 'hard']);
      expect(kinds(of(r, 'easy')), contains(SuggestionReasonKind.fitsCurve));
      expect(
        kinds(of(r, 'hard')),
        contains(SuggestionReasonKind.harderThanCurve),
      );
    });

    test('build up, then ease off: two thirds in, it prefers the hardest', () {
      final program = [
        for (var i = 0; i < 8; i++)
          dance('p$i', const [], level: DifficultyLevel.intermediateId),
      ];
      final easy = dance('easy', const [], level: DifficultyLevel.beginnerId);
      final hard = dance('hard', const [], level: DifficultyLevel.advancedId);
      final r = rank(
        program: program,
        candidates: [easy, hard],
        settings: only(SuggestionFactor.difficultyCurve),
        levels: levels,
      );
      expect(order(r), ['hard', 'easy']);
      expect(
        kinds(of(r, 'easy')),
        contains(SuggestionReasonKind.easierThanCurve),
      );
    });

    test('even: prefers the level of the dances so far', () {
      final program = [
        dance('p0', const [], level: DifficultyLevel.intermediateId),
        dance('p1', const [], level: DifficultyLevel.intermediateId),
      ];
      final hard = dance('hard', const [], level: DifficultyLevel.advancedId);
      final middle = dance(
        'middle',
        const [],
        level: DifficultyLevel.intermediateId,
      );
      final r = rank(
        program: program,
        candidates: [hard, middle],
        settings: only(
          SuggestionFactor.difficultyCurve,
        ).copyWith(curveShape: DifficultyCurveShape.even),
        levels: levels,
      );
      expect(order(r), ['middle', 'hard']);
    });

    test('the Off shape removes it, whatever the weight', () {
      final hard = dance('hard', const [], level: DifficultyLevel.advancedId);
      final easy = dance('easy', const [], level: DifficultyLevel.beginnerId);
      final r = rank(
        candidates: [hard, easy],
        settings: only(
          SuggestionFactor.difficultyCurve,
        ).copyWith(curveShape: DifficultyCurveShape.off),
        levels: levels,
      );
      expect(order(r), ['hard', 'easy']);
      expect(of(r, 'hard').reasons.where((x) => x.moved), isEmpty);
    });
  });

  group('recent calls at this venue', () {
    test('a dance called here last week ranks below one never called here', () {
      final calledLastWeek = dance('last-week', const []);
      final never = dance('never', const []);
      final r = rank(
        candidates: [calledLastWeek, never],
        settings: only(SuggestionFactor.venueRecency),
        hasVenue: true,
        calledHere: {'last-week': DateTime.utc(2026, 11, 16)},
      );
      expect(order(r), ['never', 'last-week']);
      final recent = of(r, 'last-week').reasons.single;
      expect(recent.kind, SuggestionReasonKind.calledHereRecently);
      expect(recent.date, DateTime.utc(2026, 11, 16));
      expect(
        of(r, 'never').reasons.single.kind,
        SuggestionReasonKind.neverCalledHere,
      );
    });

    test('the window counts calendar months back from the injected day', () {
      // Two months ago: inside 3 months, outside 1 month.
      final candidate = dance('two-months', const []);
      final calledHere = {'two-months': DateTime.utc(2026, 9, 23)};
      final three = rank(
        candidates: [candidate],
        settings: only(SuggestionFactor.venueRecency),
        hasVenue: true,
        calledHere: calledHere,
      );
      expect(
        of(three, 'two-months').reasons.single.kind,
        SuggestionReasonKind.calledHereRecently,
      );
      final one = rank(
        candidates: [candidate],
        settings: only(
          SuggestionFactor.venueRecency,
        ).copyWith(venueWindow: VenueRecencyWindow.oneMonth),
        hasVenue: true,
        calledHere: calledHere,
      );
      final since = of(one, 'two-months').reasons.single;
      expect(since.kind, SuggestionReasonKind.notCalledHereSince);
      expect(since.effect, isPositive);
      // The cutoff day itself is inside the window.
      final onCutoff = rank(
        candidates: [candidate],
        settings: only(
          SuggestionFactor.venueRecency,
        ).copyWith(venueWindow: VenueRecencyWindow.oneMonth),
        hasVenue: true,
        calledHere: {'two-months': DateTime.utc(2026, 10, 23)},
      );
      expect(
        of(onCutoff, 'two-months').reasons.single.kind,
        SuggestionReasonKind.calledHereRecently,
      );
    });

    test('a call with no date counts as called but in no window', () {
      final r = rank(
        candidates: [dance('undated', const [])],
        settings: only(SuggestionFactor.venueRecency),
        hasVenue: true,
        calledHere: {'undated': null},
      );
      expect(
        of(r, 'undated').reasons.single.kind,
        SuggestionReasonKind.noFactorApplied,
      );
    });

    test('with no venue it is skipped, and the reasons say so', () {
      final calledLastWeek = dance('last-week', const []);
      final never = dance('never', const []);
      final r = rank(
        candidates: [calledLastWeek, never],
        settings: only(SuggestionFactor.venueRecency),
        calledHere: {'last-week': DateTime.utc(2026, 11, 16)},
      );
      expect(order(r), ['last-week', 'never']);
      for (final s in r.order) {
        expect(s.score, 0);
        expect(kinds(s), contains(SuggestionReasonKind.venueSkippedNoVenue));
      }
    });
  });

  group('English and square dances', () {
    test('English candidates come after the ranked ones, unranked, with the '
        '"don\'t cover English dances yet" reason', () {
      final english = dance('english', const [], form: DanceForm.ecd);
      final english2 = dance('english2', const [], form: DanceForm.ecd);
      final contra = dance('contra', const []);
      final square = dance('square', const [], form: DanceForm.square);
      final r = rank(candidates: [english, contra, english2, square]);
      expect(order(r), ['contra', 'square', 'english', 'english2']);
      for (final id in ['english', 'english2']) {
        expect(of(r, id).ranked, isFalse);
        expect(
          of(r, id).headline.single.kind,
          SuggestionReasonKind.englishNotCovered,
        );
      }
      expect(of(r, 'square').ranked, isTrue);
    });
  });

  group('every candidate', () {
    test('comes back once: ranking only reorders', () {
      final candidates = [
        for (var i = 0; i < 20; i++)
          dance('d$i', [
            fig(i.isEven ? 'swing' : 'circle', 16),
          ], form: i % 5 == 0 ? DanceForm.ecd : DanceForm.contra),
      ];
      final r = rank(
        program: [
          dance('prev', [fig('swing', 16)]),
        ],
        candidates: candidates,
        hasVenue: true,
      );
      expect(order(r).toSet(), {for (final d in candidates) d.id});
      expect(order(r), hasLength(candidates.length));
    });

    test('has at least one reason, even with every factor off', () {
      var settings = SuggestionSettings.defaults;
      for (final f in SuggestionFactor.values) {
        settings = settings.withWeight(f, SuggestionWeight.off);
      }
      final r = rank(
        program: [
          dance('prev', [fig('swing', 16)]),
        ],
        candidates: [
          dance('a', [fig('swing', 16)]),
        ],
        settings: settings,
      );
      expect(
        of(r, 'a').headline.single.kind,
        SuggestionReasonKind.noFactorApplied,
      );
    });

    test('lists reasons largest effect first, and the headline is the top '
        'two that moved it', () {
      final previous = dance('prev', [fig('circle', 16), fig('swing', 16)]);
      final candidate = dance('c', [
        fig('do_si_do', 16),
        fig('swing', 16),
      ], shape: FormationShape.becketCw);
      final r = rank(
        program: [previous],
        candidates: [candidate],
        hasVenue: true,
        calledHere: {'c': DateTime.utc(2026, 11, 1)},
      );
      final reasons = of(r, 'c').reasons.where((x) => x.moved).toList();
      expect(reasons.length, greaterThan(2));
      for (var i = 1; i < reasons.length; i++) {
        expect(
          reasons[i - 1].effect.abs(),
          greaterThanOrEqualTo(reasons[i].effect.abs()),
        );
      }
      expect(of(r, 'c').headline, reasons.take(2).toList());
    });
  });

  group('a dance already in the program', () {
    final inProgram = dance('in', [fig('petronella', 16)]);
    final other = dance('other', [fig('circle', 16), fig('swing', 16)]);

    test('sinks below every other dance, says why, and is never called "never '
        'called here"', () {
      // Without the check, "in" wins: it reads as never called here (the
      // venue history leaves this program out), and "other" was called here
      // last week.
      final r = rank(
        program: [dance('first', const []), inProgram],
        candidates: [inProgram, other],
        hasVenue: true,
        calledHere: {'other': DateTime.utc(2026, 11, 16)},
      );
      expect(order(r), ['other', 'in']);
      final ranked = of(r, 'in');
      expect(ranked.ranked, isFalse, reason: 'listed last, unscored');
      expect(ranked.headline.first.kind, SuggestionReasonKind.alreadyInProgram);
      expect(ranked.score, lessThan(of(r, 'other').score));
      expect(
        kinds(ranked),
        isNot(contains(SuggestionReasonKind.neverCalledHere)),
      );
      expect(
        kinds(of(r, 'other')),
        isNot(contains(SuggestionReasonKind.alreadyInProgram)),
      );
    });

    test('with every factor off it is still below the others', () {
      var settings = SuggestionSettings.defaults;
      for (final f in SuggestionFactor.values) {
        settings = settings.withWeight(f, SuggestionWeight.off);
      }
      final r = rank(
        program: [inProgram],
        candidates: [inProgram, other],
        settings: settings,
      );
      expect(order(r), ['other', 'in']);
    });

    test('comes after the English dances too, and an English one already in '
        'the program says so', () {
      final english = dance('english', const [], form: DanceForm.ecd);
      final englishIn = dance('english-in', const [], form: DanceForm.ecd);
      final r = rank(
        program: [inProgram, englishIn],
        // Plain order: the in-program dances first.
        candidates: [englishIn, inProgram, english, other],
      );
      // Ranked, then English not in the program, then every dance in the
      // program in the plain order.
      expect(order(r), ['other', 'english', 'english-in', 'in']);
      for (final id in ['english-in', 'in']) {
        expect(of(r, id).reasons.map((x) => x.kind), [
          SuggestionReasonKind.alreadyInProgram,
        ], reason: id);
        expect(of(r, id).ranked, isFalse);
      }
      expect(kinds(of(r, 'english')), {SuggestionReasonKind.englishNotCovered});
    });
  });

  test('a candidate carries only what the scorer reads', () {
    final full = Dance(
      id: 'd',
      title: 'Title',
      hook: 'A hook',
      callingNotes: 'Notes',
      form: DanceForm.square,
      formation: const Formation(FormationShape.becketCw),
      difficultyLevelId: 'intermediate',
      figures: [fig('swing', 16)],
      createdAt: stamp,
      updatedAt: stamp,
    );
    final c = SuggestionCandidate.fromDance(full);
    expect(c.id, 'd');
    expect(c.form, DanceForm.square);
    expect(c.formation.shape, FormationShape.becketCw);
    expect(c.difficultyLevelId, 'intermediate');
    expect(c.figures.single.move, 'swing');
  });

  test('a candidate\'s revision changes with what the scorer reads, even '
      'when updatedAt does not', () {
    final before = dance('d', [fig('swing', 16), fig('circle', 16)]);
    final same = before;
    // Edited by a path that stamps the same second.
    final edited = dance('d', [fig('circle', 16), fig('swing', 16)]);
    final relevelled = dance('d', [
      fig('swing', 16),
      fig('circle', 16),
    ], level: 'advanced');
    int revision(Dance d) => SuggestionCandidate.fromDance(d).revision;
    expect(before.updatedAt, edited.updatedAt);
    expect(revision(same), revision(before));
    expect(revision(edited), isNot(revision(before)));
    expect(revision(relevelled), isNot(revision(before)));
  });

  test('the request can be sent to another isolate', () async {
    final request = SuggestionRequest(
      slotsBefore: [ProgramSlot(id: 's', position: 0, danceId: 'p')],
      programDances: {
        'p': SuggestionCandidate.fromDance(dance('p', [fig('swing', 16)])),
      },
      candidates: [
        SuggestionCandidate.fromDance(dance('c', [fig('swing', 16)])),
      ],
      settings: SuggestionSettings.defaults,
      today: today,
      taxonomy: shippedTaxonomies.anyForm,
      levels: DifficultyLevel.shipped,
    );
    // What the app does with the picker's results.
    final ids = await Isolate.run(() => rankSuggestions(request));
    expect([for (final s in ids.order) s.danceId], ['c']);
  });
}
