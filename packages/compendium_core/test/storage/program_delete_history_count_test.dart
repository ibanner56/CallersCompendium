import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// LIFE-6 (maintainer decision 2026-10-30, "a"): the delete confirm names how
/// many dances lose a program from their calling history. The number must be the
/// one the history queries produce, so the core assertion here is the
/// agreement between [ProgramRepository.danceCountLosingHistory] and
/// [ProgramRepository.callingHistoryForDance] under every combination of the
/// three history settings, not a hand-counted constant.
void main() {
  final now = DateTime.utc(2026, 1, 1);
  final gig = DateTime.utc(2026, 3, 14);

  late CompendiumDatabase db;
  late ProgramRepository programs;
  late DanceRepository dances;

  const danceIds = ['a', 'b', 'c', 'd', 'e'];

  setUp(() async {
    db = openTestDatabase();
    programs = ProgramRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
    for (final id in danceIds) {
      await dances.create(
        Dance(id: id, title: 'Dance $id', createdAt: now, updatedAt: now),
      );
    }
  });

  tearDown(() => db.close());

  /// `a` twice (one dance, two slots), `b` performed, `c` an unperformed
  /// alternate (not history), `d` a performed alternate, a free-text slot.
  Program mixed({
    String id = 'p1',
    String? caller,
    DateTime? eventDate,
    bool trashed = false,
  }) => Program(
    id: id,
    title: 'Mixed $id',
    caller: caller,
    eventDate: eventDate,
    deletedAt: trashed ? now : null,
    slots: [
      ProgramSlot(id: '$id-a1', position: 0, danceId: 'a'),
      ProgramSlot(id: '$id-a2', position: 1, danceId: 'a'),
      ProgramSlot(id: '$id-b', position: 2, danceId: 'b', performedAt: gig),
      ProgramSlot(id: '$id-c', position: 3, danceId: 'c', isAlt: true),
      ProgramSlot(
        id: '$id-d',
        position: 4,
        danceId: 'd',
        isAlt: true,
        performedAt: gig,
      ),
      ProgramSlot(id: '$id-free', position: 5, text: 'Waltz'),
    ],
    createdAt: now,
    updatedAt: now,
  );

  Future<Set<String>> listedBy(
    String programId, {
    required bool performedOnly,
    required bool requireEventDate,
    String? callerFilter,
  }) async => {
    for (final id in danceIds)
      if ((await programs.callingHistoryForDance(
        id,
        performedOnly: performedOnly,
        requireEventDate: requireEventDate,
        callerFilter: callerFilter,
      )).any((r) => r.programId == programId))
        id,
  };

  test('counts distinct dances; unperformed alternates and free text are '
      'not history', () async {
    await programs.create(mixed());
    // a (two slots, one dance), b, d. Not c (unperformed alternate).
    expect(await programs.danceCountLosingHistory('p1'), 3);
  });

  test('performed-only drops the dances that were never marked', () async {
    await programs.create(mixed());
    expect(
      await programs.danceCountLosingHistory('p1', performedOnly: true),
      2, // b and d
    );
  });

  test('require-event-date makes an undated program lose nothing', () async {
    await programs.create(mixed());
    await programs.create(mixed(id: 'p2', eventDate: gig));
    expect(
      await programs.danceCountLosingHistory('p1', requireEventDate: true),
      0,
    );
    expect(
      await programs.danceCountLosingHistory('p2', requireEventDate: true),
      3,
    );
  });

  test('the caller filter excludes another caller\'s program but keeps an '
      'unattributed one', () async {
    await programs.create(mixed(id: 'mine', caller: ' ALICE '));
    await programs.create(mixed(id: 'theirs', caller: 'Bob'));
    await programs.create(mixed(id: 'blank'));
    expect(
      await programs.danceCountLosingHistory('mine', callerFilter: 'alice'),
      3,
    );
    expect(
      await programs.danceCountLosingHistory('theirs', callerFilter: 'alice'),
      0,
    );
    expect(
      await programs.danceCountLosingHistory('blank', callerFilter: 'alice'),
      3,
    );
  });

  test('a trashed or unknown program is in no one\'s history', () async {
    await programs.create(mixed(trashed: true));
    expect(await programs.danceCountLosingHistory('p1'), 0);
    expect(await programs.danceCountLosingHistory('nope'), 0);
  });

  test('another program holding the same dance does not change the count; '
      'it is per program', () async {
    await programs.create(mixed());
    await programs.create(mixed(id: 'p2'));
    expect(await programs.danceCountLosingHistory('p1'), 3);
  });

  test('agrees with callingHistoryForDance under every combination of the '
      'history settings', () async {
    await programs.create(mixed());
    await programs.create(mixed(id: 'p2', eventDate: gig, caller: 'Alice'));
    await programs.create(mixed(id: 'p3', caller: 'Bob'));
    await programs.create(mixed(id: 'p4', trashed: true));
    for (final programId in ['p1', 'p2', 'p3', 'p4']) {
      for (final performedOnly in [false, true]) {
        for (final requireEventDate in [false, true]) {
          for (final callerFilter in [null, 'alice']) {
            final reason =
                '$programId performedOnly=$performedOnly '
                'requireEventDate=$requireEventDate caller=$callerFilter';
            expect(
              await programs.danceCountLosingHistory(
                programId,
                performedOnly: performedOnly,
                requireEventDate: requireEventDate,
                callerFilter: callerFilter,
              ),
              (await listedBy(
                programId,
                performedOnly: performedOnly,
                requireEventDate: requireEventDate,
                callerFilter: callerFilter,
              )).length,
              reason: reason,
            );
          }
        }
      }
    }
  });
}
