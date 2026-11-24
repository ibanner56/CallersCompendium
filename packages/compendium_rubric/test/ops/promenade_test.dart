import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation becket(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.becketCw);

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

OpError applyErr(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Err<Formation, OpError>>(), reason: '$op compiled');
  return (result as Err<Formation, OpError>).error;
}

void main() {
  group('Promenade across', () {
    // Partners side by side after a partner swing: A on the west side, B on
    // the east, each lark on the left of their own facing.
    final afterPartnerSwing = becket(const [
      'L1-A . . . R2-B',
      'R1-A . . . L2-B',
    ]);

    test('matches the worked example: every dancer lands diagonally '
        'across', () {
      // `docs/taxonomy.md` `promenade`: A crosses on the top row and the wheel
      // turns the couple end for end, so L1-A lands bottom east and R1-A top
      // east. B mirrors that.
      final after = applyOk(const Promenade(), afterPartnerSwing);
      expect(after.toRolesNotation(), ['L2-B . . . R1-A', 'R2-B . . . L1-A']);
    });

    test('lands exactly where a right and left through does', () {
      // The ruling, as an identity rather than a second hand-worked table.
      expect(
        applyOk(const Promenade(), afterPartnerSwing).toMatrix(),
        applyOk(const RightLeftThrough(), afterPartnerSwing).toMatrix(),
      );
    });

    test('dancers finish facing back into the set', () {
      final after = applyOk(const Promenade(), afterPartnerSwing);
      for (final row in [0, 1]) {
        expect(
          after.stateOf(after.dancerAt(Position(row, 0))!).facing,
          Facing.acrossEast,
        );
        expect(
          after.stateOf(after.dancerAt(Position(row, 4))!).facing,
          Facing.acrossWest,
        );
      }
    });

    test('neighbours promenade from where a neighbour swing leaves them', () {
      final after = applyOk(
        const Promenade(who: WhoSet.neighbors),
        becket(const ['L2-B . . . R2-B', 'R1-A . . . L1-A']),
      );
      expect(after.toRolesNotation(), ['L1-A . . . R1-A', 'R2-B . . . L2-B']);
    });

    test('the wheel sense does not change the landing', () {
      expect(
        applyOk(
          const Promenade(direction: SpinDirection.clockwise),
          afterPartnerSwing,
        ).toMatrix(),
        applyOk(const Promenade(), afterPartnerSwing).toMatrix(),
      );
    });

    test('refuses pairs that are not side by side on a side', () {
      // From the duple-improper start the partners face each other across
      // the set, so there is no couple to walk across together.
      final error = applyErr(
        const Promenade(),
        parseRolesNotation(const [
          'L2-B . . . R2-B',
          'R1-A . . . L1-A',
        ], type: FormationType.dupleImproper),
      );
      expect(error.kind, ErrorKind.whoMismatch);
    });

    test('refuses when the named pairs are not the ones side by side', () {
      // Partners stand together here; neighbours are across from each other.
      final error = applyErr(
        const Promenade(who: WhoSet.neighbors),
        afterPartnerSwing,
      );
      expect(error.kind, ErrorKind.whoMismatch);
    });

    final deferrals = {
      'a single-file promenade': const Promenade(singleFile: true),
      'where:along': const Promenade(where: 'along'),
      'a stated destination': const Promenade(
        destination: WhoSet.nextNeighbors,
      ),
    };
    for (final MapEntry(key: label, value: op) in deferrals.entries) {
      test('$label is deferred, not approximated', () {
        expect(
          applyErr(op, afterPartnerSwing).kind,
          ErrorKind.unsupportedParam,
        );
      });
    }
  });

  group('Promenade across in a longer set', () {
    test('every hands four promenades on its own', () {
      final after = applyOk(
        const Promenade(),
        becket(const [
          'L1-A . . . R2-B',
          'R1-A . . . L2-B',
          'L1-C . . . R2-D',
          'R1-C . . . L2-D',
        ]),
      );
      expect(after.toRolesNotation(), [
        'L2-B . . . R1-A',
        'R2-B . . . L1-A',
        'L2-D . . . R1-C',
        'R2-D . . . L1-C',
      ]);
    });

    test('a hands four that cannot promenade refuses the whole figure', () {
      // The lower hands four still faces across as partners, so it names the
      // band it could not read.
      final error = applyErr(
        const Promenade(),
        becket(const [
          'L1-A . . . R2-B',
          'R1-A . . . L2-B',
          'L1-C . . . R1-C',
          'R2-D . . . L2-D',
        ]),
      );
      expect(error.kind, ErrorKind.whoMismatch);
      expect(error.message, contains('rows 2-3'));
    });
  });

  group('Promenade metadata', () {
    test('stays inside its own hands four', () {
      expect(const Promenade().hands4Contribution, 0);
      expect(const Promenade().reachAfter(0), 0);
    });

    test('is not a progression by itself', () {
      expect(const Promenade().progressionEligible, isFalse);
    });

    test('names who as its dancer set, so a farther pair sizes the set', () {
      expect(const Promenade(who: WhoSet.neighbors).dancerSets, [
        WhoSet.neighbors,
      ]);
      expect(
        const Promenade(who: WhoSet.nextNeighbors).reachAfter(0),
        greaterThan(0),
      );
    });

    test('describes itself', () {
      expect(
        const Promenade().toString(),
        'promenade(partners, across, counterclockwise)',
      );
      expect(
        const Promenade(
          singleFile: true,
          destination: WhoSet.nextNeighbors,
        ).toString(),
        'promenade(partners, across, counterclockwise, singleFile, to nextNeighbors)',
      );
    });
  });

  test('each side column is read for its own pair, so a pair across the '
      'set does not hide a side pair', () {
    // Sawdust Liquor (Caller's Box #10027) after the diagonal chain to the
    // shadow. In the top hands four nobody is out, so the shadow wraps to the
    // neighbour, and L1-A would match R2-D across the set as well as R2-B
    // beside him.
    final afterChain = becket(const [
      'L1-A . . . R2-D',
      'R2-B . . . L2-B',
      'L1-C . . . R2-F',
      'R1-A . . . L2-D',
      'L1-E . . . R1-E',
      'R1-C . . . L2-F',
    ]);
    expect(
      const Promenade(who: WhoSet.shadows).checkPreconditions(afterChain),
      isNull,
    );
  });

  test('the shadow promenade remembers the pairs that danced side by side', () {
    DancerId id(String cell) => DancerId(
      cell.codeUnitAt(cell.length - 1) - 0x41,
      cell.startsWith('L') ? Role.lark : Role.robin,
    );
    final afterChain = applyOk(
      const Chain(who: WhoSet.role2s, dir: ChainDirection.leftDiagonal),
      becket(const [
        'L1-A . . . R1-A',
        'R2-B . . . L2-B',
        'L1-C . . . R1-C',
        'R2-D . . . L2-D',
        'L1-E . . . R1-E',
        'R2-F . . . L2-F',
      ]),
    );
    final after = applyOk(const Promenade(who: WhoSet.shadows), afterChain);
    // L1-A had no shadow yet: he promenaded with R2-B beside him, not with
    // R2-D across the set, who keeps the L2-B her chain gave her.
    expect(after.stateOf(id('L1-A')).shadow, id('R2-B'));
    expect(after.stateOf(id('R2-B')).shadow, id('L1-A'));
    expect(after.stateOf(id('R2-D')).shadow, id('L2-B'));
  });

  test('a shadow do-si-do remembers the pair it danced, across the set', () {
    // The same wrap band as above, with nobody there remembering a shadow:
    // do_si_do pairs first match first, so L1-A dances with R2-D across the
    // set (once around, so nobody moves), and that is what he remembers. The
    // pair remembered in the middle hands four only settles the band phase.
    DancerId id(String cell) => DancerId(
      cell.codeUnitAt(cell.length - 1) - 0x41,
      cell.startsWith('L') ? Role.lark : Role.robin,
    );
    final unremembered = becket(const [
      'L1-A . . . R2-D',
      'R2-B . . . L2-B',
      'L1-C . . . R2-F',
      'R1-A . . . L2-D',
      'L1-E . . . R1-E',
      'R1-C . . . L2-F',
    ]);
    final standing = unremembered.withUpdates({
      id('L1-C'): unremembered.stateOf(id('L1-C')).copyWith(shadow: id('R1-A')),
      id('R1-A'): unremembered.stateOf(id('R1-A')).copyWith(shadow: id('L1-C')),
    });
    final after = applyOk(const DoSiDo(who: WhoSet.shadows), standing);
    expect(after.stateOf(id('L1-A')).shadow, id('R2-D'));
    expect(after.stateOf(id('R2-B')).shadow, isNull);
  });

  test(
    'after the chain, a shadow do-si-do pairs the shadows it made first',
    () {
      // R2-D and L2-B remember each other from the chain, so they dance
      // together, and L1-A dances with R2-B beside him, as the promenade does.
      DancerId id(String cell) => DancerId(
        cell.codeUnitAt(cell.length - 1) - 0x41,
        cell.startsWith('L') ? Role.lark : Role.robin,
      );
      final afterChain = applyOk(
        const Chain(who: WhoSet.role2s, dir: ChainDirection.leftDiagonal),
        becket(const [
          'L1-A . . . R1-A',
          'R2-B . . . L2-B',
          'L1-C . . . R1-C',
          'R2-D . . . L2-D',
          'L1-E . . . R1-E',
          'R2-F . . . L2-F',
        ]),
      );
      final after = applyOk(const DoSiDo(who: WhoSet.shadows), afterChain);
      expect(after.stateOf(id('L1-A')).shadow, id('R2-B'));
      expect(after.stateOf(id('R2-B')).shadow, id('L1-A'));
      expect(after.stateOf(id('R2-D')).shadow, id('L2-B'));
    },
  );
}
