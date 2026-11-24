// A program slot's placeholder saved search (#2338): the model's invariant,
// storage, duplicate, and the archive codec.
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program(List<ProgramSlot> slots) => Program(
  id: 'p1',
  title: 'Family night',
  slots: slots,
  createdAt: _now,
  updatedAt: _now,
);

ProgramSlot _placeholder({String id = 's1', int position = 0}) => ProgramSlot(
  id: id,
  position: position,
  text: 'Easy family opener',
  placeholderSearchId: 'search-1',
);

void main() {
  group('ProgramSlot.placeholderSearchId', () {
    test('an unfilled slot with a reference is a placeholder', () {
      final slot = _placeholder();
      expect(slot.isPlaceholder, isTrue);
      expect(slot.placeholderSearchId, 'search-1');
    });

    test('a slot with a dance never keeps a reference', () {
      final slot = ProgramSlot(
        id: 's1',
        position: 0,
        danceId: 'd1',
        placeholderSearchId: 'search-1',
      );
      expect(slot.placeholderSearchId, isNull);
      expect(slot.isPlaceholder, isFalse);
      expect(
        _placeholder().copyWith(danceId: 'd1').placeholderSearchId,
        isNull,
      );
    });

    test('a blank reference is no reference', () {
      final slot = ProgramSlot(
        id: 's1',
        position: 0,
        text: 'x',
        placeholderSearchId: '  ',
      );
      expect(slot.isPlaceholder, isFalse);
    });

    test('equality counts the reference', () {
      expect(
        _placeholder(),
        isNot(_placeholder().copyWith(clearPlaceholderSearchId: true)),
      );
      expect(_placeholder(), _placeholder());
    });

    test('a duplicated program keeps its placeholders fillable', () {
      var n = 0;
      final copy = _program([
        _placeholder(),
      ]).duplicate(newId: 'p2', newSlotId: () => 'n${n++}', now: _now);
      expect(copy.slots.single.placeholderSearchId, 'search-1');
      expect(copy.slots.single.text, 'Easy family opener');
    });
  });

  group('storage', () {
    late CompendiumDatabase db;
    setUp(() => db = openTestDatabase());
    tearDown(() => db.close());

    test('a placeholder is stored and read back with its reference', () async {
      final repo = ProgramRepository(db);
      await repo.create(
        _program([
          _placeholder(),
          ProgramSlot(id: 's2', position: 1, text: 'Waltz'),
        ]),
      );
      final read = (await repo.getById('p1'))!;
      expect(read.slots[0].placeholderSearchId, 'search-1');
      expect(read.slots[0].text, 'Easy family opener');
      expect(read.slots[1].placeholderSearchId, isNull);
    });

    test('an update writes the reference, and clearing it clears it', () async {
      final repo = ProgramRepository(db);
      await repo.create(
        _program([ProgramSlot(id: 's1', position: 0, text: 'Note')]),
      );
      await repo.update(_program([_placeholder()]));
      expect(
        (await repo.getById('p1'))!.slots.single.placeholderSearchId,
        'search-1',
      );
      await repo.update(
        _program([_placeholder().copyWith(clearPlaceholderSearchId: true)]),
      );
      final updated = (await repo.getById('p1'))!;
      expect(updated.slots.single.placeholderSearchId, isNull);
      expect(updated.slots.single.text, 'Easy family opener');
    });
  });

  group('archive codec', () {
    test('backup and share both carry a placeholder; a slot without one '
        'emits no key, so its encoding does not change', () {
      for (final mode in ArchiveSerializationMode.values) {
        final json = encodeArchive(
          CompendiumArchive(
            exportedAt: _now,
            programs: [
              _program([
                _placeholder(),
                ProgramSlot(id: 's2', position: 1, text: 'Waltz'),
              ]),
            ],
          ),
          mode: mode,
        );
        final slots =
            (((jsonDecode(json) as Map)['programs'] as List).single
                    as Map)['slots']
                as List;
        expect((slots[0] as Map)['placeholderSearchId'], 'search-1');
        expect((slots[1] as Map).containsKey('placeholderSearchId'), isFalse);
        final back = decodeArchive(json).archive.programs.single;
        expect(back.slots[0].placeholderSearchId, 'search-1');
        expect(back.slots[1].placeholderSearchId, isNull);
      }
    });

    test('a malformed reference drops only that field', () {
      final json =
          encodeArchive(
            CompendiumArchive(
              exportedAt: _now,
              programs: [
                _program([_placeholder()]),
              ],
            ),
          ).replaceFirst(
            '"placeholderSearchId":"search-1"',
            '"placeholderSearchId":7',
          );
      final back = decodeArchive(json).archive.programs.single.slots.single;
      expect(back.placeholderSearchId, isNull);
      expect(back.text, 'Easy family opener');
    });
  });
}
