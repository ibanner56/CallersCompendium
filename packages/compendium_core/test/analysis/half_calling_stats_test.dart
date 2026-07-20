import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  var seq = 0;
  setUp(() => seq = 0);

  ProgramSlot danceSlot(
    String danceId, {
    int? position,
    DateTime? performedAt,
  }) => ProgramSlot(
    id: 's${seq++}',
    position: position ?? seq,
    danceId: danceId,
    performedAt: performedAt,
  );

  ProgramSlot textSlot(String text, {int? position}) =>
      ProgramSlot(id: 's${seq++}', position: position ?? seq, text: text);

  ProgramSlot breakSlot({int? position}) =>
      textSlot(Program.breakSlotText, position: position);

  group('computeHalfCallingStats — half attribution', () {
    test('empty input yields the empty stats', () {
      expect(
        computeHalfCallingStats(danceId: 'd1', programs: const []),
        HalfCallingStats.empty,
      );
    });

    test('no break in a program contributes nothing', () {
      final slots = [
        danceSlot('d1', position: 0),
        danceSlot('d2', position: 1),
        danceSlot('d1', position: 2),
      ];
      final stats = computeHalfCallingStats(danceId: 'd1', programs: [slots]);
      expect(stats, HalfCallingStats.empty);
      expect(stats.hasAny, isFalse);
    });

    test('counts first- and second-half occurrences per slot', () {
      // d1 appears once before the break (first half) and twice after
      // (second half).
      final slots = [
        danceSlot('d1', position: 0),
        danceSlot('d2', position: 1),
        breakSlot(position: 2),
        danceSlot('d1', position: 3),
        danceSlot('d3', position: 4),
        danceSlot('d1', position: 5),
      ];
      final stats = computeHalfCallingStats(danceId: 'd1', programs: [slots]);
      expect(stats.firstHalfCount, 1);
      expect(stats.secondHalfCount, 2);
      // First dance of first half is d1 → opener.
      expect(stats.openedFirstHalfCount, 1);
      // Last dance of second half is d1 (position 5) → closer.
      expect(stats.closedSecondHalfCount, 1);
      expect(stats.hasAny, isTrue);
    });

    test('opener is the first DANCE slot, not a leading free-text slot', () {
      final slots = [
        textSlot('Welcome', position: 0),
        danceSlot('d1', position: 1),
        breakSlot(position: 2),
        danceSlot('d2', position: 3),
      ];
      final stats = computeHalfCallingStats(danceId: 'd1', programs: [slots]);
      expect(stats.firstHalfCount, 1);
      expect(stats.openedFirstHalfCount, 1);
    });

    test('closer is the last DANCE slot; a trailing waltz note does not rob '
        'the dance of the closer position', () {
      final slots = [
        danceSlot('d1', position: 0),
        breakSlot(position: 1),
        danceSlot('d2', position: 2),
        danceSlot('d1', position: 3),
        textSlot('Waltz', position: 4),
      ];
      final stats = computeHalfCallingStats(danceId: 'd1', programs: [slots]);
      expect(stats.secondHalfCount, 1);
      expect(stats.closedSecondHalfCount, 1);
    });

    test('non-target dance as closer does not credit the target', () {
      final slots = [
        danceSlot('d1', position: 0),
        breakSlot(position: 1),
        danceSlot('d1', position: 2),
        danceSlot('d2', position: 3),
      ];
      final stats = computeHalfCallingStats(danceId: 'd1', programs: [slots]);
      expect(stats.secondHalfCount, 1);
      // d2 is the last dance of the 2nd half, so d1 gets no closer credit.
      expect(stats.closedSecondHalfCount, 0);
    });

    test('the break slot itself is neither half', () {
      // Target dance sitting exactly at the break position never happens (a
      // break slot has no danceId), but a break-adjacent dance is attributed
      // to the correct half.
      final slots = [
        danceSlot('d1', position: 0),
        breakSlot(position: 1),
        danceSlot('d1', position: 2),
      ];
      final stats = computeHalfCallingStats(danceId: 'd1', programs: [slots]);
      expect(stats.firstHalfCount, 1);
      expect(stats.secondHalfCount, 1);
    });

    test('multiple breaks — first break defines the halves', () {
      final slots = [
        danceSlot('d1', position: 0),
        breakSlot(position: 1),
        danceSlot('d1', position: 2),
        breakSlot(position: 3),
        danceSlot('d1', position: 4),
      ];
      final stats = computeHalfCallingStats(danceId: 'd1', programs: [slots]);
      // Before first break: 1st half (1). After first break: 2nd half — but the
      // second break slot classifies as null, so only the dance slots at
      // positions 2 and 4 count as second half.
      expect(stats.firstHalfCount, 1);
      expect(stats.secondHalfCount, 2);
    });
  });

  group('computeHalfCallingStats — performedOnly', () {
    test(
      'performedOnly counts only performed occurrences but keeps structure',
      () {
        final slots = [
          danceSlot('d1', position: 0, performedAt: DateTime.utc(2026)),
          breakSlot(position: 1),
          danceSlot('d2', position: 2, performedAt: DateTime.utc(2026)),
          danceSlot('d1', position: 3), // not performed
        ];
        final all = computeHalfCallingStats(danceId: 'd1', programs: [slots]);
        expect(all.firstHalfCount, 1);
        expect(all.secondHalfCount, 1);
        expect(all.closedSecondHalfCount, 1);

        final performed = computeHalfCallingStats(
          danceId: 'd1',
          programs: [slots],
          performedOnly: true,
        );
        expect(performed.firstHalfCount, 1);
        // The 2nd-half d1 occurrence was not performed → not counted, and so no
        // closer credit either.
        expect(performed.secondHalfCount, 0);
        expect(performed.closedSecondHalfCount, 0);
      },
    );
  });

  group('computeHalfCallingStats — aggregation across programs', () {
    test('sums counts across multiple programs', () {
      final p1 = [
        danceSlot('d1', position: 0),
        breakSlot(position: 1),
        danceSlot('d1', position: 2),
      ];
      final p2 = [
        danceSlot('d2', position: 0),
        danceSlot('d1', position: 1),
        breakSlot(position: 2),
        danceSlot('d3', position: 3),
      ];
      final stats = computeHalfCallingStats(danceId: 'd1', programs: [p1, p2]);
      // p1: 1 first (opener + no, it's the only 1st-half dance so opener),
      //     1 second (closer).
      // p2: 1 first (d1 at pos 1; opener is d2 → no opener credit).
      expect(stats.firstHalfCount, 2);
      expect(stats.secondHalfCount, 1);
      expect(stats.openedFirstHalfCount, 1);
      expect(stats.closedSecondHalfCount, 1);
    });

    test('sorts each program by position before deriving halves', () {
      // Feed slots out of position order; result must match position order.
      final slots = [
        danceSlot('d1', position: 5),
        breakSlot(position: 1),
        danceSlot('d1', position: 0),
      ];
      final stats = computeHalfCallingStats(danceId: 'd1', programs: [slots]);
      // Position order: d1@0 (first half), break@1, d1@5 (second half).
      expect(stats.firstHalfCount, 1);
      expect(stats.secondHalfCount, 1);
    });
  });

  group('HalfCallingStats value semantics', () {
    test('== and hashCode', () {
      const a = HalfCallingStats(
        firstHalfCount: 1,
        secondHalfCount: 2,
        openedFirstHalfCount: 3,
        closedSecondHalfCount: 4,
      );
      const b = HalfCallingStats(
        firstHalfCount: 1,
        secondHalfCount: 2,
        openedFirstHalfCount: 3,
        closedSecondHalfCount: 4,
      );
      const c = HalfCallingStats(firstHalfCount: 9);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('empty has no counts', () {
      expect(HalfCallingStats.empty.hasAny, isFalse);
      expect(HalfCallingStats.empty.firstHalfCount, 0);
    });
  });
}
