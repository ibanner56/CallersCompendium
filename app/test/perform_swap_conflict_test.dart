import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/perform_adjustment_write.dart';

import 'support/test_repositories.dart';

/// Perform's **Swap** (#2346) changes several slots at once. When another
/// device changed one of them while Perform was open, merging the swap field
/// by field could put a dance in the wrong group or on a slot that counts
/// toward calling history, so the write is refused and the stored program
/// left as it is.
void main() {
  final now = DateTime.utc(2026, 1, 1);

  ProgramSlot slot(String id, String dance, {bool alt = false}) =>
      ProgramSlot(id: id, position: 0, danceId: dance, isAlt: alt);

  List<ProgramSlot> numbered(List<ProgramSlot> slots) => [
    for (var i = 0; i < slots.length; i++) slots[i].copyWith(position: i),
  ];

  Future<
    ({
      CompendiumRepositories repos,
      Program opened,
      PerformAdjustmentWrite write,
    })
  >
  swapAfterChangeElsewhere({
    required List<ProgramSlot> opened,
    int swapIndex = 0,
    String danceId = 'new',
    required List<ProgramSlot> elsewhere,
    List<ProgramSlot> Function(List<ProgramSlot> before)? edit,
  }) async {
    final repos = openTestRepositories();
    for (final id in ['dq', 'dp', 'dx', 'da', 'dy', 'dc', 'dz', 'new']) {
      await repos.dances.create(
        Dance(id: id, title: id, createdAt: now, updatedAt: now),
      );
    }
    final program = Program(
      id: 'p',
      title: 'Night',
      slots: numbered(opened),
      createdAt: now,
      updatedAt: now,
    );
    await repos.programs.create(program);
    final stored = (await repos.programs.getById('p'))!;
    await repos.programs.update(
      stored.copyWith(
        slots: numbered(elsewhere),
        updatedAt: now.add(const Duration(minutes: 5)),
      ),
    );
    final before = stored.slots;
    final after = numbered(
      edit?.call(before) ??
          Program.swapSlotDanceKeepingAlternate(
            before,
            swapIndex,
            danceId: danceId,
            alternateId: 'kept',
          ),
    );
    final write = await writePerformAdjustment(
      repos.programs,
      programId: 'p',
      expected: stored,
      before: before,
      after: after,
    );
    return (repos: repos, opened: stored, write: write);
  }

  test('an alternate of the group deleted elsewhere: the swap of a shown '
      'alternate is refused, so the old primary does not join the group '
      'above', () async {
    final elsewhere = [
      slot('q', 'dq'),
      slot('p', 'dp'),
      slot('a', 'da', alt: true),
    ];
    final r = await swapAfterChangeElsewhere(
      opened: [
        slot('q', 'dq'),
        slot('p', 'dp'),
        slot('x', 'dx', alt: true),
        slot('a', 'da', alt: true),
      ],
      swapIndex: 3,
      danceId: 'new',
      elsewhere: elsewhere,
    );
    final stored = (await r.repos.programs.getById('p'))!;
    expect(stored.slots.map((s) => (s.id, s.danceId, s.isAlt)), [
      ('q', 'dq', false),
      ('p', 'dp', false),
      ('a', 'da', true),
    ]);
    expect(r.write.refused, isTrue);
  });

  test('the primary cut elsewhere and its alternate promoted: a trade is '
      'refused, so the bailed-on dance does not land on a primary', () async {
    final r = await swapAfterChangeElsewhere(
      opened: [
        slot('p', 'dp'),
        slot('a', 'da', alt: true),
        slot('y', 'dy', alt: true),
      ],
      // Calling y (Show alternate) and choosing a's dance.
      swapIndex: 2,
      danceId: 'da',
      elsewhere: [slot('a', 'da'), slot('y', 'dy', alt: true)],
    );
    final stored = (await r.repos.programs.getById('p'))!;
    expect(stored.slots.map((s) => (s.id, s.danceId, s.isAlt)), [
      ('a', 'da', false),
      ('y', 'dy', true),
    ]);
    expect(r.write.refused, isTrue);
  });

  test('a change elsewhere that leaves the swap\'s slots alone does not stop '
      'it', () async {
    final r = await swapAfterChangeElsewhere(
      opened: [slot('p', 'dp'), slot('x', 'dx', alt: true), slot('c', 'dc')],
      swapIndex: 0,
      danceId: 'new',
      elsewhere: [
        slot('p', 'dp'),
        slot('x', 'dx', alt: true),
        slot('c', 'dc'),
        ProgramSlot(id: 'brk', position: 0, text: Program.breakSlotText),
      ],
    );
    expect(r.write.refused, isFalse);
    final stored = (await r.repos.programs.getById('p'))!;
    expect(stored.slots.map((s) => (s.id, s.danceId, s.isAlt)), [
      ('p', 'new', false),
      ('kept', 'dp', true),
      ('x', 'dx', true),
      ('c', 'dc', false),
      ('brk', null, false),
    ]);
  });

  final played = DateTime.utc(2026, 1, 1, 21);

  test('the swapped slot marked performed elsewhere: the swap is refused, so '
      'the new dance is not credited with that performance', () async {
    final r = await swapAfterChangeElsewhere(
      opened: [slot('p', 'dp'), slot('c', 'dc')],
      elsewhere: [
        slot('p', 'dp').copyWith(performedAt: played),
        slot('c', 'dc'),
      ],
    );
    final stored = (await r.repos.programs.getById('p'))!;
    expect(stored.slots.map((s) => (s.id, s.danceId)), [
      ('p', 'dp'),
      ('c', 'dc'),
    ]);
    expect(stored.slots.first.performedAt, played);
    expect(r.write.refused, isTrue);
  });

  test('the group\'s primary marked performed elsewhere: the swap of a shown '
      'alternate is refused, so a performed dance is not demoted', () async {
    final r = await swapAfterChangeElsewhere(
      opened: [slot('p', 'dp'), slot('a', 'da', alt: true)],
      swapIndex: 1,
      elsewhere: [
        slot('p', 'dp').copyWith(performedAt: played),
        slot('a', 'da', alt: true),
      ],
    );
    final stored = (await r.repos.programs.getById('p'))!;
    expect(stored.slots.map((s) => (s.id, s.danceId, s.isAlt)), [
      ('p', 'dp', false),
      ('a', 'da', true),
    ]);
    expect(r.write.refused, isTrue);
  });

  test('any change to a slot whose dance was replaced elsewhere is refused, '
      'so a mark performed is not stamped on the other dance', () async {
    final r = await swapAfterChangeElsewhere(
      opened: [slot('p', 'dp'), slot('c', 'dc')],
      edit: (before) => [before[0].copyWith(performedAt: played), before[1]],
      elsewhere: [slot('p', 'dz'), slot('c', 'dc')],
    );
    final stored = (await r.repos.programs.getById('p'))!;
    expect(stored.slots.first.danceId, 'dz');
    expect(stored.slots.first.performedAt, isNull);
    expect(r.write.refused, isTrue);
  });

  test(
    'a mark performed on a slot left alone elsewhere is still written',
    () async {
      final r = await swapAfterChangeElsewhere(
        opened: [slot('p', 'dp'), slot('c', 'dc')],
        edit: (before) => [before[0].copyWith(performedAt: played), before[1]],
        elsewhere: [slot('p', 'dp'), slot('c', 'dz')],
      );
      final stored = (await r.repos.programs.getById('p'))!;
      expect(stored.slots.first.performedAt, played);
      expect(stored.slots.last.danceId, 'dz');
      expect(r.write.refused, isFalse);
    },
  );
}
