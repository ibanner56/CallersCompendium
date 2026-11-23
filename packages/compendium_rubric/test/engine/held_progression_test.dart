import 'dart:convert';
import 'dart:io';

import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Map<String, Object?> _golden(String name) =>
    jsonDecode(File('test/golden/$name.json').readAsStringSync())
        as Map<String, Object?>;

/// A golden record with its progression flag moved to figure [flagAt].
Dance progressingOn(String name, int flagAt) {
  final golden = _golden(name);
  final figures = [
    for (final figure in golden['figures']! as List<Object?>)
      Map<String, Object?>.of(figure! as Map<String, Object?>)
        ..remove('progression'),
  ];
  figures[flagAt]['progression'] = true;
  final parsed = parseDance({...golden, 'figures': figures});
  return (parsed as Ok<Dance, DanceParseError>).value;
}

/// The figure index of The Judge's left-diagonal ladies chain.
const _chain = 3;

/// The Judge's single-progression end state (`test/golden/the_judge.json`).
List<Object?> get _judgeExpected =>
    (_golden('the_judge')['expected']!
            as Map<String, Object?>)['rolesNotation']!
        as List<Object?>;

void main() {
  group('a Becket progression with nobody at an end yet is held', () {
    test('The Judge compiles progressing on its diagonal chain', () {
      // User-ruled 2026-11-23: a Becket dance progresses on the obvious move.
      // The chain sends the robins on, but no couple stands whole at an end
      // until the second petronella, so the change-over is held until then.
      final result = compile(progressingOn('the_judge', _chain));
      expect(result, isA<Compiled>(), reason: '$result');
      expect(
        (result as Compiled).finalFormation.toRolesNotation(),
        _judgeExpected,
      );
      expect(
        result.warnings.map((w) => w.kind),
        isNot(contains(WarningKind.heldProgressionUnfinished)),
      );
    });

    test('the chain holds and the second petronella finishes it', () {
      final dance = progressingOn('the_judge', _chain);
      final fold = FigureFold(holdsProgressions: true);
      var state = dance.instantiate();
      final waitingAfter = <int, int>{};
      for (var i = 0; i < dance.figures.length; i++) {
        state =
            (fold.step(dance.figures[i], state, index: i)
                    as Ok<Formation, OpError>)
                .value;
        waitingAfter[i] = state.dancers.values
            .where((d) => d.waitingOut)
            .length;
        if (i == _chain) {
          expect(fold.unfinished, [_chain]);
          expect(endHasWholeCouple(state), isFalse);
        }
      }
      // Nobody steps out on the chain or the first petronella; the second
      // petronella brings couple B to the top and couple E to the bottom.
      expect(waitingAfter[_chain], 0);
      expect(waitingAfter[_chain + 1], 0);
      expect(waitingAfter[_chain + 2], 4);
      expect(fold.unfinished, isEmpty);
      expect(fold.progressions, 1);
    });

    test('a flag where a couple already stands at an end is not held', () {
      // The golden placement: the second petronella brings couple B to the
      // top, so the change-over runs on the flagged figure itself.
      final dance = progressingOn('the_judge', 5);
      var state = dance.instantiate();
      for (var i = 0; i < 5; i++) {
        state = (dance.figures[i].apply(state) as Ok<Formation, OpError>).value;
      }
      final outcome = dance.figures[5].applyHolding(state);
      final value = (outcome as Ok).value as ({Formation formation, bool held});
      expect(value.held, isFalse);
      expect(
        value.formation,
        (dance.figures[5].apply(state) as Ok<Formation, OpError>).value,
      );
    });

    test('couples already standing out still count as being at an end', () {
      // The next time through, the only whole couples at the ends are the
      // ones already standing out. A change-over still has work to do there
      // (it brings them back in), so finding only them is no reason to hold.
      final dance = progressingOn('the_judge', _chain);
      final fold = FigureFold(holdsProgressions: true);
      var state = dance.instantiate();
      for (var i = 0; i < dance.figures.length; i++) {
        state =
            (fold.step(dance.figures[i], state, index: i)
                    as Ok<Formation, OpError>)
                .value;
      }
      final standingOut = {
        for (final entry in state.dancers.entries)
          if (entry.value.waitingOut) entry.key.coupleIndex,
      };
      expect(standingOut, hasLength(2));
      expect(endHasWholeCouple(state), isTrue);
    });

    test('a progression that never finds a couple at an end warns', () {
      // Flagged on the last figure of a twice-through where nobody is whole
      // at an end afterwards: held, never finished, and said so.
      final once = progressingOn('the_judge', _chain);
      final dance = Dance(
        name: 'The Judge, cut short',
        formation: once.formation,
        success: const ProgressionCriterion(),
        figures: once.figures.take(_chain + 1).toList(),
      );
      final result = compile(dance);
      expect(
        result.warnings
            .where((w) => w.kind == WarningKind.heldProgressionUnfinished)
            .map((w) => w.opIndex),
        [_chain],
      );
    });
  });

  group('what is never held', () {
    test('a flagged slide with nobody whole at an end is not held', () {
      // The slide is its own progression and sets its own waiting-out state.
      final circled =
          (const Circle(turn: CircleDirection.left, places: 3).apply(
                    startingFormation(FormationType.becketCw, handsFour: 3),
                  )
                  as Ok<Formation, OpError>)
              .value;
      const slide = SlideAlongSet();
      final bare = (slide.apply(circled) as Ok<Formation, OpError>).value;
      expect(endHasWholeCouple(bare), isFalse);
      final outcome = const OperationInvocation(
        slide,
        progression: true,
      ).applyHolding(circled);
      final value = (outcome as Ok).value as ({Formation formation, bool held});
      expect(value.held, isFalse);
    });

    test('a later flagged figure overtakes a held progression', () {
      // Flags on the chain (held) and on the second petronella (whose own
      // change-over runs). Finishing the chain's afterwards would retire the
      // couples the petronella had just sent out, so it is given up and
      // reported instead.
      final judge = progressingOn('the_judge', _chain);
      final figures = [
        for (final (i, figure) in judge.figures.indexed)
          i == 5
              ? OperationInvocation(figure.operation, progression: true)
              : figure,
      ];
      final fold = FigureFold(holdsProgressions: true);
      var state = judge.instantiate();
      final waiting = <int>[];
      for (var i = 0; i < figures.length; i++) {
        state =
            (fold.step(figures[i], state, index: i) as Ok<Formation, OpError>)
                .value;
        waiting.add(state.dancers.values.where((d) => d.waitingOut).length);
      }
      expect(waiting[5], 4);
      expect(waiting[6], 4, reason: 'the partner swing must not retire them');
      expect(fold.unfinished, [_chain]);
      expect(fold.progressions, 2);
    });
  });

  group('Duple Improper never holds', () {
    test('a flag with nobody at an end is spent where it stands', () {
      // Holding was ruled for Becket. A Duple Improper golden flagged one
      // figure early must still fail rather than be carried forward. (Two
      // figures early: one early happens to land on the oracle anyway.)
      final golden = _golden('the_baby_rose');
      final flagged = [
        for (final (i, figure) in (golden['figures']! as List<Object?>).indexed)
          if ((figure! as Map<String, Object?>)['progression'] == true) i,
      ];
      expect(flagged, hasLength(1));
      final result = compile(
        progressingOn('the_baby_rose', flagged.single - 2),
      );
      expect(result, isNot(isA<Compiled>()), reason: '$result');
    });
  });
}
