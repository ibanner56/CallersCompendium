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

  group('break recognition & derived half', () {
    Program program(List<ProgramSlot> slots) => Program(
      id: 'p1',
      title: 'T',
      slots: slots,
      createdAt: now,
      updatedAt: now,
    );

    ProgramSlot dance(String id, int pos) =>
        ProgramSlot(id: id, position: pos, danceId: 'dance-$id');
    ProgramSlot free(String id, int pos, String text) =>
        ProgramSlot(id: id, position: pos, text: text);
    ProgramSlot breakSlot(String id, int pos) =>
        ProgramSlot(id: id, position: pos, text: Program.breakSlotText);

    group('ProgramSlot.isBreak', () {
      test('the canonical break token is a break', () {
        expect(breakSlot('b', 0).isBreak, isTrue);
      });

      test('is case- and whitespace-insensitive on the token', () {
        expect(free('b', 0, ' break ').isBreak, isTrue);
        expect(free('b', 0, 'BREAK').isBreak, isTrue);
        expect(free('b', 0, 'Break').isBreak, isTrue);
      });

      test('does not match other free text or partial tokens', () {
        expect(free('b', 0, 'breakdown').isBreak, isFalse);
        expect(free('b', 0, 'short break after this one').isBreak, isFalse);
        expect(free('b', 0, 'Waltz').isBreak, isFalse);
      });

      test('a dance slot is never a break even if text says break', () {
        expect(
          ProgramSlot(
            id: 'd',
            position: 0,
            danceId: 'd1',
            text: 'break',
          ).isBreak,
          isFalse,
        );
      });
    });

    test('no break: no halves, no first-break index', () {
      final p = program([dance('a', 0), dance('b', 1), free('n', 2, 'Waltz')]);
      expect(p.hasBreak, isFalse);
      expect(p.firstBreakSlotIndex, isNull);
      expect(p.halfAtIndex(0), isNull);
      expect(p.halfAtIndex(1), isNull);
      expect(p.halfAtIndex(2), isNull);
    });

    test('break in the middle splits first/second, break slot is neither', () {
      final p = program([
        dance('a', 0),
        dance('b', 1),
        breakSlot('brk', 2),
        dance('c', 3),
        dance('d', 4),
      ]);
      expect(p.hasBreak, isTrue);
      expect(p.firstBreakSlotIndex, 2);
      expect(p.halfAtIndex(0), ProgramHalf.first);
      expect(p.halfAtIndex(1), ProgramHalf.first);
      expect(p.halfAtIndex(2), isNull);
      expect(p.halfAtIndex(3), ProgramHalf.second);
      expect(p.halfAtIndex(4), ProgramHalf.second);
    });

    test('break first: everything after is second half', () {
      final p = program([breakSlot('brk', 0), dance('a', 1), dance('b', 2)]);
      expect(p.firstBreakSlotIndex, 0);
      expect(p.halfAtIndex(0), isNull);
      expect(p.halfAtIndex(1), ProgramHalf.second);
      expect(p.halfAtIndex(2), ProgramHalf.second);
    });

    test('break last: everything before is first half', () {
      final p = program([dance('a', 0), dance('b', 1), breakSlot('brk', 2)]);
      expect(p.firstBreakSlotIndex, 2);
      expect(p.halfAtIndex(0), ProgramHalf.first);
      expect(p.halfAtIndex(1), ProgramHalf.first);
      expect(p.halfAtIndex(2), isNull);
    });

    test('multiple breaks: the FIRST break defines the halves', () {
      final p = program([
        dance('a', 0),
        breakSlot('brk1', 1),
        dance('b', 2),
        breakSlot('brk2', 3),
        dance('c', 4),
      ]);
      expect(p.firstBreakSlotIndex, 1);
      expect(p.halfAtIndex(0), ProgramHalf.first);
      expect(p.halfAtIndex(1), isNull);
      // Everything after the first break — including the second break slot and
      // slots beyond it — is the second half (except the break slot itself).
      expect(p.halfAtIndex(2), ProgramHalf.second);
      expect(p.halfAtIndex(3), isNull);
      expect(p.halfAtIndex(4), ProgramHalf.second);
    });

    test('halfAtIndex is null for out-of-range indices', () {
      final p = program([dance('a', 0), breakSlot('brk', 1), dance('b', 2)]);
      expect(p.halfAtIndex(-1), isNull);
      expect(p.halfAtIndex(3), isNull);
    });

    group('Program.halvesForSlots', () {
      test('aligns to the slot list and matches halfAtIndex', () {
        final slots = [
          dance('a', 0),
          dance('b', 1),
          breakSlot('brk', 2),
          dance('c', 3),
        ];
        expect(Program.halvesForSlots(slots), [
          ProgramHalf.first,
          ProgramHalf.first,
          null,
          ProgramHalf.second,
        ]);
      });

      test('all null when there is no break', () {
        final slots = [dance('a', 0), dance('b', 1)];
        expect(Program.halvesForSlots(slots), [null, null]);
      });

      test('empty slot list yields empty halves', () {
        expect(Program.halvesForSlots(const []), isEmpty);
      });
    });
  });

  group('Program.stampDanceSlotsPerformed', () {
    Program program({
      DateTime? eventDate,
      List<ProgramSlot> slots = const [],
    }) => Program(
      id: 'p1',
      title: 'Spring Dance',
      eventDate: eventDate,
      slots: slots,
      createdAt: now,
      updatedAt: now,
    );

    test('stamps dance-linked slots that lack performedAt with eventDate', () {
      final eventDate = DateTime.utc(2026, 3, 15);
      final p = program(
        eventDate: eventDate,
        slots: [
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
        ],
      );
      final stamped = p.stampDanceSlotsPerformed(
        fallback: DateTime.utc(2026, 7, 20),
      );
      expect(stamped.slots.map((s) => s.performedAt), [eventDate, eventDate]);
    });

    test('uses fallback when the program has no eventDate', () {
      final fallback = DateTime.utc(2026, 7, 20);
      final p = program(
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      );
      final stamped = p.stampDanceSlotsPerformed(fallback: fallback);
      expect(stamped.slots.single.performedAt, fallback);
    });

    test('never overwrites an existing performedAt (idempotent)', () {
      final existing = DateTime.utc(2025, 1, 1);
      final p = program(
        eventDate: DateTime.utc(2026, 3, 15),
        slots: [
          ProgramSlot(
            id: 's1',
            position: 0,
            danceId: 'd1',
            performedAt: existing,
          ),
        ],
      );
      final stamped = p.stampDanceSlotsPerformed(
        fallback: DateTime.utc(2026, 7, 20),
      );
      expect(stamped.slots.single.performedAt, existing);
      // Applying twice yields the same result.
      final twice = stamped.stampDanceSlotsPerformed(
        fallback: DateTime.utc(2026, 7, 20),
      );
      expect(twice.slots.single.performedAt, existing);
    });

    test('leaves free-text / note slots untouched', () {
      final p = program(
        eventDate: DateTime.utc(2026, 3, 15),
        slots: [
          ProgramSlot(id: 's1', position: 0, text: 'Waltz break'),
          ProgramSlot(id: 's2', position: 1, text: Program.breakSlotText),
        ],
      );
      final stamped = p.stampDanceSlotsPerformed(
        fallback: DateTime.utc(2026, 7, 20),
      );
      expect(stamped.slots.every((s) => s.performedAt == null), isTrue);
      expect(identical(stamped, p), isTrue);
    });

    test('returns the same instance when nothing needs stamping', () {
      final p = program(
        slots: [
          ProgramSlot(
            id: 's1',
            position: 0,
            danceId: 'd1',
            performedAt: DateTime.utc(2025, 1, 1),
          ),
        ],
      );
      expect(identical(p.stampDanceSlotsPerformed(fallback: now), p), isTrue);
    });
  });
}
