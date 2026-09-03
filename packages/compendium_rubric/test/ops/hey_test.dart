import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

OpError applyErr(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Err<Formation, OpError>>(), reason: '$op passed: $result');
  return (result as Err<Formation, OpError>).error;
}

/// The standard Duple Improper hands four a hey is called from.
///
/// The Robins (`role2s`, the default `pass1`) are diagonally opposite here, so
/// they are the pair standing one on each side of the set — the centres.
const _start = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];

void main() {
  group('HeyForFour permutation', () {
    test('a half hey reverses the line: both pairs exchange', () {
      final after = applyOk(const HeyForFour(), di(_start));
      expect(after.toRolesNotation(), ['R2-B . . . L2-B', 'L1-A . . . R1-A']);
    });

    test('a full hey is the identity', () {
      final start = di(_start);
      final after = applyOk(const HeyForFour(length: HeyLength.full), start);
      expect(after.toMatrix(), start.toMatrix());
    });

    test('two half heys compose to a full hey', () {
      final start = di(_start);
      const half = HeyForFour();
      expect(applyOk(half, applyOk(half, start)).toMatrix(), start.toMatrix());
    });

    test('the rule is state-dependent, not a fixed same-role swap', () {
      // Same figure, a rank-mate pair named as the centres. The `ones` are
      // partners across a row here, so reversing the line exchanges columns
      // within each rank rather than across the diagonal. A hard-coded Duple
      // Improper permutation could not produce this.
      final after = applyOk(const HeyForFour(pass1: WhoSet.ones), di(_start));
      expect(after.toRolesNotation(), ['L1-A . . . R1-A', 'R2-B . . . L2-B']);
    });

    test('runs in every hands four of a longer set', () {
      final after = applyOk(
        const HeyForFour(),
        parseRolesNotation(const [
          'R1-A . . . L1-A',
          'L2-B . . . R2-B',
          'R1-C . . . L1-C',
          'L2-D . . . R2-D',
        ], type: FormationType.dupleImproper),
      );
      expect(after.toRolesNotation(), [
        'R2-B . . . L2-B',
        'L1-A . . . R1-A',
        'R2-D . . . L2-D',
        'L1-C . . . R1-C',
      ]);
    });

    test('dancers finish flexible, for the next figure to resolve', () {
      final after = applyOk(const HeyForFour(), di(_start));
      for (final state in after.dancers.values) {
        expect(state.facing, Facing.flexible);
      }
    });
  });

  group('HeyForFour ricochets', () {
    test('rico1 suppresses the centres, leaving the ends to exchange', () {
      final after = applyOk(const HeyForFour(rico1: true), di(_start));
      expect(after.toRolesNotation(), ['R1-A . . . L2-B', 'L1-A . . . R2-B']);
    });

    test('rico2 suppresses the ends, leaving the centres to exchange', () {
      final after = applyOk(const HeyForFour(rico2: true), di(_start));
      expect(after.toRolesNotation(), ['R2-B . . . L1-A', 'L2-B . . . R1-A']);
    });

    test('rico1 and rico2 together leave everybody at home', () {
      final start = di(_start);
      final after = applyOk(const HeyForFour(rico1: true, rico2: true), start);
      expect(after.toMatrix(), start.toMatrix());
    });

    test('which pair a ricochet suppresses follows pass1, not the role', () {
      // Naming the Larks as the centres moves the *first* centre meeting onto
      // them, so rico1 now suppresses the pair that rico2 suppressed above.
      final after = applyOk(
        const HeyForFour(pass1: WhoSet.role1s, rico1: true),
        di(_start),
      );
      expect(after.toRolesNotation(), ['R2-B . . . L1-A', 'L2-B . . . R1-A']);
    });

    test('a full hey with one suppressed meeting leaves that pair swapped', () {
      // Centres meet twice; suppressing one leaves an odd number of exchanges.
      final after = applyOk(
        const HeyForFour(length: HeyLength.full, rico1: true),
        di(_start),
      );
      expect(after.toRolesNotation(), ['R2-B . . . L1-A', 'L2-B . . . R1-A']);
    });

    test('a full hey with both of a pair suppressed is the identity', () {
      final start = di(_start);
      final after = applyOk(
        const HeyForFour(length: HeyLength.full, rico1: true, rico3: true),
        start,
      );
      expect(after.toMatrix(), start.toMatrix());
    });

    test('the end pair carry the same parity, on rico2 and rico4', () {
      final start = di(_start);
      expect(
        applyOk(
          const HeyForFour(length: HeyLength.full, rico2: true),
          start,
        ).toRolesNotation(),
        ['R1-A . . . L2-B', 'L1-A . . . R2-B'],
      );
      expect(
        applyOk(
          const HeyForFour(length: HeyLength.full, rico2: true, rico4: true),
          start,
        ).toMatrix(),
        start.toMatrix(),
      );
    });

    test('rico3 has no meeting to name below a full hey', () {
      final error = applyErr(const HeyForFour(rico3: true), di(_start));
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.message, contains('rico3'));
    });

    test('rico4 has no meeting to name below a full hey', () {
      final error = applyErr(const HeyForFour(rico4: true), di(_start));
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.message, contains('rico4'));
    });
  });

  group('HeyForFour refusals', () {
    test('the partial lengths are deferred, not approximated', () {
      for (final length in [
        HeyLength.lessThanHalf,
        HeyLength.betweenHalfAndFull,
      ]) {
        final error = applyErr(HeyForFour(length: length), di(_start));
        expect(error.kind, ErrorKind.unsupportedParam, reason: length.key);
        expect(error.message, contains(length.key));
      }
    });

    test('dir beyond across is deferred behind the diagonal figures', () {
      for (final dir in [
        Direction.along,
        Direction.leftDiagonal,
        Direction.rightDiagonal,
      ]) {
        final error = applyErr(HeyForFour(dir: dir), di(_start));
        expect(error.kind, ErrorKind.unsupportedParam, reason: dir.key);
      }
    });

    test('a pass1 naming more than one pair is unresolvable', () {
      final error = applyErr(
        const HeyForFour(pass1: WhoSet.partners),
        di(_start),
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('2 pairs'));
    });

    test('centres standing in the same line have no centre to meet in', () {
      // Duple *proper*: both Robins are in the east column, so the pair named
      // cannot form the middle of an across-the-set line of four.
      final error = applyErr(
        const HeyForFour(),
        di(const ['L1-A . . . R1-A', 'L2-B . . . R2-B']),
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('same line'));
    });

    test('one same-side pair names only half a side pass', () {
      // Duple *proper* again, but asked for a full hey so the side-opening
      // deferral cannot be what answers. Both Robins stand east with nobody
      // named opposite them, so neither reading of the opening pass applies.
      final error = applyErr(
        const HeyForFour(length: HeyLength.full),
        di(const ['L1-A . . . R1-A', 'L2-B . . . R2-B']),
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('nobody named opposite'));
    });
  });

  group('HeyForFour pass2 anchor', () {
    test('a pass2 that names the derived side pass is silent', () {
      // The Robins meet in the centre and cross, so each comes out beside the
      // Lark who was standing on the far side -- and in Duple Improper the
      // dancer across the set is the partner. The second pass is a partner
      // pass, and naming it as one asserts nothing new.
      const op = HeyForFour(pass2: WhoSet.partners);
      expect(op.lint(di(_start)), isEmpty);
    });

    test('naming the ends pair instead of the side pass warns', () {
      // `role1s` is the pair standing at the ends, which is what this anchor
      // used to be read as. It is not who dances the second pass: the passes
      // alternate centre and side, and the side pass crosses the line rather
      // than joining the two ends to each other.
      const op = HeyForFour(pass2: WhoSet.role1s);
      final start = di(_start);
      final warnings = op.lint(start).toList();
      expect(warnings, hasLength(1));
      expect(warnings.single.kind, WarningKind.anchorMismatch);
      // The anchor corroborates; it never selects. The permutation is
      // unchanged by the contradiction.
      expect(applyOk(op, start).toRolesNotation(), [
        'R2-B . . . L2-B',
        'L1-A . . . R1-A',
      ]);
    });

    test('an absent pass2 asserts nothing', () {
      expect(const HeyForFour().lint(di(_start)), isEmpty);
    });

    test('a pass2 on a formation the hey refuses does not also warn', () {
      const op = HeyForFour(pass2: WhoSet.partners);
      expect(
        op.lint(di(const ['L1-A . . . R1-A', 'L2-B . . . R2-B'])),
        isEmpty,
      );
    });
  });

  group('HeyForFour metadata', () {
    test('may carry the progression flag', () {
      expect(const HeyForFour().progressionEligible, isTrue);
    });

    test('stays inside its own hands four', () {
      expect(const HeyForFour().hands4Contribution, 0);
    });

    test('names pass1 as its dancer set', () {
      expect(const HeyForFour().dancerSets, [WhoSet.role2s]);
    });

    test('describes itself', () {
      expect(const HeyForFour().toString(), 'hey(role2s first, half, across)');
    });

    test('HeyLength round-trips its wire keys', () {
      for (final length in HeyLength.values) {
        expect(HeyLength.fromKey(length.key), length);
      }
      expect(HeyLength.fromKey('sideways'), isNull);
    });
  });

  group('HeyForFour opening on the side', () {
    // The Carousel (Caller's Box 10324) reaches its hey through a Robins'
    // allemande left 1½, which swaps a diagonal and leaves each couple standing
    // together on one side of the set. Its record calls the hey
    // `pass1: partners, pass2: role1s` — and here the partners are exactly the
    // two same-side pairs, while the Larks are the pair standing across. The
    // record and the floor agree, which is what identifies the opening pass as
    // a side pass rather than a centre one.
    const carousel = ['R2-B . . . L1-A', 'L2-B . . . R1-A'];

    test('partners stand along the sides here, and the Larks across', () {
      final start = di(carousel);
      // Guards the premise the rest of this group rests on: if this state ever
      // stops being side-on, the tests below would pass for the wrong reason.
      int col(int couple, Role role) =>
          start.stateOf(DancerId(couple, role)).position.col;
      expect(
        col(0, Role.robin),
        col(0, Role.lark),
        reason: 'the A partners share a side',
      );
      expect(
        col(1, Role.robin),
        col(1, Role.lark),
        reason: 'the B partners share a side',
      );
      expect(
        col(0, Role.lark),
        isNot(col(1, Role.lark)),
        reason: 'the Larks stand across the set',
      );
    });

    test('a full hey opening on the side is still the identity', () {
      final start = di(carousel);
      const hey = HeyForFour(
        pass1: WhoSet.partners,
        pass2: WhoSet.role1s,
        length: HeyLength.full,
      );
      expect(applyOk(hey, start).toMatrix(), start.toMatrix());
    });

    test('pass2 selects the centres, so naming the wrong pair is refused', () {
      const hey = HeyForFour(
        pass1: WhoSet.partners,
        pass2: WhoSet.partners,
        length: HeyLength.full,
      );
      final error = applyErr(hey, di(carousel));
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('across the set'));
    });

    test('without pass2 there is nothing to name the centre pass', () {
      const hey = HeyForFour(pass1: WhoSet.partners, length: HeyLength.full);
      final error = applyErr(hey, di(carousel));
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('pass2 is needed'));
    });

    test('a side-opening hey raises no anchorMismatch on its own pass2', () {
      const hey = HeyForFour(
        pass1: WhoSet.partners,
        pass2: WhoSet.role1s,
        length: HeyLength.full,
      );
      expect(hey.lint(di(carousel)), isEmpty);
    });

    test('a half hey opening on the side is deferred, not guessed', () {
      const hey = HeyForFour(pass1: WhoSet.partners, pass2: WhoSet.role1s);
      final error = applyErr(hey, di(carousel));
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.message, contains('half way'));
    });

    test('ricochets on a side-opening hey are deferred', () {
      const hey = HeyForFour(
        pass1: WhoSet.partners,
        pass2: WhoSet.role1s,
        length: HeyLength.full,
        rico1: true,
      );
      final error = applyErr(hey, di(carousel));
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.message, contains('centre meetings'));
    });

    test('a centre-opening hey is untouched by any of this', () {
      final start = di(_start);
      final after = applyOk(const HeyForFour(), start);
      expect(after.toRolesNotation(), ['R2-B . . . L2-B', 'L1-A . . . R1-A']);
    });
  });
}
