import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

void main() {
  group('dancer encoding (fundamentals.md §5)', () {
    test('encodes the worked-example values', () {
      // From docs/fundamentals.md §11 and test/golden/the_baby_rose.json.
      expect(encodeDancer(const DancerId(0, Role.lark), CoupleNumber.one), 9);
      expect(encodeDancer(const DancerId(0, Role.robin), CoupleNumber.one), 10);
      expect(encodeDancer(const DancerId(1, Role.lark), CoupleNumber.two), 21);
      expect(encodeDancer(const DancerId(1, Role.robin), CoupleNumber.two), 22);
      expect(encodeDancer(const DancerId(2, Role.robin), CoupleNumber.one), 34);
      expect(encodeDancer(const DancerId(3, Role.lark), CoupleNumber.two), 69);
      expect(encodeDancer(const DancerId(3, Role.robin), CoupleNumber.two), 70);
    });

    test('couple contribution is stable regardless of set size', () {
      const expected = [8, 16, 32, 64, 128, 256];
      for (var i = 0; i < expected.length; i++) {
        expect(DancerId(i, Role.lark).coupleBits, expected[i]);
      }
    });

    test('round-trips every identity/number combination', () {
      for (var couple = 0; couple < 6; couple++) {
        for (final role in Role.values) {
          for (final number in CoupleNumber.values) {
            final id = DancerId(couple, role);
            final decoded = decodeDancer(encodeDancer(id, number));
            expect(decoded, isNotNull);
            expect(decoded!.id, id);
            expect(decoded.number, number);
          }
        }
      }
    });

    test('rejects the empty cell and malformed values', () {
      expect(decodeDancer(0), isNull);
      expect(decodeDancer(8), isNull, reason: 'no role bits');
      expect(decodeDancer(3), isNull, reason: 'both role bits set');
      expect(decodeDancer(25), isNull, reason: 'couple field not one-hot');
    });

    test('couple letters follow the one-hot index', () {
      expect(const DancerId(0, Role.lark).coupleLetter, 'A');
      expect(const DancerId(5, Role.robin).coupleLetter, 'F');
    });
  });

  group('facing (fundamentals.md §6)', () {
    test('reverses along both axes', () {
      expect(Facing.up.reversed, Facing.down);
      expect(Facing.down.reversed, Facing.up);
      expect(Facing.acrossEast.reversed, Facing.acrossWest);
      expect(Facing.acrossWest.reversed, Facing.acrossEast);
    });

    test('flexible reverses to itself and is not concrete', () {
      expect(Facing.flexible.reversed, Facing.flexible);
      expect(Facing.flexible.isConcrete, isFalse);
      expect(Facing.flexible.isAlongHall, isFalse);
      expect(Facing.flexible.isAcross, isFalse);
    });
  });

  group('duple improper start (fundamentals.md §9, §11)', () {
    final formation = startingFormation(
      FormationType.dupleImproper,
      handsFour: 2,
    );

    test('matches the worked-example decimal matrix', () {
      expect(formation.toMatrix(), [
        [10, 0, 0, 0, 9],
        [21, 0, 0, 0, 22],
        [34, 0, 0, 0, 33],
        [69, 0, 0, 0, 70],
      ]);
    });

    test('matches the golden fixture role notation', () {
      expect(formation.toRolesNotation(), [
        'R1-A . . . L1-A',
        'L2-B . . . R2-B',
        'R1-C . . . L1-C',
        'L2-D . . . R2-D',
      ]);
    });

    test('1s face down and 2s face up', () {
      expect(
        formation.stateOf(const DancerId(0, Role.lark)).facing,
        Facing.down,
      );
      expect(formation.stateOf(const DancerId(1, Role.lark)).facing, Facing.up);
    });

    test('is sized at two rows per hands four', () {
      expect(formation.rowCount, 4);
      expect(formation.handsFourCount, 2);
      expect(
        startingFormation(FormationType.dupleImproper, handsFour: 5).rowCount,
        10,
      );
    });
  });

  group('becket start (fundamentals.md §9, §10.6)', () {
    test('matches the §10.6 worked reference at 2 hands four', () {
      final formation = startingFormation(FormationType.becketCw, handsFour: 2);
      expect(formation.toRolesNotation(), [
        'L2-B . . . R1-A',
        'R2-B . . . L1-A',
        'L2-D . . . R1-C',
        'R2-D . . . L1-C',
      ]);
    });

    test('matches the The Judge fixture at 3 hands four', () {
      final formation = startingFormation(FormationType.becketCw, handsFour: 3);
      expect(formation.toRolesNotation(), [
        'L2-B . . . R1-A',
        'R2-B . . . L1-A',
        'L2-D . . . R1-C',
        'R2-D . . . L1-C',
        'L2-F . . . R1-E',
        'R2-F . . . L1-E',
      ]);
    });

    test('CW and CCW share a starting matrix', () {
      expect(
        startingFormation(FormationType.becketCw, handsFour: 2),
        startingFormation(FormationType.becketCcw, handsFour: 2),
      );
    });

    test('both lines face in', () {
      final formation = startingFormation(FormationType.becketCw, handsFour: 2);
      // c0 is the 2s line facing east; c4 is the 1s line facing west.
      expect(
        formation.stateOf(const DancerId(1, Role.lark)).facing,
        Facing.acrossEast,
      );
      expect(
        formation.stateOf(const DancerId(0, Role.lark)).facing,
        Facing.acrossWest,
      );
    });

    test('partners share a column', () {
      final formation = startingFormation(FormationType.becketCw, handsFour: 2);
      for (var couple = 0; couple < 4; couple++) {
        expect(
          formation.stateOf(DancerId(couple, Role.lark)).col,
          formation.stateOf(DancerId(couple, Role.robin)).col,
          reason: 'couple $couple should be stacked in one column',
        );
      }
    });
  });

  group('formation type resolution', () {
    test('accepts the JSON keys used by the golden fixtures', () {
      expect(
        FormationType.fromKey('duple_improper'),
        FormationType.dupleImproper,
      );
      expect(FormationType.fromKey('becket_cw'), FormationType.becketCw);
    });

    test('accepts real-world label spellings', () {
      expect(FormationType.fromKey('Becket CW'), FormationType.becketCw);
      expect(
        FormationType.fromKey('dupleImproper'),
        FormationType.dupleImproper,
      );
      expect(
        FormationType.fromKey('Duple Minor - Improper'),
        FormationType.dupleImproper,
      );
    });

    test('returns null for an unknown formation', () {
      expect(FormationType.fromKey('four_face_four'), isNull);
    });
  });

  group('formation projection', () {
    final formation = startingFormation(
      FormationType.dupleImproper,
      handsFour: 2,
    );

    test('rejects a cell collision', () {
      final occupied = formation.stateOf(const DancerId(0, Role.lark));
      expect(
        () => formation.withUpdates({
          const DancerId(0, Role.robin): formation
              .stateOf(const DancerId(0, Role.robin))
              .movedTo(occupied.position),
        }),
        throwsA(isA<FormationProjectionError>()),
      );
    });

    test('rejects a dancer outside the matrix', () {
      expect(
        () => formation.withUpdates({
          const DancerId(0, Role.lark): formation
              .stateOf(const DancerId(0, Role.lark))
              .movedTo(const Position(9, 0)),
        }),
        throwsA(isA<FormationProjectionError>()),
      );
    });

    test('rejects updating a dancer who is not in the set', () {
      expect(
        () => formation.withUpdates({
          const DancerId(7, Role.lark): formation.stateOf(
            const DancerId(0, Role.lark),
          ),
        }),
        throwsA(isA<FormationProjectionError>()),
      );
    });

    test('equality ignores facing', () {
      final allFlexible = formation.mapDancers(
        (_, state) => state.copyWith(facing: Facing.flexible),
      );
      expect(allFlexible, formation);
      expect(allFlexible.hashCode, formation.hashCode);
    });

    test('equality is sensitive to position', () {
      final moved = formation.withUpdates({
        const DancerId(0, Role.lark): formation
            .stateOf(const DancerId(0, Role.lark))
            .movedTo(const Position(0, 2)),
      });
      expect(moved, isNot(formation));
    });

    test('equality is sensitive to couple number', () {
      final flipped = formation.withUpdates({
        for (final role in Role.values)
          DancerId(0, role): formation
              .stateOf(DancerId(0, role))
              .copyWith(number: CoupleNumber.two),
      });
      expect(flipped, isNot(formation));
    });

    test('locates dancers by cell, row, and column', () {
      expect(
        formation.dancerAt(const Position(0, 0)),
        const DancerId(0, Role.robin),
      );
      expect(formation.dancerAt(const Position(0, 2)), isNull);
      expect(formation.dancersInRow(1), [
        const DancerId(1, Role.lark),
        const DancerId(1, Role.robin),
      ]);
      expect(formation.dancersInColumn(4).length, 4);
    });

    test('withUpdates leaves the original untouched', () {
      final before = formation.toMatrix();
      formation.withUpdates({
        const DancerId(0, Role.lark): formation
            .stateOf(const DancerId(0, Role.lark))
            .movedTo(const Position(0, 2)),
      });
      expect(formation.toMatrix(), before);
    });

    test('renders all three views', () {
      final rendered = formation.render();
      expect(rendered, contains('decimal:'));
      expect(rendered, contains('R1-A'));
      expect(rendered, contains('down'));
    });
  });
}
