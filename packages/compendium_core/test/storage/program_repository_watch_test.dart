import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// Tests for the reactive reads introduced by issue #768
/// ([ProgramRepository.watchCallingHistoryForDance] and
/// [ProgramRepository.watchProgramDerivedCounts]).
///
/// The interesting assertions here are the ones that write to `programs`
/// WITHOUT touching `program_slots` — a soft delete and its undo. Those are the
/// writes that fail silently if `programs` is missing from the streams'
/// declared `readsFrom` set: the query still returns the right rows when it is
/// re-run, so nothing looks broken, but nothing ever re-runs it. Drop
/// `_programDerivedTables` down to `{_db.programSlots}` and every test in this
/// file marked GUARD times out.
void main() {
  final now = DateTime.utc(2026, 1, 1);

  late CompendiumDatabase db;
  late ProgramRepository programs;
  late DanceRepository dances;

  setUp(() async {
    db = openTestDatabase();
    programs = ProgramRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
    await dances.create(
      Dance(
        id: 'd1',
        title: 'Chase the Squirrel',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await dances.create(
      Dance(id: 'd2', title: 'Petronella', createdAt: now, updatedAt: now),
    );
  });

  tearDown(() => db.close());

  Program program({
    required String id,
    String title = 'Spring Dance',
    List<ProgramSlot> slots = const [],
    DateTime? updatedAt,
  }) => Program(
    id: id,
    title: title,
    slots: slots,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );

  group('watchCallingHistoryForDance', () {
    test('emits the current history immediately on listen', () async {
      await programs.create(
        program(
          id: 'p1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      final probe = _Probe(programs.watchCallingHistoryForDance('d1'));
      addTearDown(probe.cancel);

      final first = await probe.next();
      expect(first.records.map((r) => r.slotId), ['s1']);
    });

    test('re-emits when a slot referencing the dance is added', () async {
      final probe = _Probe(programs.watchCallingHistoryForDance('d1'));
      addTearDown(probe.cancel);
      expect((await probe.next()).records, isEmpty);

      await programs.create(
        program(
          id: 'p1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );

      expect((await probe.next()).records.map((r) => r.slotId), ['s1']);
    });

    test(
      'GUARD re-emits when the program is soft-deleted — a write that touches '
      'the programs table only',
      () async {
        await programs.create(
          program(
            id: 'p1',
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
        );
        final probe = _Probe(programs.watchCallingHistoryForDance('d1'));
        addTearDown(probe.cancel);
        expect((await probe.next()).records, hasLength(1));

        await programs.softDelete('p1', at: DateTime.utc(2026, 2));

        expect((await probe.next()).records, isEmpty);
      },
    );

    test('GUARD re-emits when a soft-deleted program is restored — undo is a '
        'programs-only write too', () async {
      await programs.create(
        program(
          id: 'p1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      await programs.softDelete('p1', at: DateTime.utc(2026, 2));
      final probe = _Probe(programs.watchCallingHistoryForDance('d1'));
      addTearDown(probe.cancel);
      expect((await probe.next()).records, isEmpty);

      await programs.restore('p1', at: DateTime.utc(2026, 3));

      expect((await probe.next()).records.map((r) => r.slotId), ['s1']);
    });

    test('half-calling stats ride the same stream', () async {
      // A break slot is what makes the halves derivable, so the stats have
      // something to attribute (see [Program.halvesForSlots]).
      await programs.create(
        program(
          id: 'p1',
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 'b1', position: 1, text: Program.breakSlotText),
            ProgramSlot(id: 's2', position: 2, danceId: 'd2'),
          ],
        ),
      );
      final probe = _Probe(
        programs.watchCallingHistoryForDance('d1', performedOnly: true),
      );
      addTearDown(probe.cancel);
      expect((await probe.next()).halfStats.hasAny, isFalse);

      await programs.update(
        program(
          id: 'p1',
          updatedAt: DateTime.utc(2026, 2),
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 2),
            ),
            ProgramSlot(id: 'b1', position: 1, text: Program.breakSlotText),
            ProgramSlot(id: 's2', position: 2, danceId: 'd2'),
          ],
        ),
      );

      final after = await probe.next();
      expect(after.records.map((r) => r.slotId), ['s1']);
      expect(
        after.halfStats.hasAny,
        isTrue,
        reason:
            'the stats are derived from the same two tables, so they must '
            'arrive with the history rather than one emit later',
      );
    });

    test(
      'half-stats derived from the emitted rows equal the one-shot read, under '
      'both performedOnly settings',
      () async {
        // The case where the two program-id sets could diverge: `p2` contains
        // the dance but never performed it, so it is in
        // `halfCallingStatsForDance`'s id query yet absent from a
        // performed-only history. It must not change the answer.
        await programs.create(
          program(
            id: 'p1',
            slots: [
              ProgramSlot(
                id: 's1',
                position: 0,
                danceId: 'd1',
                performedAt: DateTime.utc(2026, 2),
              ),
              ProgramSlot(id: 'b1', position: 1, text: Program.breakSlotText),
              ProgramSlot(id: 's2', position: 2, danceId: 'd2'),
            ],
          ),
        );
        await programs.create(
          program(
            id: 'p2',
            title: 'Never performed',
            slots: [
              ProgramSlot(id: 's3', position: 0, danceId: 'd1'),
              ProgramSlot(id: 'b2', position: 1, text: Program.breakSlotText),
              ProgramSlot(id: 's4', position: 2, danceId: 'd2'),
            ],
          ),
        );

        for (final performedOnly in [false, true]) {
          final probe = _Probe(
            programs.watchCallingHistoryForDance(
              'd1',
              performedOnly: performedOnly,
            ),
          );
          addTearDown(probe.cancel);

          expect(
            (await probe.next()).halfStats,
            await programs.halfCallingStatsForDance(
              'd1',
              performedOnly: performedOnly,
            ),
            reason: 'performedOnly: $performedOnly',
          );
        }
      },
    );

    test('agrees with the one-shot read under performedOnly', () async {
      await programs.create(
        program(
          id: 'p1',
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(
              id: 's2',
              position: 1,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 2),
            ),
          ],
        ),
      );
      final probe = _Probe(
        programs.watchCallingHistoryForDance('d1', performedOnly: true),
      );
      addTearDown(probe.cancel);

      expect(
        (await probe.next()).records.map((r) => r.slotId),
        (await programs.callingHistoryForDance(
          'd1',
          performedOnly: true,
        )).map((r) => r.slotId),
      );
    });

    test('issue #340: one write produces exactly one emit', () async {
      await programs.create(
        program(
          id: 'p1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      final probe = _Probe(programs.watchCallingHistoryForDance('d1'));
      addTearDown(probe.cancel);
      await probe.next();
      final before = probe.values.length;

      // One `update` rewrites the whole slot list (delete-then-reinsert) inside
      // a single transaction; drift coalesces per transaction, so the multiple
      // statements must still reach a subscriber as ONE rebuild.
      await programs.update(
        program(
          id: 'p1',
          title: 'Spring Dance (rev)',
          updatedAt: DateTime.utc(2026, 2),
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
          ],
        ),
      );
      await probe.next();
      await probe.quiet();

      expect(probe.values.length - before, 1);
    });

    test('ignores writes about a different dance', () async {
      await programs.create(
        program(
          id: 'p1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      final probe = _Probe(programs.watchCallingHistoryForDance('d1'));
      addTearDown(probe.cancel);
      await probe.next();

      // A write to an unrelated table must not wake this stream at all.
      await dances.update(
        Dance(
          id: 'd2',
          title: 'Petronella (rev)',
          createdAt: now,
          updatedAt: DateTime.utc(2026, 2),
        ),
      );
      await probe.quiet();

      expect(probe.values, hasLength(1));
    });
  });

  group('watchProgramDerivedCounts', () {
    test('emits the current tallies immediately on listen', () async {
      await programs.create(
        program(
          id: 'p1',
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(
              id: 's2',
              position: 1,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 2),
            ),
          ],
        ),
      );
      final probe = _Probe(programs.watchProgramDerivedCounts());
      addTearDown(probe.cancel);

      final first = await probe.next();
      expect(first.callCounts['d1']?.all, 2);
      expect(first.callCounts['d1']?.performed, 1);
      expect(first.lastCalled['d1'], DateTime.utc(2026, 2));
    });

    test('re-emits when a dance is added to a program', () async {
      final probe = _Probe(programs.watchProgramDerivedCounts());
      addTearDown(probe.cancel);
      expect((await probe.next()).callCounts, isEmpty);

      await programs.create(
        program(
          id: 'p1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );

      expect((await probe.next()).callCounts['d1']?.all, 1);
    });

    test(
      'GUARD re-emits when the program is soft-deleted — a write that touches '
      'the programs table only',
      () async {
        await programs.create(
          program(
            id: 'p1',
            slots: [
              ProgramSlot(
                id: 's1',
                position: 0,
                danceId: 'd1',
                performedAt: DateTime.utc(2026, 2),
              ),
            ],
          ),
        );
        final probe = _Probe(programs.watchProgramDerivedCounts());
        addTearDown(probe.cancel);
        final first = await probe.next();
        expect(first.callCounts['d1']?.all, 1);
        expect(first.lastCalled, contains('d1'));

        await programs.softDelete('p1', at: DateTime.utc(2026, 3));

        final after = await probe.next();
        expect(after.callCounts, isEmpty);
        expect(
          after.lastCalled,
          isEmpty,
          reason:
              'last-called rides this stream, so it must be refreshed by the '
              'same emit rather than lag a write behind the counts',
        );
      },
    );

    test('each emit is one consistent snapshot: tallies and last-called move '
        'together', () async {
      await programs.create(
        program(
          id: 'p1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      final probe = _Probe(programs.watchProgramDerivedCounts());
      addTearDown(probe.cancel);
      final first = await probe.next();
      expect(first.callCounts['d1']?.performed, 0);
      expect(first.lastCalled, isNot(contains('d1')));

      // Marking the slot performed changes BOTH halves of the value. They
      // come from one query, so no emit can carry the new tally beside the
      // old timestamp (or the reverse) — which a second, separately-timed
      // read could produce.
      await programs.update(
        program(
          id: 'p1',
          updatedAt: DateTime.utc(2026, 2),
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 2),
            ),
          ],
        ),
      );

      final after = await probe.next();
      expect(after.callCounts['d1']?.performed, 1);
      expect(after.lastCalled['d1'], DateTime.utc(2026, 2));
    });

    test('agrees with the one-shot reads it shares a query with', () async {
      await programs.create(
        program(
          id: 'p1',
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 2),
            ),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
          ],
        ),
      );
      final probe = _Probe(programs.watchProgramDerivedCounts());
      addTearDown(probe.cancel);

      final emitted = await probe.next();
      expect(emitted.callCounts, await programs.countByDance());
      expect(emitted.lastCalled, await programs.lastCalledByDance());
      // d2 has been called but never performed, so it carries a tally and no
      // last-called stamp — the case the shared query has to get right, since
      // `MAX(performed_at)` returns NULL rather than dropping the row.
      expect(emitted.callCounts['d2']?.all, 1);
      expect(emitted.lastCalled, isNot(contains('d2')));
    });

    test('the one-shot sibling reads the same query, once', () async {
      await programs.create(
        program(
          id: 'p1',
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 2),
            ),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
          ],
        ),
      );

      final both = await programs.programDerivedCounts();
      expect(both.callCounts, await programs.countByDance());
      expect(both.lastCalled, await programs.lastCalledByDance());
    });

    test('issue #340: one write produces exactly one emit', () async {
      await programs.create(
        program(
          id: 'p1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      final probe = _Probe(programs.watchProgramDerivedCounts());
      addTearDown(probe.cancel);
      await probe.next();
      final before = probe.values.length;

      await programs.update(
        program(
          id: 'p1',
          updatedAt: DateTime.utc(2026, 2),
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, danceId: 'd1'),
          ],
        ),
      );
      await probe.next();
      await probe.quiet();

      expect(probe.values.length - before, 1);
    });
  });
}

