import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 10);

  Program program({
    String title = 'Friday Contra',
    DateTime? eventDate,
    String? venue,
    String? band,
    String? caller,
    String? dancerLevel,
    String notes = '',
    List<ProgramSlot> slots = const [],
  }) => Program(
    id: 'p1',
    title: title,
    eventDate: eventDate,
    venue: venue,
    band: band,
    caller: caller,
    dancerLevel: dancerLevel,
    notes: notes,
    slots: slots,
    createdAt: now,
    updatedAt: now,
  );

  // Simple title lookup for danceId slots.
  String? titles(String id) => const {
    'd1': 'Rory O\'More',
    'd2': 'The Nice Combination',
    'd3': 'Chinese New Year',
  }[id];

  group('programToPlainText', () {
    test('renders numbered primaries in position order', () {
      final text = programToPlainText(
        program(
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
          ],
        ),
        titleFor: titles,
      );
      expect(text, contains('1. Rory O\'More'));
      expect(text, contains('2. The Nice Combination'));
      // Ordering is preserved.
      expect(text.indexOf('1. Rory'), lessThan(text.indexOf('2. The Nice')));
    });

    test('indents ALTs under the nearest preceding primary', () {
      final text = programToPlainText(
        program(
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
            ProgramSlot(id: 's3', position: 2, danceId: 'd3'),
          ],
        ),
        titleFor: titles,
      );
      final lines = text.split('\n');
      expect(lines, contains('1. Rory O\'More'));
      expect(lines, contains('   ALT: The Nice Combination'));
      expect(lines, contains('2. Chinese New Year'));
      // The alt is not numbered as its own primary.
      expect(text, isNot(contains('2. The Nice Combination')));
    });

    test('renders a free-text-only slot as its text', () {
      final text = programToPlainText(
        program(
          slots: [ProgramSlot(id: 's1', position: 0, text: 'Waltz break')],
        ),
        titleFor: titles,
      );
      expect(text, contains('1. Waltz break'));
    });

    test('renders a dance slot with a per-slot note as "title — note"', () {
      final text = programToPlainText(
        program(
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              text: 'call slow',
            ),
          ],
        ),
        titleFor: titles,
      );
      expect(text, contains('1. Rory O\'More — call slow'));
    });

    test('appends optional guest caller and planned minutes', () {
      final text = programToPlainText(
        program(
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              guestCaller: 'Jo',
              plannedMinutes: 8,
            ),
          ],
        ),
        titleFor: titles,
      );
      expect(text, contains('1. Rory O\'More (guest: Jo; 8 min)'));
    });

    test('omits the optional suffix when guest and minutes are absent', () {
      final text = programToPlainText(
        program(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
        titleFor: titles,
      );
      expect(text, contains('1. Rory O\'More'));
      expect(text, isNot(contains('(')));
    });

    test('marks performed slots', () {
      final text = programToPlainText(
        program(
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1', performedAt: now),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
          ],
        ),
        titleFor: titles,
      );
      expect(text, contains('1. Rory O\'More [performed]'));
      expect(text, contains('2. The Nice Combination'));
      expect(text, isNot(contains('2. The Nice Combination [performed]')));
    });

    test('renders header only for an empty program', () {
      final text = programToPlainText(
        program(title: 'Empty Night'),
        titleFor: titles,
      );
      expect(text, 'Empty Night');
    });

    test('still renders a leading/orphaned alt', () {
      final text = programToPlainText(
        program(
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1', isAlt: true),
          ],
        ),
        titleFor: titles,
      );
      // The orphaned alt becomes a degenerate primary and is numbered.
      expect(text, contains('1. Rory O\'More'));
    });

    test(
      'falls back to the unknown-dance label when titleFor returns null',
      () {
        final text = programToPlainText(
          program(
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'gone')],
          ),
          titleFor: (_) => null,
        );
        expect(text, contains('1. Untitled dance'));
      },
    );

    test('uses a custom unknown-dance label', () {
      final text = programToPlainText(
        program(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'gone')],
        ),
        titleFor: (_) => null,
        unknownDanceLabel: '(missing)',
      );
      expect(text, contains('1. (missing)'));
    });

    test('formats the metadata block and omits absent parts', () {
      final text = programToPlainText(
        program(
          eventDate: DateTime.utc(2026, 3, 9),
          band: 'The Ripplers',
          caller: 'Isaac',
          // venue and dancerLevel absent
        ),
        titleFor: titles,
      );
      final lines = text.split('\n');
      expect(lines.first, 'Friday Contra');
      expect(lines, contains('2026-03-09'));
      expect(lines, contains('Band: The Ripplers'));
      expect(lines, contains('Caller: Isaac'));
      expect(text, isNot(contains('Level:')));
      // No venue means the date stands alone (no trailing separator).
      expect(text, isNot(contains(' · ')));
    });

    test('joins date and venue with a separator when both present', () {
      final text = programToPlainText(
        program(eventDate: DateTime.utc(2026, 3, 9), venue: 'Town Hall'),
        titleFor: titles,
      );
      expect(text, contains('2026-03-09 · Town Hall'));
    });

    test('uses a provided formatDate callback', () {
      final text = programToPlainText(
        program(eventDate: DateTime.utc(2026, 3, 9)),
        titleFor: titles,
        formatDate: (d) => 'March ${d.day}',
      );
      expect(text, contains('March 9'));
      expect(text, isNot(contains('2026-03-09')));
    });

    test('includes a Notes section when notes are present', () {
      final text = programToPlainText(
        program(notes: 'Bring extra water.'),
        titleFor: titles,
      );
      expect(text, contains('Notes:'));
      expect(text, contains('Bring extra water.'));
    });

    test('omits the Notes section when notes are blank', () {
      final text = programToPlainText(program(notes: '   '), titleFor: titles);
      expect(text, isNot(contains('Notes:')));
    });

    // Privacy invariant (ROADMAP 4b.4 / Choreographer doc): the emailable set
    // list is built solely from the Program plus the `titleFor` lookup, which
    // resolves a dance id to a *title* string. It never receives or serializes
    // choreographer records, so private contact data (email/location) has no
    // path into a shared export. This test locks that API shape by asserting
    // the sole per-dance content comes from `titleFor`.
    test('renders dances only via the titleFor lookup', () {
      final seenIds = <String>[];
      String? titleFor(String id) {
        seenIds.add(id);
        return const {'d1': 'Rory O\'More'}[id];
      }

      final text = programToPlainText(
        program(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
        titleFor: titleFor,
      );

      // The dance line is exactly the title resolved by titleFor.
      expect(text, contains('1. Rory O\'More'));
      expect(seenIds, ['d1']);
    });
  });
}
