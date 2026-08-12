import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show QueryRow, Table, TableInfo;
import 'package:test/test.dart';

import 'test_database.dart';
import 'fixtures.dart';

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ProgramRepository programs;
  late ChoreographerRepository choreographers;
  late PublishedSourceRepository sources;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    programs = ProgramRepository(db);
    choreographers = ChoreographerRepository(db);
    sources = PublishedSourceRepository(db);
  });

  tearDown(() => db.close());

  test('hardDelete removes dances immediately and clears FTS', () async {
    final a = sampleDance(id: 'a', title: 'Alpha');
    final b = sampleDance(id: 'b', title: 'Bravo');
    await dances.create(a);
    await dances.create(b);

    await dances.hardDelete(['a']);

    expect(await dances.getById('a', includeDeleted: true), isNull);
    expect(await dances.getById('b'), isNotNull);
    // FTS row for the removed dance is gone.
    expect(await dances.searchText('Alpha'), isNot(contains('a')));
    expect(await dances.searchText('Bravo'), contains('b'));
  });

  test('hardDelete ignores unknown ids and an empty list', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));
    await dances.hardDelete(const []);
    await dances.hardDelete(['does-not-exist']);
    expect(await dances.getById('a'), isNotNull);
  });

  test('hardDelete tombstones a dance-only program slot with the dance title '
      '(#429, import-undo path)', () async {
    // Mirrors the purgeDeleted tombstone case for the separate hardDelete
    // (import-session undo) path: a slot whose ONLY content is its dance.
    // Without the cleanup, hardDelete's SET NULL would leave (danceId, text)
    // = (null, null) and corrupt every Programs load.
    await dances.create(sampleDance(id: 'd1', title: 'Doomed Dance'));
    await programs.create(
      Program(
        id: 'p1',
        title: 'Evening set',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    await dances.hardDelete(['d1']);

    final program = await programs.getById('p1');
    expect(program, isNotNull);
    expect(program!.slots.single.danceId, isNull);
    expect(program.slots.single.text, 'Doomed Dance');

    // No dangling references remain after the import-undo hard delete.
    final fkViolations = await db
        .customSelect('PRAGMA foreign_key_check')
        .get();
    expect(fkViolations, isEmpty);
  });

  test('hardDelete removes a surviving owner\'s relatedDance link when its '
      'target is deleted (#466, import-undo path)', () async {
    // Owner A links to target B via a relatedDance link. Hard-deleting only
    // B (the owner survives) must drop the now-meaningless orphan link rather
    // than leaving (relatedDance, targetDanceId=null), which corrupts A's
    // load.
    await dances.create(sampleDance(id: 'b', title: 'Target'));
    await dances.create(
      sampleDance(
        id: 'a',
        title: 'Owner',
        links: [
          DanceLink(id: 'l1', kind: LinkKind.relatedDance, targetDanceId: 'b'),
        ],
      ),
    );

    await dances.hardDelete(['b']);

    final owner = await dances.getById('a');
    expect(owner, isNotNull);
    expect(owner!.links, isEmpty);

    // listAll (batched link hydration) also succeeds, and no FK dangles.
    final all = await dances.listAll();
    expect(all.map((d) => d.id), ['a']);
    expect(all.single.links, isEmpty);
    final fkViolations = await db
        .customSelect('PRAGMA foreign_key_check')
        .get();
    expect(fkViolations, isEmpty);
  });

  group('purge and hard-delete reach .watch() subscribers (issue #768)', () {
    /// Collects a watched `SELECT COUNT(*)` over [table], the smallest probe
    /// that shows whether a raw write reached drift's stream machinery at all.
    ///
    /// These assert on a *stream*, not on the database — every one of them
    /// passes trivially if you query the table directly afterwards, because
    /// the SQL was always correct. What was missing was the notification, and
    /// a stream is the only thing that can observe its absence.
    /// [table] supplies BOTH the SQL identifier and the `readsFrom` target, so
    /// the query cannot end up counting one table while listening to another —
    /// a mismatch that would make these tests pass or fail for the wrong
    /// reason. Same single-source rule the repository writes now follow.
    Future<({List<int> seen, StreamSubscription<List<QueryRow>> sub})>
    watchCount(TableInfo<Table, dynamic> table) async {
      final seen = <int>[];
      final sub = db
          .customSelect(
            'SELECT COUNT(*) AS n FROM ${table.actualTableName}',
            readsFrom: {table},
          )
          .watch()
          .listen((rows) => seen.add(rows.single.read<int>('n')));
      // Let the initial value arrive so a later emit is a real change.
      await pumpEventQueue();
      return (seen: seen, sub: sub);
    }

    test(
      'a purge that orphans a choreographer notifies a choreographers watcher',
      () async {
        // The site with NO incidental cover: no WritePropagation rule targets
        // `choreographers`, so before the fix this watcher never heard about
        // the orphan GC's raw DELETE and kept reporting the removed row.
        // ignore: unused_result
        await choreographers.upsert(
          Choreographer(id: 'c1', name: 'Solo Author'),
        );
        await dances.create(
          sampleDance(id: 'd1', title: 'Only Dance', authorIds: const ['c1']),
        );
        final probe = await watchCount(db.choreographers);
        addTearDown(probe.sub.cancel);
        expect(probe.seen, [1]);

        await dances.softDelete('d1', at: DateTime.utc(2026, 2));
        await dances.purgeDeleted(now: DateTime.utc(2026, 6));
        await pumpEventQueue();

        expect(
          probe.seen.last,
          0,
          reason: 'the orphan GC removed the row; the watcher must see it',
        );
        expect(await choreographers.listAll(), isEmpty);
      },
    );

    test(
      'a purge that orphans a published source notifies a sources watcher',
      () async {
        await sources.upsert(PublishedSource(id: 's1', title: 'Zesty Contras'));
        await dances.create(
          sampleDance(
            id: 'd1',
            title: 'Only Citer',
            sourceCitations: [SourceCitation(sourceId: 's1')],
          ),
        );
        final probe = await watchCount(db.publishedSources);
        addTearDown(probe.sub.cancel);
        expect(probe.seen, [1]);

        await dances.softDelete('d1', at: DateTime.utc(2026, 2));
        await dances.purgeDeleted(now: DateTime.utc(2026, 6));
        await pumpEventQueue();

        expect(probe.seen.last, 0);
        expect(await sources.listAll(), isEmpty);
      },
    );

    test('the dangling-reference cleanup notifies a dance_links watcher on its '
        'own, without relying on the dances delete beside it', () async {
      // This site IS incidentally covered — a WritePropagation rule fires
      // `dances (delete) -> dance_links (delete)` from the native delete in
      // the same transaction. So this calls the private cleanup's public
      // entry point in isolation is impossible; instead assert the write is
      // attributed by checking a watcher scoped to dance_links ONLY sees the
      // link removal, which is what `updates:` now guarantees regardless of
      // what else the transaction happens to contain.
      await dances.create(sampleDance(id: 'b', title: 'Target'));
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Owner',
          links: [
            DanceLink(
              id: 'l1',
              kind: LinkKind.relatedDance,
              targetDanceId: 'b',
            ),
          ],
        ),
      );
      final probe = await watchCount(db.danceLinks);
      addTearDown(probe.sub.cancel);
      expect(probe.seen, [1]);

      await dances.hardDelete(['b']);
      await pumpEventQueue();

      expect(probe.seen.last, 0);
    });

    test(
      'CHARACTERISATION (cannot fail on omitted `updates:`): a purge notifies '
      'a program_slots watcher',
      () async {
        // Same incidental cover as the dance_links case above — see its comment.
        // This is the table the streams shipped in #924 actually read, so it is
        // worth pinning even though it is not a red-run-proven guard.
        await dances.create(sampleDance(id: 'd1', title: 'Called Once'));
        await programs.create(
          Program(
            id: 'p1',
            title: 'Friday',
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        // Counts slots still linked to a dance — what the calling-history and
        // called-count streams shipped in #924 actually read.
        final seen = <int>[];
        final sub = db
            .customSelect(
              'SELECT COUNT(*) AS n FROM ${db.programSlots.actualTableName} '
              'WHERE dance_id IS NOT NULL',
              readsFrom: {db.programSlots},
            )
            .watch()
            .listen((rows) => seen.add(rows.single.read<int>('n')));
        addTearDown(sub.cancel);
        await pumpEventQueue();
        expect(seen, [1]);

        await dances.softDelete('d1', at: DateTime.utc(2026, 2));
        await dances.purgeDeleted(now: DateTime.utc(2026, 6));
        await pumpEventQueue();

        expect(seen.last, 0);
      },
    );
  });
}
