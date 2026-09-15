import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// The §10.5 canonical Duple Improper progression example, pre-progression.
const _diPreProgression = [
  'L2-B . . . R2-B',
  'R1-A . . . L1-A',
  'L2-D . . . R2-D',
  'R1-C . . . L1-C',
];

/// The same state after the progression's end-normalization (§10.5).
const _diPostProgression = [
  'R1-B . . . L1-B',
  'R1-A . . . L1-A',
  'L2-D . . . R2-D',
  'L2-C . . . R2-C',
];

/// The Becket starting state (§10.6) — couples stacked in columns, so each end
/// row holds one dancer from each of two different couples.
const _becketStart = [
  'L2-B . . . R1-A',
  'R2-B . . . L1-A',
  'L2-D . . . R1-C',
  'R2-D . . . L1-C',
];

Formation _di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

Formation _becket(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.becketCw);

void main() {
  group('Result', () {
    test('Ok carries its value and folds to the success branch', () {
      const result = Ok<int, String>(7);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 7);
      expect(result.errorOrNull, isNull);
      expect(result.fold((v) => 'ok $v', (e) => 'err $e'), 'ok 7');
    });

    test('Err carries its error and folds to the failure branch', () {
      const result = Err<int, String>('boom');
      expect(result.isOk, isFalse);
      expect(result.valueOrNull, isNull);
      expect(result.errorOrNull, 'boom');
      expect(result.fold((v) => 'ok $v', (e) => 'err $e'), 'err boom');
    });

    test('map transforms a success and leaves a failure alone', () {
      expect(
        const Ok<int, String>(2).map((v) => v * 3),
        const Ok<int, String>(6),
      );
      expect(
        const Err<int, String>('bad').map((v) => v * 3),
        const Err<int, String>('bad'),
      );
    });

    test('flatMap chains successes and short-circuits on failure', () {
      Result<int, String> halve(int v) =>
          v.isEven ? Ok<int, String>(v ~/ 2) : const Err<int, String>('odd');

      expect(
        const Ok<int, String>(8).flatMap(halve).flatMap(halve),
        const Ok<int, String>(2),
      );
      expect(
        const Ok<int, String>(6).flatMap(halve).flatMap(halve),
        const Err<int, String>('odd'),
      );

      // Once failed, later steps must not run at all.
      var ran = false;
      const Err<int, String>('early').flatMap((v) {
        ran = true;
        return Ok<int, String>(v);
      });
      expect(ran, isFalse);
    });

    test('equality is by case and payload', () {
      expect(const Ok<int, String>(1), const Ok<int, String>(1));
      expect(const Ok<int, String>(1), isNot(const Ok<int, String>(2)));
      expect(const Ok<int, String>(1), isNot(const Err<int, String>('1')));
      expect(
        const Ok<int, String>(1).hashCode,
        const Ok<int, String>(1).hashCode,
      );
    });
  });

  group('diagnostics', () {
    test('every error kind keeps its canonical taxonomy spelling', () {
      expect(
        ErrorKind.values.map((k) => k.key),
        containsAll(<String>[
          'whoMismatch',
          'notAdjacent',
          'UnresolvableDancerSet',
          'UnsupportedParam',
        ]),
      );
    });

    test('facing is reported as a warning and never as a refusal', () {
      // The ruling that facing is the softest thing the matrix holds. There is
      // no error kind left that can be raised for it, which is what stops a
      // future figure from quietly reintroducing a fatal facing check.
      expect(
        ErrorKind.values.map((k) => k.key),
        isNot(contains('invalidFacing')),
      );
      expect(
        WarningKind.values.map((k) => k.key),
        contains('facingPrecondition'),
      );
    });

    test('OpError falls back to the kind gloss when no detail is given', () {
      const bare = OpError(ErrorKind.notAdjacent);
      expect(bare.message, ErrorKind.notAdjacent.description);
      const detailed = OpError(
        ErrorKind.notAdjacent,
        'L-A and R-B are diagonal',
      );
      expect(detailed.message, 'L-A and R-B are diagonal');
      expect(detailed, isNot(bare));
    });

    test('Warning may or may not point at an operation', () {
      const whole = Warning(WarningKind.oneSidedHall);
      const pinned = Warning(WarningKind.oneSidedHall, opIndex: 3);
      expect(whole.opIndex, isNull);
      expect(pinned.toString(), contains('@3'));
      expect(whole, isNot(pinned));
    });
  });

  group('sizing (3.1)', () {
    test('an empty dance still gets the base two hands four', () {
      expect(computeHandsFour(const []), kBaseHandsFour);
      expect(kBaseHandsFour, 2);
    });

    test('contributions are summed per instance, not per kind', () {
      expect(computeHandsFour(const [0, 0, 0]), 2);
      expect(computeHandsFour(const [1, 1, 1]), 5);
      // The worked example: a double progression plus one expanding figure.
      expect(computeHandsFour(const [1, 1]), 4);
    });
  });

  group('StandStill', () {
    test('is a pure identity over the whole state', () {
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      final result = const StandStill().apply(start);
      expect(result.isOk, isTrue);
      final after = result.valueOrNull!;
      expect(after.toMatrix(), start.toMatrix());
      // Identity means facing survives too, which matrix equality would miss.
      expect(after.dancers, start.dancers);
    });

    test('reports its registry key and contributes no hands four', () {
      const op = StandStill();
      expect(op.name, 'stand_still');
      expect(op.hands4Contribution, 0);
      expect(op.progressionEligible, isFalse);
      expect(op.toString(), 'stand_still');
    });

    test('beats are timing only and do not affect the result', () {
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      expect(
        const StandStill(beats: 16).apply(start).valueOrNull!.toMatrix(),
        const StandStill(beats: 4).apply(start).valueOrNull!.toMatrix(),
      );
      expect(const StandStill(beats: 8), const StandStill());
      expect(const StandStill(beats: 8), isNot(const StandStill(beats: 4)));
    });
  });

  group('end-normalization (10.2)', () {
    test('reproduces the 10.5 canonical Duple Improper example exactly', () {
      final after = applyEndNormalization(_di(_diPreProgression));
      expect(after.toRolesNotation(), _diPostProgression);
    });

    test('end couples turn back into the set', () {
      final after = applyEndNormalization(_di(_diPreProgression));
      for (final id in after.dancersInRow(0)) {
        expect(after.stateOf(id).facing, Facing.down);
      }
      for (final id in after.dancersInRow(after.lastRow)) {
        expect(after.stateOf(id).facing, Facing.up);
      }
    });

    test('end couples flip number; interior couples keep theirs', () {
      final before = _di(_diPreProgression);
      final after = applyEndNormalization(before);

      const larkB = DancerId(1, Role.lark);
      const larkA = DancerId(0, Role.lark);
      expect(before.stateOf(larkB).number, CoupleNumber.two);
      expect(after.stateOf(larkB).number, CoupleNumber.one);
      expect(after.stateOf(larkA).number, before.stateOf(larkA).number);
    });

    test('interior rows are untouched, facing included', () {
      final before = _di(_diPreProgression);
      final after = applyEndNormalization(before);
      for (final row in [1, 2]) {
        for (final id in before.dancersInRow(row)) {
          expect(after.stateOf(id), before.stateOf(id), reason: 'row $row');
        }
      }
    });

    test('normalizing marks the end couples as standing out', () {
      // The whole point of normalizing: it is what takes the end couples out
      // of the active hands four, leaving a single band across rows 1-2.
      final after = applyEndNormalization(_di(_diPreProgression));
      expect(waitingOutRows(after), [0, 3]);
      expect(handsFourBands(after), [(topRow: 1, bottomRow: 2)]);
    });

    test('re-applying leaves the matrix alone but rotates who stands out', () {
      // The *matrix* is idempotent: the end number is assigned from the end
      // reached rather than flipped, so positions and numbers are stable.
      // Waiting-out state deliberately is not - a second application is a
      // second progression, and the couples that have served their round
      // re-enter (§10.3 change-over).
      final once = applyEndNormalization(_di(_diPreProgression));
      final twice = applyEndNormalization(once);
      expect(twice.toRolesNotation(), once.toRolesNotation());
      expect(waitingOutRows(once), [0, 3]);
      expect(waitingOutRows(twice), isEmpty);
      expect(handsFourBands(twice), [
        (topRow: 0, bottomRow: 1),
        (topRow: 2, bottomRow: 3),
      ]);
    });

    test(
      'a couple that has served its round re-enters and is not re-marked',
      () {
        // The user-supplied trace, run end to end. Progression 1 over B/A/D/C
        // takes B and C out. The active band (1,2) then swaps A and D, which is
        // all a within-hands-four figure can reach - B and C have not moved.
        // Progression 2 must still bring them back in.
        final afterFirst = applyEndNormalization(
          _di(const [
            'L2-B . . . R2-B',
            'R1-A . . . L1-A',
            'L2-D . . . R2-D',
            'R1-C . . . L1-C',
          ]),
        );
        expect(waitingOutRows(afterFirst), [0, 3]);
        expect(handsFourBands(afterFirst), [(topRow: 1, bottomRow: 2)]);

        // Stand in for the next progression figure's own transform: the active
        // band exchanges rows, giving the user's second grid B / D / A / C.
        final swapped = afterFirst.withUpdates({
          for (final id in afterFirst.dancersInRow(1))
            id: afterFirst
                .stateOf(id)
                .movedTo(Position(2, afterFirst.stateOf(id).col)),
          for (final id in afterFirst.dancersInRow(2))
            id: afterFirst
                .stateOf(id)
                .movedTo(Position(1, afterFirst.stateOf(id).col)),
        });

        final afterSecond = applyEndNormalization(swapped);
        expect(waitingOutRows(afterSecond), isEmpty);
        expect(handsFourBands(afterSecond), [
          (topRow: 0, bottomRow: 1),
          (topRow: 2, bottomRow: 3),
        ]);
        // B derives into a hands four with D, exactly as specified.
        final band = handsFourBandContaining(afterSecond, 0)!;
        final couples = {
          for (final row in [band.topRow, band.bottomRow])
            for (final id in afterSecond.dancersInRow(row)) id.coupleLetter,
        };
        expect(couples, {'B', 'D'});
      },
    );

    test('the end number is assigned, not flipped', () {
      // A couple that arrives at the top already holding #1 stays #1 rather
      // than being toggled to #2.
      final alreadyOne = _di(const [
        'L1-B . . . R1-B',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'R1-C . . . L1-C',
      ]);
      final after = applyEndNormalization(alreadyOne);
      expect(after.toRolesNotation().first, 'R1-B . . . L1-B');
    });
  });

  group('end number is assigned by destination line (10.2.1, decision 1C)', () {
    /// A whole couple collected into an end row, ready to normalize.
    List<String> collected(String top, String bottom) => [
      top,
      'L2-D . . . R1-C',
      'R2-D . . . L1-C',
      bottom,
    ];

    test('Becket CW: top takes #1 and bottom takes #2', () {
      // 10.6 CW+Single: B runs off the top of c0 (the 2s line) and re-enters
      // c4 (the 1s line), so it lands at the top as a #1.
      final before = _becket(collected('L2-B . . . R2-B', 'R1-E . . . L1-E'));
      final after = applyEndNormalization(before);
      expect(after.toRolesNotation().first, 'R1-B . . . L1-B');
      expect(after.toRolesNotation().last, 'L2-E . . . R2-E');
    });

    test('Becket CCW mirrors it: top takes #2 and bottom takes #1', () {
      // 10.6 CCW+Single: c4 (the 1s line) shifts UP, so it is a 1s couple that
      // runs off the top; it re-enters c0 (the 2s line) and waits out as a #2.
      // The oracle's row 0 is exactly 'R2-A . . . L2-A'.
      final before = parseRolesNotation(
        collected('L1-A . . . R1-A', 'R2-E . . . L2-E'),
        type: FormationType.becketCcw,
      );
      final after = applyEndNormalization(before);
      expect(after.toRolesNotation().first, 'R2-A . . . L2-A');
      expect(after.toRolesNotation().last, 'L1-E . . . R1-E');
    });

    test('the two Becket senses disagree on the same input', () {
      final rows = collected('L1-A . . . R1-A', 'R2-E . . . L2-E');
      final cw = applyEndNormalization(
        parseRolesNotation(rows, type: FormationType.becketCw),
      );
      final ccw = applyEndNormalization(
        parseRolesNotation(rows, type: FormationType.becketCcw),
      );
      expect(cw.toRolesNotation().first, isNot(ccw.toRolesNotation().first));
    });

    test('Duple Improper follows the CW sense: top #1, bottom #2', () {
      expect(FormationType.dupleImproper.topEndNumber, CoupleNumber.one);
      expect(FormationType.becketCw.topEndNumber, CoupleNumber.one);
      expect(FormationType.becketCcw.topEndNumber, CoupleNumber.two);
      for (final type in FormationType.values) {
        expect(type.bottomEndNumber, type.topEndNumber.flipped);
      }
    });

    test('both partners always receive the same number', () {
      // The structural guarantee of decision 2B: a number is written for the
      // couple, never for one dancer, so partners cannot desync here.
      final after = applyEndNormalization(
        _becket(collected('L2-B . . . R2-B', 'R1-E . . . L1-E')),
      );
      for (final coupleIndex in [1, 4]) {
        expect(
          after.stateOf(DancerId(coupleIndex, Role.lark)).number,
          after.stateOf(DancerId(coupleIndex, Role.robin)).number,
        );
      }
    });
  });

  group('end-normalization selection (10.2.1, decision 2B)', () {
    test('skips an end row holding two dancers from different couples', () {
      // The Becket start: r0 is L2-B (c0) and R1-A (c4) - not partners. This
      // is the shape that a positional rule would normalize, desyncing both
      // couples' numbers against their partners in r1.
      final before = _becket(_becketStart);
      final after = applyEndNormalization(before);
      expect(after.toRolesNotation(), _becketStart);
      expect(after.dancers, before.dancers);
    });

    test('a skipped end leaves every number matching its partner', () {
      final after = applyEndNormalization(_becket(_becketStart));
      for (var coupleIndex = 0; coupleIndex < 4; coupleIndex++) {
        expect(
          after.stateOf(DancerId(coupleIndex, Role.lark)).number,
          after.stateOf(DancerId(coupleIndex, Role.robin)).number,
          reason: 'couple $coupleIndex',
        );
      }
    });

    test('skips a line of four rather than treating it as a couple', () {
      // 8.1: two whole couples in one row is an entire hands four, not an end
      // couple. Guards the "exactly one" qualifier.
      final lineOfFour = _di(const [
        'L2-B R2-B L1-A R1-A .',
        '. . . . .',
        'L2-D . . . R2-D',
        'R1-C . . . L1-C',
      ]);
      final after = applyEndNormalization(lineOfFour);
      expect(after.toRolesNotation().first, lineOfFour.toRolesNotation().first);
      // The other end still normalizes: the two ends are independent.
      expect(after.toRolesNotation().last, 'L2-C . . . R2-C');
    });

    test('skips an empty end row', () {
      final gapped = _di(const [
        '. . . . .',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'R1-C . . . L1-C',
      ]);
      final after = applyEndNormalization(gapped);
      expect(after.dancersInRow(0), isEmpty);
      expect(after.toRolesNotation().last, 'L2-C . . . R2-C');
    });

    test('skips a lone dancer at an end', () {
      final lone = _di(const [
        'L2-B . . . .',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'R1-C . . . L1-C',
      ]);
      final after = applyEndNormalization(lone);
      expect(after.toRolesNotation().first, 'L2-B . . . .');
    });

    test('skips a same-role pair, which is not a couple', () {
      final sameRole = _di(const [
        'L2-B . . . L1-A',
        '. . . . .',
        'L2-D . . . R2-D',
        'R1-C . . . L1-C',
      ]);
      final after = applyEndNormalization(sameRole);
      expect(after.toRolesNotation().first, 'L2-B . . . L1-A');
    });

    test("The Judge's pre-progression end rows are non-partner pairs", () {
      // Regression guard for the deferred question: at the instant The Judge's
      // op-6 progression fires, r0 holds R2-D + L2-B and r5 holds L1-E + R1-C.
      // Under 2B both ends skip, so the whole-couple ends the fixture expects
      // must be produced by petronella's own transform, not by this step. If
      // that turns out to be false, this test is where the model breaks.
      final afterOp5 = _becket(const [
        'R2-D . . . L2-B',
        'L1-A . . . R2-B',
        'R2-F . . . L2-D',
        'L1-C . . . R1-A',
        'R1-E . . . L2-F',
        'L1-E . . . R1-C',
      ]);
      expect(applyEndNormalization(afterOp5).dancers, afterOp5.dancers);
    });
  });

  group('OperationInvocation', () {
    final start = startingFormation(FormationType.dupleImproper, handsFour: 2);
    final preProgression = _di(_diPreProgression);

    test('the canonical DI start is already end-normalized in the matrix', () {
      // Both end rows hold a whole couple, already numbered and placed for
      // their end - so the positional half of the rule is a no-op. A good
      // sanity check that the start builder and this rule agree.
      expect(applyEndNormalization(start).toMatrix(), start.toMatrix());
      for (final entry in start.dancers.entries) {
        final after = applyEndNormalization(start).stateOf(entry.key);
        expect(after.position, entry.value.position);
        expect(after.number, entry.value.number);
        expect(after.facing, entry.value.facing);
      }
    });

    test('applying it to a start state still marks the ends - by design', () {
      // Waiting-out state is the one thing normalization does *not* leave
      // alone, and it should not: in Duple Improper every row holds a whole
      // couple, so the end rows always qualify. The rule cannot be made to
      // skip couples that sit in a complete band instead - that would break
      // §10.5, where B is banded with A and still waits out. Normalization
      // only ever runs behind a progression flag (§10.1), so applying it to a
      // start state is a category error rather than a case to defend against.
      expect(waitingOutRows(start), isEmpty);
      expect(waitingOutRows(applyEndNormalization(start)), [0, start.lastRow]);
    });

    test('without the flag, no end-normalization runs', () {
      final result = const OperationInvocation(
        StandStill(),
      ).apply(preProgression);
      expect(result.valueOrNull!.toMatrix(), preProgression.toMatrix());
    });

    test('with the flag, end-normalization runs after the transform', () {
      final result = const OperationInvocation(
        StandStill(),
        progression: true,
      ).apply(preProgression);
      final after = result.valueOrNull!;
      expect(after.toMatrix(), isNot(preProgression.toMatrix()));
      expect(after.toRolesNotation(), _diPostProgression);
    });

    test('names and compares by operation plus flag', () {
      const plain = OperationInvocation(StandStill());
      const progressing = OperationInvocation(StandStill(), progression: true);
      expect(plain.name, 'stand_still');
      expect(plain, const OperationInvocation(StandStill()));
      expect(plain, isNot(progressing));
      expect(progressing.toString(), contains('progression'));
    });
  });

  group('CompileResult', () {
    final start = _di(_diPreProgression);
    final other = applyEndNormalization(start);

    test('Compiled is the only success case', () {
      expect(Compiled(start).isSuccess, isTrue);
      expect(Mismatch(actual: start, expected: other).isSuccess, isFalse);
      expect(
        const CompileError(
          opIndex: 0,
          opName: 'stand_still',
          error: OpError(ErrorKind.notAdjacent),
        ).isSuccess,
        isFalse,
      );
    });

    test('Mismatch retains both states for diffing', () {
      final mismatch = Mismatch(actual: start, expected: other);
      expect(mismatch.actual, start);
      expect(mismatch.expected, other);
      expect(mismatch.actual, isNot(mismatch.expected));
    });

    test('CompileError reports where and why, with no final state', () {
      const error = CompileError(
        opIndex: 4,
        opName: 'box_the_gnat',
        error: OpError(ErrorKind.notAdjacent, 'diagonal'),
      );
      expect(error.opIndex, 4);
      expect(error.kind, ErrorKind.notAdjacent);
      expect(error.toString(), contains('box_the_gnat'));
    });

    test('warnings ride along on every outcome', () {
      const warning = Warning(WarningKind.oneSidedHall, opIndex: 2);
      expect(Compiled(start, warnings: const [warning]).warnings, [warning]);
      expect(
        Mismatch(
          actual: start,
          expected: other,
          warnings: const [warning],
        ).warnings,
        [warning],
      );
      expect(Compiled(start).warnings, isEmpty);
    });

    test('every outcome prints something a reader can act on', () {
      expect(Compiled(start).toString(), contains('Compiled'));
      expect(
        Mismatch(actual: start, expected: other).toString(),
        allOf(contains('Mismatch'), contains('actual'), contains('expected')),
      );
    });
  });

  group('diagnostics are values', () {
    // Errors and warnings are compared and de-duplicated by the engine and by
    // the tests, so they need the same field-complete equality the figures do.
    test('an OpError equals one carrying the same kind and message', () {
      const a = OpError(ErrorKind.notAdjacent, 'diagonal');
      const b = OpError(ErrorKind.notAdjacent, 'diagonal');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const OpError(ErrorKind.notAdjacent, 'not diagonal')));
      expect(a, isNot(const OpError(ErrorKind.whoMismatch, 'diagonal')));
    });

    test('an OpError falls back to its kind gloss', () {
      const bare = OpError(ErrorKind.notAdjacent);
      expect(bare.message, ErrorKind.notAdjacent.description);
      expect(bare.toString(), contains(ErrorKind.notAdjacent.key));
      expect(bare, isNot(const OpError(ErrorKind.notAdjacent, 'diagonal')));
    });

    test('a Warning compares on kind, index and message alike', () {
      const a = Warning(WarningKind.oneSidedHall, opIndex: 2);
      const b = Warning(WarningKind.oneSidedHall, opIndex: 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const Warning(WarningKind.oneSidedHall, opIndex: 3)));
      expect(
        a,
        isNot(
          const Warning(
            WarningKind.oneSidedHall,
            opIndex: 2,
            detail: 'something specific',
          ),
        ),
      );
    });

    test('a Warning names its figure only when it points at one', () {
      const anchored = Warning(WarningKind.oneSidedHall, opIndex: 2);
      const floating = Warning(WarningKind.oneSidedHall);
      expect(anchored.toString(), contains('@2'));
      expect(floating.toString(), isNot(contains('@')));
      expect(floating.message, WarningKind.oneSidedHall.description);
    });
  });
}
