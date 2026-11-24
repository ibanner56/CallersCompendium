import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// Partners are row-mates, neighbours column-mates (`docs/taxonomy.md`).
const List<String> base = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];
const List<String> rowSwap = ['L2-B . . . R2-B', 'R1-A . . . L1-A'];

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

void main() {
  group('arch_and_dive is the row swap (user-ruled)', () {
    for (final who in [WhoSet.ones, WhoSet.twos]) {
      test('${who.key} arching: the couples trade places along the set', () {
        expect(
          applyOk(ArchAndDive(who: who), di(base)).toRolesNotation(),
          rowSwap,
        );
      });
    }

    test('facing is preserved: both couples walk forward through', () {
      final before = startingFormation(
        FormationType.dupleImproper,
        handsFour: 1,
      );
      final after = applyOk(const ArchAndDive(), before);
      for (final entry in after.dancers.entries) {
        expect(entry.value.facing, before.stateOf(entry.key).facing);
      }
    });

    test('twice is the identity', () {
      expect(
        applyOk(const ArchAndDive(), applyOk(const ArchAndDive(), di(base))),
        di(base),
      );
    });
  });

  test('who is descriptive: it names no set to reach for', () {
    // A named set would otherwise re-band the set before the swap.
    expect(const ArchAndDive(who: WhoSet.nextNeighbors).dancerSets, isEmpty);
    expect(
      applyOk(const ArchAndDive(who: WhoSet.nextNeighbors), di(base)),
      applyOk(const ArchAndDive(), di(base)),
    );
  });

  test('swaps the rows of every hands four', () {
    final two = startingFormation(FormationType.dupleImproper, handsFour: 2);
    final after = applyOk(const ArchAndDive(), two);
    for (final entry in after.dancers.entries) {
      final from = two.stateOf(entry.key).position;
      final band = from.row ~/ 2 * 2;
      expect(entry.value.position.col, from.col);
      expect(entry.value.position.row, band + (1 - (from.row - band)));
    }
  });

  test('is progression-eligible, and not its own progression', () {
    expect(const ArchAndDive().progressionEligible, isTrue);
    expect(const ArchAndDive().isItsOwnProgression, isFalse);
  });

  group('from a line of four, the line bends into a ring first '
      '(user-ruled 2026-11-24)', () {
    Formation line(List<String> rows, Facing facing) => parseRolesNotation(
      rows,
      type: FormationType.dupleImproper,
      defaultFacing: facing,
    );

    test('a line facing up: the ends step up, then the couples trade', () {
      // Ones on the ends, as after "go up the hall (M1-W2-M2-W1)".
      final before = line(['. . . . .', 'R1-A L2-B . R2-B L1-A'], Facing.up);
      final after = applyOk(const ArchAndDive(who: WhoSet.twos), before);

      // Bent: the ones above facing down, the twos below facing up. Then the
      // swap: the twos pass up, the ones down, still facing the way they
      // walked.
      expect(after.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
      for (final id in ['L2-B', 'R2-B']) {
        expect(after.stateOf(_id(id)).facing, Facing.up, reason: id);
      }
      for (final id in ['R1-A', 'L1-A']) {
        expect(after.stateOf(_id(id)).facing, Facing.down, reason: id);
      }
    });

    test('a line backing up the hall: the ends step down, then the couples '
        'trade', () {
      // Twos on the ends, facing down: "go up the hall (backwards)" after
      // "go down the hall (W2-M1-W1-M2)".
      final before = line(['L2-B R1-A . L1-A R2-B', '. . . . .'], Facing.down);
      final after = applyOk(const ArchAndDive(who: WhoSet.ones), before);

      expect(after.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
      for (final id in ['L2-B', 'R2-B']) {
        expect(after.stateOf(_id(id)).facing, Facing.up, reason: id);
      }
      for (final id in ['R1-A', 'L1-A']) {
        expect(after.stateOf(_id(id)).facing, Facing.down, reason: id);
      }
    });

    test('a line that bends raises no warning', () {
      expect(
        const ArchAndDive().lint(
          line(['. . . . .', 'R1-A L2-B . R2-B L1-A'], Facing.up),
        ),
        isEmpty,
      );
    });

    test('in a compiled dance, after a hall figure, nothing is raised', () {
      final result = compile(
        Dance(
          formation: FormationType.dupleImproper,
          success: const ProgressionCriterion(count: 1),
          figures: [
            OperationInvocation(const UpTheHall(ender: HallEnder.none)),
            OperationInvocation(const ArchAndDive(), progression: true),
          ],
        ),
      );
      expect(
        result.warnings.where((w) => w.kind == WarningKind.archFromLine),
        isEmpty,
      );
    });
  });

  group('the archFromLine lint (user-ruled 2026-11-23)', () {
    test('a line that cannot bend warns, and is swapped as it stands', () {
      // Facing unknown: the line faces no one way along the hall.
      final line = di(['. . . . .', 'R1-A L2-B . R2-B L1-A']);
      final warnings = const ArchAndDive().lint(line).toList();
      expect(warnings.single.kind, WarningKind.archFromLine);
      expect(applyOk(const ArchAndDive(), line).toRolesNotation(), [
        'R1-A L2-B . R2-B L1-A',
        '. . . . .',
      ]);
    });

    test('two couples facing along the set raise nothing', () {
      expect(const ArchAndDive().lint(di(base)), isEmpty);
    });
  });
}

DancerId _id(String cell) => DancerId(
  cell.codeUnitAt(cell.length - 1) - 0x41,
  cell.startsWith('L') ? Role.lark : Role.robin,
);
