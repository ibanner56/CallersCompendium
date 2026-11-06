import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// The four performance-tracking toggles (maintainer, 2026-11-05):
///
/// 1. recency counts only dated programs,
/// 2. recency counts only slots marked performed,
/// 3. the history order and Last called ignore undated programs,
/// 4. the history order and Last called ignore slots not marked performed.
///
/// Each is pinned on the SQL path (the Called filter's recency window, the
/// history order, the Last-called sort) against one fixture. The Dart mirrors
/// are pinned against the same SQL in `called_filter_scopes_test.dart`.
void main() {
  final now = DateTime.utc(2026, 1, 1);
  final cutoff = DateTime.utc(2026, 9, 1);

  late CompendiumDatabase db;
  late ProgramRepository programs;
  late DanceRepository dances;

  setUp(() async {
    db = openTestDatabase();
    programs = ProgramRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  Future<void> dance(String id) =>
      dances.create(Dance(id: id, title: id, createdAt: now, updatedAt: now));

  /// One program holding one slot of [danceId].
  Future<void> call(
    String id,
    String danceId, {
    DateTime? eventDate,
    DateTime? performedAt,
    required DateTime updatedAt,
  }) => programs.create(
    Program(
      id: id,
      title: id,
      eventDate: eventDate,
      slots: [
        ProgramSlot(
          id: '$id-slot',
          position: 0,
          danceId: danceId,
          performedAt: performedAt,
        ),
      ],
      createdAt: now,
      updatedAt: updatedAt,
    ),
  );

  // Four calls with every combination of dated / performed. Edit times differ
  // from the call dates, so the ordering shows which date each one used.
  //
  //   a: dated 10-01, performed   b: dated 10-05, not performed
  //   c: undated, performed 10-10, edited 10-20
  //   d: undated, not performed, edited 10-25
  Future<void> fourCallsOfOneDance() async {
    await dance('x');
    await call(
      'a',
      'x',
      eventDate: DateTime.utc(2026, 10, 1),
      performedAt: DateTime.utc(2026, 10, 1, 21),
      updatedAt: DateTime.utc(2026, 10, 2),
    );
    await call(
      'b',
      'x',
      eventDate: DateTime.utc(2026, 10, 5),
      updatedAt: DateTime.utc(2026, 10, 6),
    );
    await call(
      'c',
      'x',
      performedAt: DateTime.utc(2026, 10, 10, 21),
      updatedAt: DateTime.utc(2026, 10, 20),
    );
    await call('d', 'x', updatedAt: DateTime.utc(2026, 10, 25));
  }

  // The same four combinations as four dances with one call each.
  Future<void> fourDances() async {
    for (final (id, event, performed, edited) in [
      ('dp', DateTime.utc(2026, 10, 1), true, DateTime.utc(2026, 10, 2)),
      ('du', DateTime.utc(2026, 10, 2), false, DateTime.utc(2026, 10, 3)),
      ('up', null, true, DateTime.utc(2026, 10, 20)),
      ('uu', null, false, DateTime.utc(2026, 10, 25)),
    ]) {
      await dance(id);
      await call(
        'p-$id',
        id,
        eventDate: event,
        performedAt: performed ? DateTime.utc(2026, 10, 10, 21) : null,
        updatedAt: edited,
      );
    }
  }

  group('recency window', () {
    Future<Set<String>> calledSince({
      bool called = true,
      bool requireEventDate = true,
      bool requirePerformed = false,
    }) async => (await dances.search(
      CalledFilter(
        called: called,
        since: cutoff,
        tracking: CallingHistoryTracking(
          recencyRequireEventDate: requireEventDate,
          recencyRequirePerformed: requirePerformed,
        ),
      ),
    )).toSet();

    setUp(fourDances);

    test('by default only dated programs are in a window (toggle 1)', () async {
      expect(await calledSince(), {'dp', 'du'});
    });

    test('toggle 1 off dates an undated program by its last edit', () async {
      expect(await calledSince(requireEventDate: false), {
        'dp',
        'du',
        'up',
        'uu',
      });
    });

    test('toggle 2 on needs a performed slot', () async {
      expect(
        await calledSince(requireEventDate: false, requirePerformed: true),
        {'dp', 'up'},
      );
    });

    test('both on: both must hold', () async {
      expect(await calledSince(requirePerformed: true), {'dp'});
    });

    test('a slot outside every window still counts as called', () async {
      expect(await calledSince(called: false), {'up', 'uu'});
      final counts = await programs.countByDance();
      expect(counts.keys, containsAll(['dp', 'du', 'up', 'uu']));
    });

    test(
      'a global gate still excludes a slot the toggles would admit',
      () async {
        final ids = await dances.search(
          CalledFilter(
            called: true,
            since: cutoff,
            requireEventDate: true,
            tracking: const CallingHistoryTracking(
              recencyRequireEventDate: false,
            ),
          ),
        );
        expect(ids.toSet(), {'dp', 'du'});
      },
    );
  });

  group('history order', () {
    setUp(fourCallsOfOneDance);

    Future<List<String>> order({
      bool ignoreUndated = false,
      bool ignoreUnperformed = false,
    }) async => [
      for (final r in await programs.callingHistoryForDance(
        'x',
        tracking: CallingHistoryTracking(
          orderIgnoreUndated: ignoreUndated,
          orderIgnoreUnperformed: ignoreUnperformed,
        ),
      ))
        r.programId,
    ];

    test('by default every slot orders, newest first', () async {
      expect(await order(), ['d', 'c', 'b', 'a']);
    });

    test('toggle 3 sorts undated programs after every dated one', () async {
      expect(await order(ignoreUndated: true), ['b', 'a', 'c', 'd']);
    });

    test(
      'toggle 4 sorts unperformed slots after every performed one',
      () async {
        expect(await order(ignoreUnperformed: true), ['c', 'a', 'b', 'd']);
      },
    );

    test('both on: only dated, performed slots lead', () async {
      expect(await order(ignoreUndated: true, ignoreUnperformed: true), [
        'a',
        'b',
        'c',
        'd',
      ]);
    });

    test('the toggles never change what is listed or counted', () async {
      expect(
        await order(ignoreUndated: true, ignoreUnperformed: true),
        hasLength(4),
      );
      expect((await programs.countByDance())['x']!.all, 4);
    });

    test(
      'a global gate keeps excluding what the toggles would order',
      () async {
        final rows = await programs.callingHistoryForDance(
          'x',
          requireEventDate: true,
        );
        expect(rows.map((r) => r.programId), ['b', 'a']);
      },
    );
  });

  group('Last-called sort', () {
    setUp(fourDances);

    Future<List<String>> sorted({
      bool ignoreUndated = false,
      bool ignoreUnperformed = false,
    }) => dances.search(
      const AndFilter([]),
      sort: SearchSort.lastCalled,
      tracking: CallingHistoryTracking(
        orderIgnoreUndated: ignoreUndated,
        orderIgnoreUnperformed: ignoreUnperformed,
      ),
    );

    test('by default an undated program sorts by its last edit', () async {
      expect(await sorted(), ['uu', 'up', 'du', 'dp']);
    });

    test('toggle 3: undated calls give no date, so those dances sort '
        'with the never-called', () async {
      expect(await sorted(ignoreUndated: true), ['du', 'dp', 'up', 'uu']);
    });

    test('toggle 4: unperformed calls give no date', () async {
      expect(await sorted(ignoreUnperformed: true), ['up', 'dp', 'du', 'uu']);
    });

    test('both on: only dated, performed calls give a date', () async {
      expect(await sorted(ignoreUndated: true, ignoreUnperformed: true), [
        'dp',
        'du',
        'up',
        'uu',
      ]);
    });

    test('a dance with no ordering date still counts as called', () async {
      await sorted(ignoreUndated: true, ignoreUnperformed: true);
      expect((await programs.countByDance())['uu']!.all, 1);
    });
  });
}
