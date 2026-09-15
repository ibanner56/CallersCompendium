import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// Builds a formation from role notation, ignoring column padding.
Formation grid(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// Builds a Becket formation from role notation.
Formation becketGrid(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.becketCw);

void main() {
  group('left/right relative to facing (fundamentals.md §7)', () {
    test('left is a quarter turn counterclockwise', () {
      expect(Facing.up.turnedLeft, Facing.acrossWest);
      expect(Facing.down.turnedLeft, Facing.acrossEast);
      expect(Facing.acrossEast.turnedLeft, Facing.up);
      expect(Facing.acrossWest.turnedLeft, Facing.down);
    });

    test('right is a quarter turn clockwise', () {
      expect(Facing.up.turnedRight, Facing.acrossEast);
      expect(Facing.down.turnedRight, Facing.acrossWest);
      expect(Facing.acrossEast.turnedRight, Facing.down);
      expect(Facing.acrossWest.turnedRight, Facing.up);
    });

    test('four left turns return to the start', () {
      for (final facing in Facing.values) {
        expect(facing.turnedLeft.turnedLeft.turnedLeft.turnedLeft, facing);
      }
    });

    test('two left turns equal a reversal', () {
      for (final facing in Facing.values) {
        expect(facing.turnedLeft.turnedLeft, facing.reversed);
      }
    });

    test('flexible has no determinate left or right', () {
      expect(Facing.flexible.turnedLeft, Facing.flexible);
      expect(Facing.flexible.turnedRight, Facing.flexible);
    });
  });

  group('normalization (fundamentals.md §8)', () {
    test('along the hall, the Lark takes the column on their left', () {
      final facingDown = normalizeAlongHall(row: 0, facing: Facing.down);
      expect(facingDown.lark, const Position(0, 4));
      expect(facingDown.robin, const Position(0, 0));

      final facingUp = normalizeAlongHall(row: 1, facing: Facing.up);
      expect(facingUp.lark, const Position(1, 0));
      expect(facingUp.robin, const Position(1, 4));
    });

    test('across the set, the Lark takes the row on their left', () {
      final facingEast = normalizeAcross(
        col: 0,
        topRow: 0,
        facing: Facing.acrossEast,
      );
      expect(facingEast.lark, const Position(0, 0));
      expect(facingEast.robin, const Position(1, 0));

      final facingWest = normalizeAcross(
        col: 4,
        topRow: 0,
        facing: Facing.acrossWest,
      );
      expect(facingWest.lark, const Position(1, 4));
      expect(facingWest.robin, const Position(0, 4));
    });

    test('rejects a facing that does not match the orientation', () {
      expect(
        () => normalizeAlongHall(row: 0, facing: Facing.acrossEast),
        throwsArgumentError,
      );
      expect(
        () => normalizeAcross(col: 0, topRow: 0, facing: Facing.up),
        throwsArgumentError,
      );
      expect(
        () => normalizeAlongHall(row: 0, facing: Facing.flexible),
        throwsArgumentError,
      );
      expect(
        () => normalizeAcross(col: 0, topRow: 0, facing: Facing.flexible),
        throwsArgumentError,
      );
    });
  });

  group('couple orientation', () {
    test('duple improper couples stand along the hall', () {
      final formation = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      expect(orientationOf(formation, 0), CoupleOrientation.alongHall);
    });

    test('becket couples stand across', () {
      final formation = startingFormation(FormationType.becketCw, handsFour: 2);
      expect(orientationOf(formation, 0), CoupleOrientation.across);
    });

    test('a split couple is scattered', () {
      final formation = grid(['R1-B . . . L1-A', 'R1-A . . . L1-B']);
      expect(orientationOf(formation, 0), CoupleOrientation.scattered);
      expect(orientationOf(formation, 1), CoupleOrientation.scattered);
    });
  });

  group('hands four boundaries (fundamentals.md §10.3)', () {
    test('with nobody standing out, bands are consecutive row pairs', () {
      // §10.5 pre-progression: B#2, A#1, D#2, C#1.
      final formation = grid([
        'L2-B . . . R2-B',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'R1-C . . . L1-C',
      ]);
      expect(handsFourBands(formation), [
        (topRow: 0, bottomRow: 1),
        (topRow: 2, bottomRow: 3),
      ]);
      expect(waitingOutRows(formation), isEmpty);
    });

    test('couples standing out at both ends leave one active band', () {
      // §10.5 post-progression: B waits at the top, C at the bottom.
      final formation = markWaitingOut(
        grid([
          'R1-B . . . L1-B',
          'R1-A . . . L1-A',
          'L2-D . . . R2-D',
          'L2-C . . . R2-C',
        ]),
        rows: [0, 3],
      );
      expect(handsFourBands(formation), [(topRow: 1, bottomRow: 2)]);
      expect(waitingOutRows(formation), [0, 3]);
    });

    test('couple numbers no longer drive the grouping', () {
      // The same matrix as above, minus the waiting-out marks. Under the
      // superseded §10.3 rule the matching top couples (B#1 over A#1) read as
      // offset 1; grouping is now state-derived, so this reads as two bands.
      final formation = grid([
        'R1-B . . . L1-B',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'L2-C . . . R2-C',
      ]);
      expect(handsFourBands(formation), [
        (topRow: 0, bottomRow: 1),
        (topRow: 2, bottomRow: 3),
      ]);
    });

    test('the standard duple improper start begins at row 0', () {
      final formation = startingFormation(
        FormationType.dupleImproper,
        handsFour: 3,
      );
      expect(handsFourBands(formation).length, 3);
      expect(waitingOutRows(formation), isEmpty);
    });

    test(
      'a line of four keeps its band - an empty row is not a waiting row',
      () {
        // §8.1: one row holds a whole hands four and its partner row is empty.
        // The superseded rule could not evaluate this shape at all.
        final formation = grid(['R1-A L1-A . L2-B R2-B', '. . . . .']);
        expect(waitingOutRows(formation), isEmpty);
        expect(handsFourBands(formation), [(topRow: 0, bottomRow: 1)]);
      },
    );

    test('grouping resolves mid-figure, where the old rule could not', () {
      // The Baby Rose after op 2 (circle): row 0 holds R2-B and L1-A - two
      // different couples carrying two different numbers, so "the row's
      // number" had no referent and the superseded rule returned null.
      final formation = grid([
        'R2-B . . . L1-A',
        'L2-B . . . R1-A',
        'R2-D . . . L1-C',
        'L2-D . . . R1-C',
      ]);
      expect(handsFourBands(formation), [
        (topRow: 0, bottomRow: 1),
        (topRow: 2, bottomRow: 3),
      ]);
    });
  });

  group('hands four boundaries in becket (fundamentals.md §10.6)', () {
    test('becket groups by exactly the same rule as duple improper', () {
      final formation = becketGrid([
        'L2-B . . . R1-A',
        'R2-B . . . L1-A',
        'L2-D . . . R1-C',
        'R2-D . . . L1-C',
      ]);
      expect(handsFourBands(formation), [
        (topRow: 0, bottomRow: 1),
        (topRow: 2, bottomRow: 3),
      ]);
      expect(waitingOutRows(formation), isEmpty);
    });

    test('a couple collected into the end row waits out', () {
      // §10.6 Becket CW single-progression oracle: B has collected into row 0
      // and C into row 3, so the active hands four is A + D across rows 1-2.
      final formation = markWaitingOut(
        becketGrid([
          'R1-B . . . L1-B',
          'L2-D . . . R1-A',
          'R2-D . . . L1-A',
          'L2-C . . . R2-C',
        ]),
        rows: [0, 3],
      );
      expect(handsFourBands(formation), [(topRow: 1, bottomRow: 2)]);
      expect(waitingOutRows(formation), [0, 3]);
    });

    test('the becket start begins at row 0 at any set size', () {
      for (final handsFour in [1, 2, 3, 5]) {
        final formation = startingFormation(
          FormationType.becketCw,
          handsFour: handsFour,
        );
        expect(
          handsFourBands(formation).length,
          handsFour,
          reason: '$handsFour hands four',
        );
      }
    });

    test('grouping does not read couple numbers', () {
      // The same geometry as the start with every number flipped: grouping is
      // waiting-out-derived, so the answer must not change.
      final formation = becketGrid([
        'L1-B . . . R2-A',
        'R1-B . . . L2-A',
        'L1-D . . . R2-C',
        'R1-D . . . L2-C',
      ]);
      expect(handsFourBands(formation), [
        (topRow: 0, bottomRow: 1),
        (topRow: 2, bottomRow: 3),
      ]);
    });

    test("the judge's mid-dance state groups cleanly", () {
      // after_5_petronella. No progression has fired yet, so nobody is out and
      // all three bands are active. The superseded orientation rule returned
      // null here: couple D spans rows 0 and 2, which is not a column.
      final formation = becketGrid([
        'R2-D . . . L2-B',
        'L1-A . . . R2-B',
        'R2-F . . . L2-D',
        'L1-C . . . R1-A',
        'R1-E . . . L2-F',
        'L1-E . . . R1-C',
      ]);
      expect(handsFourBands(formation), [
        (topRow: 0, bottomRow: 1),
        (topRow: 2, bottomRow: 3),
        (topRow: 4, bottomRow: 5),
      ]);
    });
  });

  group('reading the set from the top down', () {
    test('orders duple improper couples by row', () {
      final formation = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      expect(
        [for (final c in couplesDownTheSet(formation)) c.coupleIndex],
        [0, 1, 2, 3],
      );
    });

    test('breaks becket row ties by westmost column', () {
      final formation = startingFormation(FormationType.becketCw, handsFour: 2);
      final spans = couplesDownTheSet(formation);
      // Couples B (c0) and A (c4) both start on row 0; B sorts first.
      expect([for (final c in spans) c.coupleIndex], [1, 0, 3, 2]);
      expect(spans.first.topRow, 0);
      expect(spans.first.bottomRow, 1);
    });
  });

  group('roles notation round trip', () {
    test('parses back into the formation it was rendered from', () {
      for (final type in FormationType.values) {
        final original = startingFormation(type, handsFour: 3);
        expect(
          parseRolesNotation(original.toRolesNotation(), type: type),
          original,
          reason: type.label,
        );
      }
    });

    test('tolerates the fixture spacing', () {
      final formation = parseRolesNotation(type: FormationType.dupleImproper, [
        'R1-B .  .  . L1-B',
        'R1-A .  .  . L1-A',
      ]);
      expect(formation.toMatrix()[0][0], 18);
      expect(formation.toMatrix()[0][4], 17);
    });

    test('defaults facing to flexible rather than asserting a direction', () {
      final formation = grid(['R1-A . . . L1-A', 'L2-B . . . R2-B']);
      expect(
        formation.stateOf(const DancerId(0, Role.lark)).facing,
        Facing.flexible,
      );
    });

    test('rejects malformed notation', () {
      expect(
        () => parseRolesNotation([
          'R1-A . . L1-A',
        ], type: FormationType.dupleImproper),
        throwsA(isA<RolesNotationFormatException>()),
      );
      expect(
        () => parseRolesNotation([
          'R1-A . . . X9-Q',
        ], type: FormationType.dupleImproper),
        throwsA(isA<RolesNotationFormatException>()),
      );
      expect(
        () => parseRolesNotation([
          'R1-A . . . R1-A',
        ], type: FormationType.dupleImproper),
        throwsA(isA<RolesNotationFormatException>()),
      );
      expect(
        () => parseRolesNotation([], type: FormationType.dupleImproper),
        throwsA(isA<RolesNotationFormatException>()),
      );
    });
  });
}
