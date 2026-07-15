import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 10);

  group('ProgramSlot invariants', () {
    test('requires at least one of danceId or text', () {
      expect(() => ProgramSlot(id: 's1', position: 0), throwsArgumentError);
    });

    test('accepts danceId only, text only, and both together', () {
      expect(ProgramSlot(id: 's1', position: 0, danceId: 'd1').danceId, 'd1');
      final textOnly = ProgramSlot(id: 's2', position: 1, text: 'Waltz');
      expect(textOnly.danceId, isNull);
      final both = ProgramSlot(
        id: 's3',
        position: 2,
        danceId: 'd1',
        text: 'call from the floor',
      );
      expect(both.danceId, 'd1');
      expect(both.text, 'call from the floor');
    });

    test('rejects negative positions', () {
      expect(
        () => ProgramSlot(id: 's1', position: -1, danceId: 'd1'),
        throwsArgumentError,
      );
    });
  });

  group('Program invariants', () {
    test('rejects empty titles', () {
      expect(
        () => Program(id: 'p1', title: ' ', createdAt: now, updatedAt: now),
        throwsArgumentError,
      );
    });

    test('orders slots by position regardless of input order', () {
      final p = Program(
        id: 'p1',
        title: 'Friday night',
        slots: [
          ProgramSlot(id: 's2', position: 1, text: 'break'),
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
        ],
        createdAt: now,
        updatedAt: now,
      );
      expect(p.slots.map((s) => s.id), ['s1', 's2']);
    });

    test('slot list is unmodifiable', () {
      final p = Program(id: 'p1', title: 'T', createdAt: now, updatedAt: now);
      expect(
        () => p.slots.add(ProgramSlot(id: 'x', position: 0, text: 'y')),
        throwsUnsupportedError,
      );
    });
  });

  group('Program.duplicate', () {
    test('deep-copies slots with fresh ids, draft status, no history', () {
      final original = Program(
        id: 'p1',
        title: 'Friday night',
        status: ProgramStatus.performed,
        venue: 'Grange Hall',
        slots: [
          ProgramSlot(id: 's1', position: 0, danceId: 'd1', performedAt: now),
          ProgramSlot(id: 's2', position: 1, text: 'waltz', isAlt: true),
        ],
        createdAt: now,
        updatedAt: now,
      );
      var n = 0;
      final later = now.add(const Duration(days: 7));
      final copy = original.duplicate(
        newId: 'p2',
        newSlotId: () => 'new${n++}',
        now: later,
      );

      expect(copy.id, 'p2');
      expect(copy.status, ProgramStatus.draft);
      expect(copy.title, original.title);
      expect(copy.venue, original.venue);
      expect(copy.slots, hasLength(2));
      expect(copy.slots.map((s) => s.id), ['new0', 'new1']);
      expect(copy.slots[0].danceId, 'd1');
      expect(copy.slots[0].performedAt, isNull, reason: 'history cleared');
      expect(copy.slots[1].isAlt, isTrue);
      expect(copy.createdAt, later);
    });

    test('can retitle the copy', () {
      final p = Program(id: 'p1', title: 'Old', createdAt: now, updatedAt: now);
      expect(
        p
            .duplicate(
              newId: 'p2',
              newSlotId: () => 'x',
              now: now,
              newTitle: 'New',
            )
            .title,
        'New',
      );
    });
  });

  group('soft delete', () {
    test('copyWith sets and clearDeletedAt restores', () {
      final p = Program(id: 'p1', title: 'T', createdAt: now, updatedAt: now);
      final deleted = p.copyWith(deletedAt: now);
      expect(deleted.isDeleted, isTrue);
      expect(deleted.copyWith(clearDeletedAt: true).isDeleted, isFalse);
    });
  });

  group('copyWith clearing nullable fields', () {
    final p = Program(
      id: 'p1',
      title: 'Friday night',
      eventDate: now,
      venue: 'Grange Hall',
      createdAt: now,
      updatedAt: now,
    );

    test('clearEventDate clears the event date', () {
      expect(p.copyWith(clearEventDate: true).eventDate, isNull);
    });

    test('clearVenue clears the venue', () {
      expect(p.copyWith(clearVenue: true).venue, isNull);
    });

    test('without the clear flag the value is preserved', () {
      final unchanged = p.copyWith(title: 'Saturday night');
      expect(unchanged.eventDate, now);
      expect(unchanged.venue, 'Grange Hall');
    });

    test('a set clear flag wins over a passed value', () {
      final later = now.add(const Duration(days: 1));
      expect(
        p.copyWith(eventDate: later, clearEventDate: true).eventDate,
        isNull,
      );
      expect(p.copyWith(venue: 'Elsewhere', clearVenue: true).venue, isNull);
    });
  });

  group('event metadata fields', () {
    test('Program carries band, caller, and dancerLevel', () {
      final p = Program(
        id: 'p1',
        title: 'Contra Night',
        band: 'The Fiddleheads',
        caller: 'Alice',
        dancerLevel: 'intermediate',
        createdAt: now,
        updatedAt: now,
      );
      expect(p.band, 'The Fiddleheads');
      expect(p.caller, 'Alice');
      expect(p.dancerLevel, 'intermediate');
    });

    test('ProgramSlot carries guestCaller and plannedMinutes', () {
      final s = ProgramSlot(
        id: 's1',
        position: 0,
        danceId: 'd1',
        guestCaller: 'Bob',
        plannedMinutes: 12,
      );
      expect(s.guestCaller, 'Bob');
      expect(s.plannedMinutes, 12);
    });

    test('plannedMinutes >= 0 is enforced; 0 is allowed', () {
      expect(
        () => ProgramSlot(
          id: 's1',
          position: 0,
          danceId: 'd1',
          plannedMinutes: -1,
        ),
        throwsArgumentError,
      );
      expect(
        ProgramSlot(
          id: 's1',
          position: 0,
          danceId: 'd1',
          plannedMinutes: 0,
        ).plannedMinutes,
        0,
      );
    });

    test('Program.copyWith clears band/caller/dancerLevel via flags', () {
      final p = Program(
        id: 'p1',
        title: 'T',
        band: 'B',
        caller: 'C',
        dancerLevel: 'L',
        createdAt: now,
        updatedAt: now,
      );
      final cleared = p.copyWith(
        clearBand: true,
        clearCaller: true,
        clearDancerLevel: true,
      );
      expect(cleared.band, isNull);
      expect(cleared.caller, isNull);
      expect(cleared.dancerLevel, isNull);
      // A set clear flag wins over a passed value.
      expect(p.copyWith(band: 'X', clearBand: true).band, isNull);
      // Without the flag, values pass through / are preserved.
      final updated = p.copyWith(band: 'New');
      expect(updated.band, 'New');
      expect(updated.caller, 'C');
    });

    test(
      'ProgramSlot.copyWith clears guestCaller/plannedMinutes via flags',
      () {
        final s = ProgramSlot(
          id: 's1',
          position: 0,
          danceId: 'd1',
          guestCaller: 'Bob',
          plannedMinutes: 10,
        );
        final cleared = s.copyWith(
          clearGuestCaller: true,
          clearPlannedMinutes: true,
        );
        expect(cleared.guestCaller, isNull);
        expect(cleared.plannedMinutes, isNull);
        expect(
          s
              .copyWith(plannedMinutes: 20, clearPlannedMinutes: true)
              .plannedMinutes,
          isNull,
        );
        expect(s.copyWith(plannedMinutes: 20).plannedMinutes, 20);
      },
    );

    test('ProgramSlot.copyWith sets and clears performedAt via flag', () {
      final now = DateTime.utc(2026, 5, 1, 20, 30);
      final s = ProgramSlot(id: 's1', position: 0, danceId: 'd1');
      final marked = s.copyWith(performedAt: now);
      expect(marked.performedAt, now);
      expect(marked.copyWith(clearPerformedAt: true).performedAt, isNull);
      // A set clear flag wins over any value passed for the same field.
      expect(
        marked.copyWith(performedAt: now, clearPerformedAt: true).performedAt,
        isNull,
      );
    });

    test('duplicate carries the new fields through', () {
      final original = Program(
        id: 'p1',
        title: 'Night',
        band: 'The Fiddleheads',
        caller: 'Alice',
        dancerLevel: 'beginner',
        slots: [
          ProgramSlot(
            id: 's1',
            position: 0,
            danceId: 'd1',
            guestCaller: 'Bob',
            plannedMinutes: 12,
            performedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final copy = original.duplicate(
        newId: 'p2',
        newSlotId: () => 'ns1',
        now: now,
      );
      expect(copy.band, 'The Fiddleheads');
      expect(copy.caller, 'Alice');
      expect(copy.dancerLevel, 'beginner');
      expect(copy.slots.single.guestCaller, 'Bob');
      expect(copy.slots.single.plannedMinutes, 12);
      // performedAt still resets per existing behavior.
      expect(copy.slots.single.performedAt, isNull);
    });
  });

  group('ALT grouping (Program.grouped)', () {
    Program program(List<ProgramSlot> slots) => Program(
      id: 'p1',
      title: 'T',
      slots: slots,
      createdAt: now,
      updatedAt: now,
    );

    ProgramSlot slot(String id, int pos, {bool alt = false}) =>
        ProgramSlot(id: id, position: pos, text: id, isAlt: alt);

    test('all primaries produce one group each with no alternates', () {
      final g = program([slot('a', 0), slot('b', 1), slot('c', 2)]).grouped;
      expect(g.map((x) => x.primary.id), ['a', 'b', 'c']);
      expect(g.every((x) => x.alternates.isEmpty), isTrue);
    });

    test('groups multiple alts under the nearest preceding primary', () {
      final g = program([
        slot('a', 0),
        slot('a1', 1, alt: true),
        slot('a2', 2, alt: true),
        slot('b', 3),
        slot('b1', 4, alt: true),
      ]).grouped;
      expect(g.map((x) => x.primary.id), ['a', 'b']);
      expect(g[0].alternates.map((s) => s.id), ['a1', 'a2']);
      expect(g[1].alternates.map((s) => s.id), ['b1']);
    });

    test('leading/orphaned alt renders without throwing as its own group', () {
      final g = program([
        slot('orphan', 0, alt: true),
        slot('a', 1),
        slot('a1', 2, alt: true),
      ]).grouped;
      expect(g.map((x) => x.primary.id), ['orphan', 'a']);
      expect(g[0].alternates, isEmpty);
      expect(g[1].alternates.map((s) => s.id), ['a1']);
      // Every slot appears exactly once across all groups.
      final all = [
        for (final grp in g) grp.primary.id,
        for (final grp in g) ...grp.alternates.map((s) => s.id),
      ];
      expect(all.toSet(), {'orphan', 'a', 'a1'});
      expect(all, hasLength(3));
    });

    test('empty program yields no groups', () {
      expect(program(const []).grouped, isEmpty);
    });
  });

  group('Program.validate', () {
    Program program(List<ProgramSlot> slots) => Program(
      id: 'p1',
      title: 'T',
      slots: slots,
      createdAt: now,
      updatedAt: now,
    );

    test('is clean for a well-formed program', () {
      final issues = program([
        ProgramSlot(id: 'a', position: 0, text: 'a'),
        ProgramSlot(id: 'a1', position: 1, text: 'a1', isAlt: true),
      ]).validate();
      expect(issues, isEmpty);
    });

    test('warns (non-blocking) about a leading/orphaned alt', () {
      final issues = program([
        ProgramSlot(id: 'orphan', position: 0, text: 'x', isAlt: true),
        ProgramSlot(id: 'a', position: 1, text: 'a'),
      ]).validate();
      expect(issues, hasLength(1));
      expect(issues.single.severity, ValidationSeverity.warning);
      expect(issues.single.code, 'orphaned_alt');
      // User-facing message references position/text, not the internal id.
      expect(issues.single.message, isNot(contains('orphan')));
      expect(issues.single.message, contains('position 1'));
      expect(issues.single.message, contains('"x"'));
    });
  });
}
