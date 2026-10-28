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
}
