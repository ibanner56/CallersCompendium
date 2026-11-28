import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/program_slot_rebase.dart';

ProgramSlot _slot(String id, {DateTime? performedAt, String? note}) =>
    ProgramSlot(
      id: id,
      position: 0,
      danceId: 'dance-$id',
      text: note,
      performedAt: performedAt,
    );

List<String> _ids(List<ProgramSlot> slots) => [for (final s in slots) s.id];

void main() {
  final stamp = DateTime.utc(2026, 10, 24);
  final mark = DateTime.utc(2026, 10, 25);

  test('a changed field is applied; the other fields keep the target', () {
    final result = rebaseSlotEdits(
      before: [_slot('a')],
      after: [_slot('a', performedAt: mark)],
      onto: [_slot('a', note: 'stored note')],
    );
    expect(result.single.performedAt, mark);
    expect(result.single.text, 'stored note');
  });

  test('a stamp the target has and the edit did not touch is kept', () {
    final result = rebaseSlotEdits(
      before: [_slot('a'), _slot('b')],
      after: [
        _slot('a', performedAt: mark),
        _slot('b'),
      ],
      onto: [
        _slot('a', performedAt: stamp),
        _slot('b', performedAt: stamp),
      ],
    );
    expect(result.map((s) => s.performedAt), [mark, stamp]);
  });

  test('clearing a mark clears it in the target', () {
    final result = rebaseSlotEdits(
      before: [_slot('a', performedAt: mark)],
      after: [_slot('a')],
      onto: [_slot('a', performedAt: mark)],
    );
    expect(result.single.performedAt, isNull);
  });

  test('an unsaved order in the edit base does not reorder the target', () {
    final result = rebaseSlotEdits(
      before: [_slot('b'), _slot('a'), _slot('c')],
      after: [
        _slot('b', performedAt: mark),
        _slot('a'),
        _slot('c'),
      ],
      onto: [_slot('a'), _slot('b'), _slot('c')],
    );
    expect(_ids(result), ['a', 'b', 'c']);
    expect(result[1].performedAt, mark);
  });

  test('a moved slot follows its new predecessor', () {
    final result = rebaseSlotEdits(
      before: [_slot('a'), _slot('b'), _slot('c'), _slot('d')],
      after: [_slot('a'), _slot('c'), _slot('d'), _slot('b')],
      onto: [_slot('a'), _slot('x'), _slot('b'), _slot('c'), _slot('d')],
    );
    expect(_ids(result), ['a', 'x', 'c', 'd', 'b']);
  });

  test('a slot moved to the front goes first', () {
    final result = rebaseSlotEdits(
      before: [_slot('a'), _slot('b')],
      after: [_slot('b'), _slot('a')],
      onto: [_slot('a'), _slot('b')],
    );
    expect(_ids(result), ['b', 'a']);
  });

  test('an added slot is inserted after its predecessor in the target', () {
    final result = rebaseSlotEdits(
      before: [_slot('a'), _slot('u'), _slot('b')],
      after: [_slot('a'), _slot('u'), _slot('new'), _slot('b')],
      onto: [_slot('a'), _slot('b')],
    );
    expect(_ids(result), [
      'a',
      'new',
      'b',
    ], reason: 'u is an unsaved builder slot; the nearest held one is a');
  });

  test('an inserted slot does not split a group the edit never saw', () {
    final alt = ProgramSlot(
      id: 'c-alt',
      position: 0,
      danceId: 'x',
      isAlt: true,
    );
    final result = rebaseSlotEdits(
      before: [_slot('c'), _slot('d')],
      after: [_slot('c'), _slot('new'), _slot('d')],
      onto: [_slot('c'), alt, _slot('d')],
    );
    expect(_ids(result), ['c', 'c-alt', 'new', 'd']);
  });

  test('a slot the target does not hold is never added', () {
    final result = rebaseSlotEdits(
      before: [_slot('a'), _slot('u')],
      after: [
        _slot('u', performedAt: mark),
        _slot('a'),
      ],
      onto: [_slot('a')],
    );
    expect(_ids(result), ['a']);
  });

  test('a removed slot is removed', () {
    final result = rebaseSlotEdits(
      before: [_slot('a'), _slot('b')],
      after: [_slot('a')],
      onto: [_slot('a'), _slot('b'), _slot('c')],
    );
    expect(_ids(result), ['a', 'c']);
  });

  test('applying the reverse edit restores the target', () {
    final before = [_slot('a'), _slot('b')];
    final after = [_slot('new'), _slot('b'), _slot('a', performedAt: mark)];
    final onto = [_slot('a'), _slot('b', performedAt: stamp)];
    final applied = rebaseSlotEdits(before: before, after: after, onto: onto);
    final undone = rebaseSlotEdits(before: after, after: before, onto: applied);
    expect(undone, onto);
  });

  test('a slot Perform added that the target already holds is not added '
      'again', () {
    // The target is a program that already took Perform's insert (GIG-6: a
    // change from elsewhere carried onto Perform's own copy).
    final result = rebaseSlotEdits(
      before: [_slot('a')],
      after: [_slot('a'), _slot('new'), _slot('elsewhere')],
      onto: [_slot('a'), _slot('new')],
    );
    expect(_ids(result), ['a', 'new', 'elsewhere']);
  });

  // #2346: a swap keeps the old dance as an alternate added after the slot it
  // swapped. If another device deleted that slot meanwhile, the alternate has
  // no group of its own left and is dropped, rather than joining another.
  test('an alternate Perform added after a slot the target no longer holds is '
      'dropped', () {
    final kept = ProgramSlot(
      id: 'kept',
      position: 0,
      danceId: 'old',
      isAlt: true,
    );
    final result = rebaseSlotEdits(
      before: [_slot('a'), _slot('b'), _slot('c')],
      after: [
        _slot('a'),
        _slot('b').copyWith(danceId: 'new'),
        kept,
        _slot('c'),
      ],
      onto: [_slot('a'), _slot('c')],
    );
    expect(_ids(result), ['a', 'c']);
  });

  test('an alternate Perform added after a slot the target holds stays in '
      'its group', () {
    final kept = ProgramSlot(
      id: 'kept',
      position: 0,
      danceId: 'old',
      isAlt: true,
    );
    final result = rebaseSlotEdits(
      before: [_slot('a'), _slot('b')],
      after: [
        _slot('a'),
        _slot('b').copyWith(danceId: 'new'),
        kept,
      ],
      onto: [_slot('a'), _slot('b')],
    );
    expect(_ids(result), ['a', 'b', 'kept']);
    expect(result[1].danceId, 'new');
  });

  group('performAdjustmentStillApplies', () {
    ProgramSlot slot(String id, String dance) =>
        ProgramSlot(id: id, position: 0, danceId: dance);
    List<ProgramSlot> numbered(List<ProgramSlot> slots) => [
      for (var i = 0; i < slots.length; i++) slots[i].copyWith(position: i),
    ];
    // a · b · c, three planned dances.
    final base = numbered([slot('a', 'da'), slot('b', 'db'), slot('c', 'dc')]);
    final swapped = numbered(
      Program.swapSlotDanceKeepingAlternate(
        base,
        0,
        danceId: 'dn',
        alternateId: 'kept',
      ),
    );
    final marked = numbered([
      base[0],
      base[1],
      base[2].copyWith(performedAt: mark),
    ]);

    /// Each adjustment, the slot it changes or moves, a slot it leaves alone,
    /// and whether it still applies once another device has put another
    /// dance on the slot it changes or moves.
    final cases =
        <
          ({
            String name,
            List<ProgramSlot> before,
            List<ProgramSlot> after,
            String moved,
            String untouched,
            bool appliesOverMoved,
          })
        >[
          (
            name: 'reorder',
            before: base,
            after: numbered([base[2], base[0], base[1]]),
            moved: 'c',
            untouched: 'b',
            // Only the order changes, which credits no dance.
            appliesOverMoved: true,
          ),
          (
            name: 'insert',
            before: base,
            after: numbered([base[0], slot('i', 'di'), base[1], base[2]]),
            moved: 'b',
            untouched: 'a',
            appliesOverMoved: true,
          ),
          (
            name: 'note edit',
            before: base,
            after: numbered([
              base[0],
              base[1],
              base[2].copyWith(text: 'Raffle'),
            ]),
            moved: 'c',
            untouched: 'a',
            appliesOverMoved: false,
          ),
          (
            name: 'mark performed',
            before: base,
            after: marked,
            moved: 'c',
            untouched: 'a',
            appliesOverMoved: false,
          ),
          (
            name: 'Undo of a swap',
            before: swapped,
            after: base,
            moved: 'a',
            untouched: 'c',
            appliesOverMoved: false,
          ),
          (
            name: 'Undo of a mark',
            before: marked,
            after: base,
            moved: 'c',
            untouched: 'a',
            appliesOverMoved: false,
          ),
        ];

    List<ProgramSlot> elsewhere(List<ProgramSlot> slots, String id) => [
      for (final s in slots) s.id == id ? s.copyWith(danceId: 'dz') : s,
    ];

    for (final c in cases) {
      test('${c.name}: applies when nothing changed elsewhere', () {
        expect(
          performAdjustmentStillApplies(
            before: c.before,
            after: c.after,
            onto: c.before,
          ),
          isTrue,
        );
      });

      test('${c.name}: applies when another dance was put on a slot it '
          'leaves alone', () {
        expect(
          performAdjustmentStillApplies(
            before: c.before,
            after: c.after,
            onto: elsewhere(c.before, c.untouched),
          ),
          isTrue,
        );
      });

      test('${c.name}: ${c.appliesOverMoved ? 'applies' : 'is refused'} when '
          'another dance was put on the slot it changes or moves', () {
        expect(
          performAdjustmentStillApplies(
            before: c.before,
            after: c.after,
            onto: elsewhere(c.before, c.moved),
          ),
          c.appliesOverMoved,
        );
      });
    }

    // A swap under a note or break stays in place as an alternate, so the
    // group's front is a slot the swap never touches: only the front-slot
    // check sees another device marking it performed meanwhile.
    test('a swap in a group led by a note is refused once the note has been '
        'marked performed elsewhere', () {
      final before = numbered([
        ProgramSlot(id: 'n', position: 0, text: 'Raffle'),
        ProgramSlot(id: 'x', position: 0, danceId: 'dx', isAlt: true),
      ]);
      final after = numbered(
        Program.swapSlotDanceKeepingAlternate(
          before,
          1,
          danceId: 'dn',
          alternateId: 'kept',
        ),
      );
      // The swap left the note leading the group.
      expect(after.first.id, 'n');
      expect(after.first, before.first);
      expect(
        performAdjustmentStillApplies(
          before: before,
          after: after,
          onto: before,
        ),
        isTrue,
      );

      final noteMarked = [
        before[0].copyWith(performedAt: mark),
        before[1],
      ];
      expect(
        performAdjustmentStillApplies(
          before: before,
          after: after,
          onto: noteMarked,
        ),
        isFalse,
      );
    });
  });
}
