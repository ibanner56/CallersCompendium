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
}
