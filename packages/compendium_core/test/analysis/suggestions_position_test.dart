import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// Suggestions for a point inside the program (#2344): an add before or after
/// a slot, and **Replace…**. The end of the program is pinned by
/// suggestions_end_regression_test.dart.
///
/// As in suggestions_test.dart, each ranking test puts the candidate that
/// should sink FIRST in the plain order, so a scorer that misses the
/// comparison (every candidate tied) fails it.
void main() {
  final stamp = DateTime.utc(2026, 1, 1);
  // A fixed calendar day: no test reads the real clock.
  final today = DateTime.utc(2026, 11, 23);

  Figure fig(String move, int beats) =>
      testFigure(move: move, params: {'beats': beats});

  Dance dance(
    String id,
    List<Figure> figures, {
    FormationShape shape = FormationShape.dupleImproper,
    String? level,
  }) => Dance(
    id: id,
    title: id,
    formation: Formation(shape),
    figures: figures,
    difficultyLevelId: level,
    createdAt: stamp,
    updatedAt: stamp,
  );

  ProgramSlot slot(String danceId, {bool alt = false}) =>
      ProgramSlot(id: 's-$danceId', position: 0, danceId: danceId, isAlt: alt);
  ProgramSlot note(String text) =>
      ProgramSlot(id: 'n-$text', position: 0, text: text);

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
    required List<Dance> program,
    required SuggestionPosition position,
    required List<Dance> candidates,
    required SuggestionSettings settings,
    MatrixCollisionMode mode = MatrixCollisionMode.exactBeats,
  }) => rankSuggestions(
    SuggestionRequest(
      slotsBefore: position.slotsBefore,
      slotsAfter: position.slotsAfter,
      candidateIsAlternate: position.isAlternate,
      programDances: {
        for (final d in program) d.id: SuggestionCandidate.fromDance(d),
      },
      candidates: [
        for (final d in candidates) SuggestionCandidate.fromDance(d),
      ],
      settings: settings,
      today: today,
      collisionMode: mode,
      taxonomy: shippedTaxonomies.anyForm,
      levels: DifficultyLevel.shipped,
    ),
  );

  List<String> order(SuggestionRanking r) => [
    for (final s in r.order) s.danceId,
  ];
  RankedSuggestion of(SuggestionRanking r, String id) =>
      r.order.singleWhere((s) => s.danceId == id);
  SuggestionReason? overlapOf(SuggestionRanking r, String id) => of(r, id)
      .reasons
      .where(
        (x) =>
            x.kind == SuggestionReasonKind.beatOverlap ||
            x.kind == SuggestionReasonKind.phraseOverlap,
      )
      .firstOrNull;

  // A: a circle, then a do-si-do on beats 16-32. No swing.
  final a = dance('A', [fig('circle', 16), fig('do_si_do', 16)]);
  // B: a circle, then a partner swing on beats 16-32.
  final b = dance('B', [fig('circle', 16), fig('swing', 16)]);
  // Both bring petronella, new to the program; only the swing's beats differ.
  final overlapsB = dance('overlaps-B', [
    fig('petronella', 16),
    fig('swing', 16),
  ]);
  final clean = dance('clean', [fig('swing', 16), fig('petronella', 16)]);

  group('adding before a slot', () {
    test('ranks against the dance after it too: a candidate whose beats '
        'overlap the following dance ranks below a clean one', () {
      final slots = [slot('A'), slot('B')];
      final r = rank(
        program: [a, b],
        position: SuggestionPosition.inserting(slots, 1, after: false),
        candidates: [overlapsB, clean],
        settings: only(SuggestionFactor.matrixVariety),
      );
      expect(order(r), ['clean', 'overlaps-B']);
      final reason = overlapOf(r, 'overlaps-B')!;
      expect(reason.kind, SuggestionReasonKind.beatOverlap);
      expect(reason.neighbor, SuggestionNeighbor.next);
      expect(reason.neighborDanceId, 'B');
      expect(overlapOf(r, 'clean'), isNull);
    });

    test('a break between the position and the next dance removes it from '
        'the comparison; a note does not', () {
      for (final (between, separates) in [
        (note(Program.breakSlotText), true),
        (note('Waltz'), false),
      ]) {
        final r = rank(
          program: [a, b],
          position: SuggestionPosition(
            slotsBefore: [slot('A')],
            slotsAfter: [between, slot('B')],
          ),
          candidates: [overlapsB, clean],
          settings: only(SuggestionFactor.matrixVariety),
        );
        expect(
          overlapOf(r, 'overlaps-B'),
          separates ? isNull : isNotNull,
          reason: between.text,
        );
      }
    });

    test('a break between the dance before and the position removes it; a '
        'note does not', () {
      // B before, A after: the overlap is with the dance before.
      for (final (between, separates) in [
        (note(Program.breakSlotText), true),
        (note('Waltz'), false),
      ]) {
        final r = rank(
          program: [a, b],
          position: SuggestionPosition(
            slotsBefore: [slot('B'), between],
            slotsAfter: [slot('A')],
          ),
          candidates: [overlapsB, clean],
          settings: only(SuggestionFactor.matrixVariety),
        );
        final reason = overlapOf(r, 'overlaps-B');
        expect(reason, separates ? isNull : isNotNull, reason: between.text);
        if (!separates) {
          expect(reason!.neighbor, SuggestionNeighbor.previous);
          expect(reason.neighborDanceId, 'B');
        }
      }
    });

    test("compares a neighbouring group's alternates as well as its "
        'primary, on either side', () {
      // B is now an alternate of A: either may be danced next to the
      // candidate.
      for (final (position, side) in [
        (
          SuggestionPosition.inserting(
            [slot('A'), slot('B', alt: true)],
            0,
            after: false,
          ),
          SuggestionNeighbor.next,
        ),
        (
          SuggestionPosition.inserting(
            [slot('A'), slot('B', alt: true)],
            0,
            after: true,
          ),
          SuggestionNeighbor.previous,
        ),
      ]) {
        final r = rank(
          program: [a, b],
          position: position,
          candidates: [overlapsB, clean],
          settings: only(SuggestionFactor.matrixVariety),
        );
        expect(order(r), ['clean', 'overlaps-B'], reason: side.name);
        final reason = overlapOf(r, 'overlaps-B')!;
        expect(reason.neighbor, side);
        expect(reason.neighborDanceId, 'B');
      }
    });

    test('names the neighbour the beats really collide with, not the first '
        'one that has the move', () {
      // Before: a swing on beats 0-16, which the candidate does not touch.
      final early = dance('early', [fig('swing', 16), fig('circle', 16)]);
      final r = rank(
        program: [early, b],
        position: SuggestionPosition(
          slotsBefore: [slot('early')],
          slotsAfter: [slot('B')],
        ),
        candidates: [overlapsB],
        settings: only(SuggestionFactor.matrixVariety),
      );
      final reason = overlapOf(r, 'overlaps-B')!;
      expect(reason.neighbor, SuggestionNeighbor.next);
      expect(reason.neighborDanceId, 'B');
    });

    test('the phrase rule names the neighbour too', () {
      final r = rank(
        program: [a, b],
        position: SuggestionPosition(
          slotsBefore: [slot('A')],
          slotsAfter: [slot('B')],
        ),
        candidates: [overlapsB],
        settings: only(SuggestionFactor.matrixVariety),
        mode: MatrixCollisionMode.phrase,
      );
      final reason = overlapOf(r, 'overlaps-B')!;
      expect(reason.kind, SuggestionReasonKind.phraseOverlap);
      expect(reason.neighbor, SuggestionNeighbor.next);
      expect(reason.neighborDanceId, 'B');
    });

    test('formation balance compares both neighbours and names the one it '
        'matches', () {
      final becket = dance('becket', [
        fig('circle', 16),
      ], shape: FormationShape.becketCw);
      final becketCandidate = dance('becket-candidate', [
        fig('circle', 16),
      ], shape: FormationShape.becketCcw);
      final improper = dance('improper', [fig('circle', 16)]);
      final r = rank(
        program: [a, becket],
        position: SuggestionPosition(
          slotsBefore: [slot('A')],
          slotsAfter: [slot('becket')],
        ),
        candidates: [becketCandidate, improper],
        settings: only(SuggestionFactor.formationBalance),
      );
      final same = of(r, 'becket-candidate').reasons.singleWhere(
        (x) => x.kind == SuggestionReasonKind.sameFormationAsNeighbor,
      );
      expect(same.neighbor, SuggestionNeighbor.next);
      expect(same.neighborDanceId, 'becket');
      // The improper candidate matches A, before it.
      final before = of(r, 'improper').reasons.singleWhere(
        (x) => x.kind == SuggestionReasonKind.sameFormationAsNeighbor,
      );
      expect(before.neighbor, SuggestionNeighbor.previous);
      expect(before.neighborDanceId, 'A');
    });

    test('reads the difficulty curve at the position, not at the end', () {
      final program = [
        for (var i = 0; i < 10; i++)
          dance('p$i', const [], level: DifficultyLevel.intermediateId),
      ];
      final slots = [for (final d in program) slot(d.id)];
      final hard = dance('hard', const [], level: DifficultyLevel.advancedId);
      final easy = dance('easy', const [], level: DifficultyLevel.beginnerId);
      final settings = only(SuggestionFactor.difficultyCurve);
      // Second dance of the evening: the curve has barely started.
      final early = rank(
        program: program,
        position: SuggestionPosition.inserting(slots, 0, after: true),
        candidates: [hard, easy],
        settings: settings,
      );
      expect(order(early), ['easy', 'hard']);
      // The same program, at its end: near the top of the curve.
      final end = rank(
        program: program,
        position: SuggestionPosition.atEnd(slots),
        candidates: [easy, hard],
        settings: settings,
      );
      expect(order(end), ['hard', 'easy']);
    });
  });

  group('Replace…', () {
    test("leaves the slot's current dance out of the comparison", () {
      // Replacing B: its swing is not a neighbour of the candidates.
      final slots = [slot('A'), slot('B')];
      final r = rank(
        program: [a, b],
        position: SuggestionPosition.replacing(slots, 1),
        candidates: [overlapsB, clean],
        settings: only(SuggestionFactor.matrixVariety),
      );
      expect(overlapOf(r, 'overlaps-B'), isNull);
      expect(of(r, 'overlaps-B').score, of(r, 'clean').score);
      // The swing is new to the program without B.
      expect(
        of(r, 'clean').reasons
            .singleWhere((x) => x.kind == SuggestionReasonKind.newMoves)
            .count,
        2,
      );
    });

    test('ranks against the dances on both sides of the slot', () {
      // Replacing A in A, X, B: X goes, so B is the dance after.
      final x = dance('X', [fig('long_lines', 32)]);
      final slots = [slot('X'), slot('A'), slot('B')];
      final r = rank(
        program: [x, a, b],
        position: SuggestionPosition.replacing(slots, 1),
        candidates: [overlapsB, clean],
        settings: only(SuggestionFactor.matrixVariety),
      );
      expect(order(r), ['clean', 'overlaps-B']);
      expect(overlapOf(r, 'overlaps-B')!.neighborDanceId, 'B');
    });

    test('the dance being replaced is not "already in this program", '
        'unless another slot holds it', () {
      final slots = [slot('A'), slot('B')];
      final r = rank(
        program: [a, b],
        position: SuggestionPosition.replacing(slots, 1),
        candidates: [b, clean],
        settings: SuggestionSettings.defaults,
      );
      expect(of(r, 'B').ranked, isTrue);
      expect(
        of(r, 'B').reasons.map((x) => x.kind),
        isNot(contains(SuggestionReasonKind.alreadyInProgram)),
      );
      final twice = [
        slot('A'),
        slot('B'),
        ProgramSlot(id: 's-B-again', position: 0, danceId: 'B'),
      ];
      final r2 = rank(
        program: [a, b],
        position: SuggestionPosition.replacing(twice, 1),
        candidates: [b, clean],
        settings: SuggestionSettings.defaults,
      );
      expect(order(r2), ['clean', 'B']);
      expect(
        of(r2, 'B').headline.single.kind,
        SuggestionReasonKind.alreadyInProgram,
      );
    });

    test("an alternate's replacement is an alternative to its group, not "
        'its neighbour', () {
      // A, then B with an alternate (replaced), then C. The candidate stands
      // beside A and C; B is an alternative to it.
      final c = dance('C', [fig('long_lines', 32)]);
      final overlapsA = dance('overlaps-A', [
        fig('petronella', 16),
        fig('do_si_do', 16),
      ]);
      final slots = [
        slot('A'),
        slot('B'),
        ProgramSlot(id: 's-alt', position: 0, danceId: 'C', isAlt: true),
        slot('C'),
      ];
      final position = SuggestionPosition.replacing(slots, 2);
      expect(position.isAlternate, isTrue);
      final r = rank(
        program: [a, b, c],
        position: position,
        candidates: [overlapsA, overlapsB],
        settings: only(SuggestionFactor.matrixVariety),
      );
      expect(order(r), ['overlaps-B', 'overlaps-A']);
      final reason = overlapOf(r, 'overlaps-A')!;
      expect(reason.neighbor, SuggestionNeighbor.previous);
      expect(reason.neighborDanceId, 'A');
      expect(overlapOf(r, 'overlaps-B'), isNull);
    });

    test("an alternate's replacement reads the curve where its primary is", () {
      // Twelve dances, the tenth with an alternate. Replacing the alternate
      // and replacing the primary are the same place in the evening.
      final program = [
        for (var i = 0; i < 12; i++)
          dance('p$i', const [], level: DifficultyLevel.intermediateId),
      ];
      final slots = [
        for (var i = 0; i < 12; i++) ...[
          slot('p$i'),
          if (i == 9)
            ProgramSlot(id: 's-alt', position: 0, danceId: 'p0', isAlt: true),
        ],
      ];
      final candidate = dance(
        'mid',
        const [],
        level: DifficultyLevel.intermediateId,
      );
      SuggestionReason curve(SuggestionPosition position) => of(
        rank(
          program: program,
          position: position,
          candidates: [candidate],
          settings: only(SuggestionFactor.difficultyCurve),
        ),
        'mid',
      ).reasons.single;
      final alternate = curve(SuggestionPosition.replacing(slots, 10));
      final primary = curve(SuggestionPosition.replacing(slots, 9));
      expect(alternate.kind, SuggestionReasonKind.easierThanCurve);
      expect(alternate.effect, primary.effect);
    });
  });

  group('SuggestionPosition', () {
    final slots = [
      slot('A'),
      slot('B'),
      slot('B2', alt: true),
      note(Program.breakSlotText),
      slot('C'),
    ];
    List<String> ids(List<ProgramSlot> s) => [for (final x in s) x.id];

    test('inserting lands at the group boundary, as the builder adds', () {
      final before = SuggestionPosition.inserting(slots, 2, after: false);
      expect(ids(before.slotsBefore), ['s-A']);
      expect(ids(before.slotsAfter), ['s-B', 's-B2', 'n-Break', 's-C']);
      expect(before.isAlternate, isFalse);
      final after = SuggestionPosition.inserting(slots, 1, after: true);
      expect(ids(after.slotsBefore), ['s-A', 's-B', 's-B2']);
      expect(ids(after.slotsAfter), ['n-Break', 's-C']);
    });

    test('inserting before a leading run of orphaned alternates gives the '
        'run promoted, as the add will', () {
      final orphaned = [slot('X', alt: true), slot('Y', alt: true), slot('A')];
      final p = SuggestionPosition.inserting(orphaned, 0, after: false);
      expect(p.slotsBefore, isEmpty);
      expect([for (final s in p.slotsAfter) s.isAlt], [false, true, false]);
    });

    test('replacing leaves the slot out, and says whether it is an '
        'alternate', () {
      final p = SuggestionPosition.replacing(slots, 2);
      expect(ids(p.slotsBefore), ['s-A', 's-B']);
      expect(ids(p.slotsAfter), ['n-Break', 's-C']);
      expect(p.isAlternate, isTrue);
      expect(SuggestionPosition.replacing(slots, 1).isAlternate, isFalse);
    });

    test('at the end is every slot before, none after', () {
      final p = SuggestionPosition.atEnd(slots);
      expect(ids(p.slotsBefore), ids(slots));
      expect(p.slotsAfter, isEmpty);
      expect(p, SuggestionPosition.atEnd([...slots]));
      expect(p, isNot(SuggestionPosition.replacing(slots, 4)));
    });
  });
}