/// Collects a stream's emissions and hands them out one at a time.
///
/// [next] resolves with the next value and FAILS THE TEST BY TIMEOUT if none
/// arrives, which is precisely the shape of the defect these tests guard: a
/// stream whose `readsFrom` set is missing a table does not error, it simply
/// never speaks again.
class _Probe<T> {
  _Probe(Stream<T> stream) {
    _sub = stream.listen((value) {
      values.add(value);
      final waiter = _waiter;
      if (waiter != null && !waiter.isCompleted) {
        _waiter = null;
        waiter.complete(value);
      }
    });
  }

  /// Every value seen so far, in order.
  final values = <T>[];
  late final StreamSubscription<T> _sub;
  Completer<T>? _waiter;
  int _taken = 0;

  /// The next unread emission — already-buffered if one is waiting, otherwise
  /// the next to arrive.
  Future<T> next() {
    if (_taken < values.length) return Future.value(values[_taken++]);
    final completer = Completer<T>();
    _waiter = completer;
    return completer.future
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
            'the stream never re-emitted: a write that should have refreshed '
            'this read did not reach a subscriber (check the readsFrom set)',
          ),
        )
        .whenComplete(() => _taken++);
  }

  /// Waits long enough for a stray extra emission to have shown up, so a test
  /// can assert that one did NOT (the over-firing side of issue #340).
  Future<void> quiet() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  Future<void> cancel() => _sub.cancel();
}
