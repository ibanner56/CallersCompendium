import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// The base input every worked `swing` / `do_si_do` example in
/// `docs/taxonomy.md` is stated against.
Formation base() => di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']);

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

void main() {
  group('Swing (where: sides) — the taxonomy worked examples', () {
    // Base input [[R1-A,0,0,0,L1-A],[L2-B,0,0,0,R2-B]] with who:neighbor.
    // Column-mates here are neighbours, so who:neighbors is the passing case.
    const who = WhoSet.neighbors;

    test('face:in stacks each pair in its own column, facing the set', () {
      final after = applyOk(
        const Swing(who: who, face: FaceDirection.towardSet),
        base(),
      );
      expect(after.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
    });

    test('face:out is the base input, facing away from the set', () {
      final after = applyOk(
        const Swing(who: who, face: FaceDirection.awayFromSet),
        base(),
      );
      expect(after.toRolesNotation(), ['R1-A . . . L1-A', 'L2-B . . . R2-B']);
    });

    test('face:down collapses to a line of four in the top row', () {
      final after = applyOk(
        const Swing(who: who, face: FaceDirection.down),
        base(),
      );
      expect(after.toRolesNotation(), ['R1-A L2-B . R2-B L1-A', '. . . . .']);
    });

    test('face:up collapses to a line of four in the bottom row', () {
      final after = applyOk(
        const Swing(who: who, face: FaceDirection.up),
        base(),
      );
      expect(after.toRolesNotation(), ['. . . . .', 'L2-B R1-A . L1-A R2-B']);
    });

    test('every swinger finishes on the stated facing', () {
      final after = applyOk(
        const Swing(who: who, face: FaceDirection.down),
        base(),
      );
      for (final state in after.dancers.values) {
        expect(state.facing, Facing.down);
      }
    });

    test('face:in turns each side inward, not to a common direction', () {
      final after = applyOk(
        const Swing(who: who, face: FaceDirection.towardSet),
        base(),
      );
      expect(
        after.stateOf(after.dancerAt(const Position(0, 0))!).facing,
        Facing.acrossEast,
      );
      expect(
        after.stateOf(after.dancerAt(const Position(0, 4))!).facing,
        Facing.acrossWest,
      );
    });
  });

  group('Swing preconditions', () {
    test('who is validated against whoever is physically in position', () {
      // Column-mates in the DI start are neighbours, so partners must fail.
      final result = const Swing(who: WhoSet.partners).apply(base());
      expect(result, isA<Err<Formation, OpError>>());
      expect(
        (result as Err<Formation, OpError>).error.kind,
        ErrorKind.whoMismatch,
      );
    });

    test(
      'where:center is reported as unsupported rather than approximated',
      () {
        final result = const Swing(
          who: WhoSet.neighbors,
          where: SwingWhere.center,
        ).apply(base());
        expect(
          (result as Err<Formation, OpError>).error.kind,
          ErrorKind.unsupportedParam,
        );
      },
    );

    test('a swing normalizes, discarding the pair\'s starting arrangement', () {
      // Swap the west column so the robin starts on top, then swing face:in.
      // The result must match the un-swapped case exactly.
      final swapped = di(const ['L2-B . . . L1-A', 'R1-A . . . R2-B']);
      const op = Swing(who: WhoSet.neighbors, face: FaceDirection.towardSet);
      expect(
        applyOk(op, swapped).toRolesNotation()[0].split(' ').first,
        applyOk(op, base()).toRolesNotation()[0].split(' ').first,
      );
    });
  });

  group('DoSiDo', () {
    test('a whole circling is the identity', () {
      for (final amount in [1.0, 2.0]) {
        final after = applyOk(
          DoSiDo(who: WhoSet.partners, circling: amount),
          base(),
        );
        expect(after.toMatrix(), base().toMatrix(), reason: 'circling=$amount');
      }
    });

    test('half circling swaps neighbours vertically', () {
      final after = applyOk(
        const DoSiDo(who: WhoSet.neighbors, circling: 1.5),
        base(),
      );
      expect(after.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
    });

    test('half circling swaps partners across columns', () {
      final after = applyOk(
        const DoSiDo(who: WhoSet.partners, circling: 1.5),
        base(),
      );
      expect(after.toRolesNotation(), ['L1-A . . . R1-A', 'R2-B . . . L2-B']);
    });

    test('facing is preserved, unlike a swing', () {
      final before = base();
      final after = applyOk(
        const DoSiDo(who: WhoSet.partners, circling: 1.5),
        before,
      );
      for (final id in before.dancers.keys) {
        expect(
          after.stateOf(id).facing,
          before.stateOf(id).facing,
          reason: '$id',
        );
      }
    });

    test('quarter circling is deferred, not approximated', () {
      final result = const DoSiDo(
        who: WhoSet.partners,
        circling: 0.25,
      ).apply(base());
      expect(
        (result as Err<Formation, OpError>).error.kind,
        ErrorKind.unsupportedParam,
      );
    });
  });

  group('who vocabulary', () {
    test('canonical keys and legacy aliases both resolve', () {
      expect(WhoSet.fromKey('neighbors'), WhoSet.neighbors);
      expect(WhoSet.fromKey('neighbor'), WhoSet.neighbors);
      expect(WhoSet.fromKey('larks'), WhoSet.role1s);
      expect(WhoSet.fromKey('role2s'), WhoSet.role2s);
      expect(WhoSet.fromKey('nope'), isNull);
    });

    test('couple numbers and roles are distinct concepts', () {
      final f = base();
      final lark1 = f.dancerAt(const Position(0, 4))!;
      final lark2 = f.dancerAt(const Position(1, 0))!;
      // Both larks, but not both ones.
      expect(whoMatches(f, lark1, lark2, WhoSet.role1s), isTrue);
      expect(whoMatches(f, lark1, lark2, WhoSet.ones), isFalse);
    });
  });

  group('"Ones swing" in their own row (user-ruled 2026-11-23)', () {
    // The ones stand across the set from each other in one row; they swing
    // there and finish facing down the hall, toward the twos.
    test('the ones finish facing down, lark on the east line', () {
      // Crossed over and facing in, so the swing has to move them.
      final after = applyOk(
        const Swing(who: WhoSet.ones),
        di(const ['L1-A . . . R1-A', 'L2-B . . . R2-B']),
      );
      expect(after.toRolesNotation(), ['R1-A . . . L1-A', 'L2-B . . . R2-B']);
      for (final id in after.dancersInRow(0)) {
        expect(after.stateOf(id).facing, Facing.down, reason: '$id');
      }
    });

    test('ones in the bottom row still face down, toward new twos', () {
      final after = applyOk(
        const Swing(who: WhoSet.ones),
        di(const ['L2-B . . . R2-B', 'L1-A . . . R1-A']),
      );
      expect(after.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
      for (final id in after.dancersInRow(1)) {
        expect(after.stateOf(id).facing, Facing.down, reason: '$id');
      }
    });

    test('a stated face: up is honoured', () {
      final after = applyOk(
        const Swing(who: WhoSet.ones, face: FaceDirection.up),
        di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']),
      );
      expect(after.toRolesNotation(), ['L1-A . . . R1-A', 'L2-B . . . R2-B']);
      for (final id in after.dancersInRow(0)) {
        expect(after.stateOf(id).facing, Facing.up, reason: '$id');
      }
    });

    test('ones not sharing a row are still refused', () {
      final result = const Swing(who: WhoSet.ones).apply(
        base().withUpdates({
          for (final entry in base().dancers.entries)
            entry.key: entry.value.copyWith(
              position: Position(
                entry.key.role == Role.lark ? 0 : 1,
                entry.value.col,
              ),
            ),
        }),
      );
      expect(
        (result as Err<Formation, OpError>).error.kind,
        ErrorKind.whoMismatch,
      );
    });

    test('face: out for ones in their own row is deferred', () {
      final result = const Swing(
        who: WhoSet.ones,
        face: FaceDirection.awayFromSet,
      ).apply(di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']));
      expect(
        (result as Err<Formation, OpError>).error.kind,
        ErrorKind.unsupportedParam,
      );
    });

    test('ones at the ends of a line of four do not swing in that row', () {
      // The ones stand at c0 and c4 of a line, facing in. A ones-in-a-row
      // swing would turn them down the hall; here nobody moves or turns.
      final line = di(const ['R1-A L2-B . R2-B L1-A', '. . . . .']);
      final after = applyOk(const Swing(who: WhoSet.ones), line);
      for (final id in line.dancers.keys) {
        expect(after.stateOf(id), line.stateOf(id), reason: '$id');
      }
    });

    test(
      'a hands four with ones in both rows is not a ones-in-a-row swing',
      () {
        // Synthetic: every dancer numbered one. The side-column swing then
        // runs, so the dancers are paired by column, not by row.
        final set = di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']);
        final allOnes = set.withUpdates({
          for (final entry in set.dancers.entries)
            entry.key: entry.value.copyWith(number: CoupleNumber.one),
        });
        final after = applyOk(const Swing(who: WhoSet.ones), allOnes);
        for (final id in after.dancers.keys) {
          expect(after.stateOf(id).facing.isAcross, isTrue, reason: '$id');
        }
      },
    );

    test('a couple standing out does not swing', () {
      final set = di(const [
        'L1-A . . . R1-A',
        'L1-C . . . R1-C',
        'L2-B . . . R2-B',
        'L2-D . . . R2-D',
      ]);
      final out = set.withUpdates({
        for (final id in set.dancersInRow(3))
          id: set.stateOf(id).copyWith(waitingOut: true),
        for (final id in set.dancersInRow(0))
          id: set.stateOf(id).copyWith(waitingOut: true),
      });
      final after = applyOk(const Swing(who: WhoSet.ones), out);
      for (final row in [0, 3]) {
        for (final id in out.dancersInRow(row)) {
          expect(after.stateOf(id), out.stateOf(id), reason: '$id');
        }
      }
      // The ones of the one active hands four did swing.
      expect(after.toRolesNotation()[1], 'R1-C . . . L1-C');
    });
  });

  group('"Twos swing" in their own row (user-ruled 2026-11-23)', () {
    // The twos swing in their row and finish facing up, toward the ones.
    test('the twos finish facing up, lark on the west line', () {
      final after = applyOk(
        const Swing(who: WhoSet.twos),
        di(const ['R1-A . . . L1-A', 'R2-B . . . L2-B']),
      );
      expect(after.toRolesNotation(), ['R1-A . . . L1-A', 'L2-B . . . R2-B']);
      for (final id in after.dancersInRow(1)) {
        expect(after.stateOf(id).facing, Facing.up, reason: '$id');
      }
    });

    test('twos in the top row still face up, toward new ones', () {
      final after = applyOk(
        const Swing(who: WhoSet.twos),
        di(const ['R2-B . . . L2-B', 'R1-A . . . L1-A']),
      );
      expect(after.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
      for (final id in after.dancersInRow(0)) {
        expect(after.stateOf(id).facing, Facing.up, reason: '$id');
      }
    });

    test('a stated face: down is honoured', () {
      final after = applyOk(
        const Swing(who: WhoSet.twos, face: FaceDirection.down),
        di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']),
      );
      expect(after.toRolesNotation(), ['R1-A . . . L1-A', 'R2-B . . . L2-B']);
    });

    test('twos at the ends of a line of four do not swing in that row', () {
      final line = di(const ['R2-B L1-A . R1-A L2-B', '. . . . .']);
      final after = applyOk(const Swing(who: WhoSet.twos), line);
      for (final id in line.dancers.keys) {
        expect(after.stateOf(id), line.stateOf(id), reason: '$id');
      }
    });

    test('face: out for twos in their own row is deferred', () {
      final result = const Swing(
        who: WhoSet.twos,
        face: FaceDirection.awayFromSet,
      ).apply(di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']));
      expect(
        (result as Err<Formation, OpError>).error.kind,
        ErrorKind.unsupportedParam,
      );
    });
  });
}
