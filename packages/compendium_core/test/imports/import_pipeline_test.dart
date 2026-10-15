import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import '../storage/test_database.dart';
import 'support/fake_adapter.dart';

String Function() sequentialIds() {
  var n = 0;
  return () => 'imported-${++n}';
}

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ChoreographerRepository choreographers;
  late DifficultyLevelRepository difficultyLevels;
  late ImportPipeline pipeline;
  late String Function() nextId;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    difficultyLevels = DifficultyLevelRepository(db);
    pipeline = ImportPipeline(
      dances,
      choreographers,
      difficultyLevels: difficultyLevels,
    );
    nextId = sequentialIds();
  });

  tearDown(() => db.close());

  final now = DateTime.utc(2026, 7, 15);

  Map<String, Object?> record(
    String id,
    String title, {
    List<Map<String, Object?>> figures = const [],
    String? version,
    String? permission,
    String? license,
    List<String> authorNames = const [],
    List<String> authorIds = const [],
    String? difficultyLevelLabel,
  }) => {
    'id': id,
    'title': title,
    'version': ?version,
    'permission': ?permission,
    'license': ?license,
    'authorNames': authorNames,
    'authorIds': authorIds,
    'difficultyLevelLabel': ?difficultyLevelLabel,
    'figures': figures,
  };

  group('plan cooperates with a busy event loop', () {
    List<Map<String, Object?>> records(int n) => [
      for (var i = 0; i < n; i++) record('r$i', 'Dance $i'),
    ];

    test('hands the event loop a turn while parsing a long batch', () async {
      // A timer fires only when the loop gets a real turn — a chain of
      // already-complete awaits (microtasks) never lets it. Each parse records
      // how many timer ticks had happened by then: if planning held the isolate
      // start to finish they would all read zero.
      var ticks = 0;
      final ticksSeenAtParse = <int>[];
      final adapter = _TickRecordingAdapter(
        records(40),
        () => ticks,
        ticksSeenAtParse,
      );
      final timer = Timer.periodic(Duration.zero, (_) => ticks++);
      addTearDown(timer.cancel);

      final batch = await pipeline.plan(
        adapter,
        const ImportRequest(),
        yieldInterval: Duration.zero,
      );

      expect(batch.records, hasLength(40));
      expect(ticksSeenAtParse.last, greaterThan(ticksSeenAtParse.first));
      expect(ticksSeenAtParse.toSet().length, greaterThan(5));
    });

    test('hands the event loop a turn while deduping a long batch', () async {
      // The dedupe loop's only await (`_dedupeAuthorNames`) completes as a
      // microtask when a draft carries author names, so without a real yield it
      // runs start to finish. Each `verdictFor` records the ticks seen so far.
      var ticks = 0;
      final ticksSeenAtDedupe = <int>[];
      final index = _TickRecordingIndex(
        [
          for (var i = 0; i < 2000; i++)
            DedupeEntry(
              danceId: 'existing-$i',
              title: 'Existing Title $i',
              authorNames: ['Author $i'],
            ),
        ],
        () => ticks,
        ticksSeenAtDedupe,
      );
      final timer = Timer.periodic(Duration.zero, (_) => ticks++);
      addTearDown(timer.cancel);

      final batch = await pipeline.plan(
        FakeSourceAdapter([
          for (var i = 0; i < 200; i++)
            record(
              'r$i',
              'Incoming Dance $i',
              authorNames: ['Incoming Author $i'],
            ),
        ]),
        const ImportRequest(),
        index: index,
        yieldInterval: Duration.zero,
      );

      expect(batch.records, hasLength(200));
      expect(ticksSeenAtDedupe, hasLength(200));
      expect(ticksSeenAtDedupe.last, greaterThan(ticksSeenAtDedupe.first));
      expect(ticksSeenAtDedupe.toSet().length, greaterThan(5));
    });

    test('dedupe does not yield with a long interval', () async {
      var ticks = 0;
      final seen = <int>[];
      final index = _TickRecordingIndex(const [], () => ticks, seen);
      final timer = Timer.periodic(Duration.zero, (_) => ticks++);
      addTearDown(timer.cancel);

      await pipeline.plan(
        FakeSourceAdapter([
          for (var i = 0; i < 40; i++)
            record('r$i', 'Dance $i', authorNames: ['A $i']),
        ]),
        const ImportRequest(),
        index: index,
        yieldInterval: const Duration(hours: 1),
      );

      expect(seen, hasLength(40));
      expect(seen.toSet(), {0});
    });

    test('with a long interval it does not pay for yielding', () async {
      var ticks = 0;
      final seen = <int>[];
      final adapter = _TickRecordingAdapter(records(40), () => ticks, seen);
      final timer = Timer.periodic(Duration.zero, (_) => ticks++);
      addTearDown(timer.cancel);

      await pipeline.plan(
        adapter,
        const ImportRequest(),
        yieldInterval: const Duration(hours: 1),
      );

      expect(seen.toSet(), {0}, reason: 'no record was preceded by a yield');
    });

    test(
      'reports progress as records are handled, ending at the total',
      () async {
        final events = <(int, int)>[];
        await pipeline.plan(
          FakeSourceAdapter(records(5)),
          const ImportRequest(),
          onProgress: (done, total) => events.add((done, total)),
        );
        expect(events.first, (1, 5));
        expect(events.last, (5, 5));
        expect([for (final e in events) e.$1], orderedEquals([1, 2, 3, 4, 5]));
        expect(events.every((e) => e.$2 == 5), isTrue);
      },
    );

    test('an empty source reports a single completed progress', () async {
      final events = <(int, int)>[];
      await pipeline.plan(
        FakeSourceAdapter(const []),
        const ImportRequest(),
        onProgress: (done, total) => events.add((done, total)),
      );
      expect(events, [(0, 0)]);
    });

    test('yielding does not change the planned result', () async {
      final input = records(12);
      final eager = await pipeline.plan(
        FakeSourceAdapter(input),
        const ImportRequest(),
        yieldInterval: Duration.zero,
      );
      final steady = await pipeline.plan(
        FakeSourceAdapter(input),
        const ImportRequest(),
        yieldInterval: const Duration(hours: 1),
      );
      expect(
        [for (final r in eager.records) r.draft.dance.title],
        [for (final r in steady.records) r.draft.dance.title],
      );
    });
  });

  group('commit writes provenance per record', () {
    test('commit reports progress per record, ending at the total', () async {
      final batch = await pipeline.plan(
        FakeSourceAdapter([
          for (var i = 0; i < 3; i++) record('p$i', 'Progress Dance $i'),
        ]),
        const ImportRequest(),
      );
      final events = <(int, int)>[];
      await pipeline.commit(
        batch,
        now: now,
        newId: nextId,
        onProgress: (done, total) => events.add((done, total)),
      );
      expect(events, [(1, 3), (2, 3), (3, 3), (3, 3)]);
    });

    test('resolves a matching configured custom difficulty label', () async {
      final custom = await difficultyLevels.createCustom(
        label: 'Workshop',
        position: 3,
      );
      final batch = await pipeline.plan(
        FakeSourceAdapter([
          record('custom-level', 'Custom Level Dance'),
        ], difficultyLevelLabel: ' workshop '),
        const ImportRequest(),
      );

      expect(batch.records.single.draft.dance.difficultyLevelId, custom.id);
      expect(
        batch.records.single.draft.issues.where(
          (issue) => issue.code == 'cc_unmapped_level',
        ),
        isEmpty,
      );
    });

    test(
      'prefers an exact configured label over a stale shipped alias mapping',
      () async {
        final advanced = await difficultyLevels.getById(
          DifficultyLevel.advancedId,
        );
        expect(advanced, isNotNull);
        await difficultyLevels.upsert(
          advanced!.copyWith(label: 'Expert'),
          at: now,
        );
        final custom = await difficultyLevels.createCustom(
          label: 'Advanced',
          position: 3,
        );

        final batch = await pipeline.plan(
          FakeSourceAdapter([
            record(
              'custom-alias',
              'Custom Alias Dance',
              difficultyLevelLabel: 'Advanced',
            )..['difficultyLevelId'] = DifficultyLevel.advancedId,
          ]),
          const ImportRequest(),
        );

        expect(batch.records.single.draft.dance.difficultyLevelId, custom.id);
        expect(
          batch.records.single.draft.issues.any(
            (issue) => issue.code == 'cc_inactive_level',
          ),
          isFalse,
        );
      },
    );

    test('does not resolve Mixed to a configured custom level', () async {
      final custom = await difficultyLevels.createCustom(
        label: 'Mixed',
        position: 3,
      );
      final batch = await pipeline.plan(
        FakeSourceAdapter([
          record('mixed-level', 'Mixed Level Dance')..['mixedLevel'] = true,
        ], difficultyLevelLabel: 'Mixed'),
        const ImportRequest(),
      );

      final draft = batch.records.single.draft;
      expect(draft.dance.mixedLevel, isTrue);
      expect(draft.dance.difficultyLevelId, isNull);
      expect(custom.id, isNotEmpty);
    });

    test(
      'two-argument construction preserves adapter difficulty mappings',
      () async {
        final legacyPipeline = ImportPipeline(dances, choreographers);
        final batch = await legacyPipeline.plan(
          FakeSourceAdapter([
            record('shipped-level', 'Shipped Level Dance')
              ..['difficultyLevelId'] = DifficultyLevel.intermediateId,
          ], difficultyLevelLabel: 'Intermediate'),
          const ImportRequest(),
        );

        final draft = batch.records.single.draft;
        expect(draft.dance.difficultyLevelId, DifficultyLevel.intermediateId);
        expect(
          draft.issues.any((issue) => issue.code == 'cc_inactive_level'),
          isFalse,
        );
      },
    );

    test('a new dance is inserted with a full provenance row', () async {
      final adapter = FakeSourceAdapter([
        record(
          'fake-1',
          'Rory OMore',
          version: 'v3',
          permission: 'full',
          license: 'CC-BY',
          figures: [
            {'beats': 16, 'text': 'balance and swing', 'move': 'swing'},
            {'beats': 8, 'text': 'give and take'},
          ],
        ),
      ]);

      final batch = await pipeline.plan(adapter, const ImportRequest());
      expect(batch.records.single.verdict.isNewDance, isTrue);
      expect(batch.records.single.draft.quality.score, 0.5);

      final session = await pipeline.commit(batch, now: now, newId: nextId);
      expect(session.committedCount, 1);

      final id = session.insertedDanceIds.single;
      final loaded = await dances.getById(id);
      expect(loaded, isNotNull);
      expect(loaded!.title, 'Rory OMore');
      final prov = loaded.provenance!;
      expect(prov.source, ProvenanceSource.json);
      expect(prov.externalId, 'fake-1');
      expect(prov.importedAt, now);
      expect(prov.permission, 'full');
      expect(prov.license, 'CC-BY');
      expect(prov.sourceVersion, 'v3');
    });

    test('tombstoned shipped levels are cleared before commit', () async {
      await difficultyLevels.delete(DifficultyLevel.advancedId, at: now);
      final batch = await pipeline.plan(
        FakeSourceAdapter([
          record('deleted-level', 'Deleted Level Dance')
            ..['difficultyLevelId'] = DifficultyLevel.advancedId,
        ], difficultyLevelLabel: 'Advanced'),
        const ImportRequest(),
      );

      final draft = batch.records.single.draft;
      expect(draft.dance.difficultyLevelId, isNull);
      expect(
        draft.issues.any((issue) => issue.code == 'cc_inactive_level'),
        isTrue,
      );

      final session = await pipeline.commit(batch, now: now, newId: nextId);
      expect(session.records.single.succeeded, isTrue);
      expect((await dances.listAll()).single.difficultyLevelId, isNull);
    });

    test('custom-figure text is searchable after commit', () async {
      final adapter = FakeSourceAdapter([
        record(
          'fake-2',
          'Custom Only',
          figures: [
            {'beats': 16, 'text': 'weave the star basket'},
          ],
        ),
      ]);
      final batch = await pipeline.plan(adapter, const ImportRequest());
      final session = await pipeline.commit(batch, now: now, newId: nextId);
      final id = session.insertedDanceIds.single;
      final hits = await dances.searchText('basket');
      expect(hits, contains(id));
    });
  });

  group('defaultTagIds (issue #1476)', () {
    late TagRepository tags;
    late String smooth;
    late String noCard;

    setUp(() async {
      tags = TagRepository(db);
      smooth = await tags.upsert(Tag(id: 'tag-smooth', name: 'Smooth'));
      noCard = await tags.upsert(Tag(id: 'tag-no-card', name: 'No card'));
    });

    Future<ImportBatchResult> planOne(String title) => pipeline.plan(
      FakeSourceAdapter([record('fake-$title', title)]),
      const ImportRequest(),
    );

    Future<int> joinRows(String danceId) async =>
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM dance_tags WHERE dance_id = ?',
                  variables: [Variable<String>(danceId)],
                )
                .getSingle())
            .read<int>('n');

    test('a created dance receives them, in the given order', () async {
      final session = await pipeline.commit(
        await planOne('Fresh'),
        now: now,
        newId: nextId,
        defaultTagIds: [noCard, smooth],
      );
      final dance = (await dances.getById(session.insertedDanceIds.single))!;
      expect(dance.tagIds, [noCard, smooth]);
    });

    test('omitting them leaves the dance untagged (program and archive '
        'callers rely on this default)', () async {
      final session = await pipeline.commit(
        await planOne('Fresh'),
        now: now,
        newId: nextId,
      );
      final dance = (await dances.getById(session.insertedDanceIds.single))!;
      expect(dance.tagIds, isEmpty);
    });

    test(
      'tags the draft already carries are kept, first and not duplicated',
      () async {
        final batch = await planOne('Fresh');
        final plan = batch.records.single;
        final withOwnTag = ImportBatchResult(
          records: [
            ImportRecordPlan(
              draft: plan.draft.copyWith(
                dance: plan.draft.dance.copyWith(tagIds: [smooth]),
              ),
              verdict: plan.verdict,
            ),
          ],
        );
        final session = await pipeline.commit(
          withOwnTag,
          now: now,
          newId: nextId,
          defaultTagIds: [noCard, smooth],
        );
        final dance = (await dances.getById(session.insertedDanceIds.single))!;
        expect(dance.tagIds, [smooth, noCard]);
      },
    );

    test('a variation (a new dance) receives them', () async {
      final seed = await pipeline.commit(
        await planOne('The Nice Combination'),
        now: now,
        newId: nextId,
      );
      final existingId = seed.insertedDanceIds.single;
      final session = await pipeline.commit(
        await planOne('Nice Combination'),
        now: now,
        newId: nextId,
        resolutions: {0: DedupeResolution.variation(existingId)},
        defaultTagIds: [noCard],
      );
      final created = (await dances.getById(session.records.single.danceId!))!;
      expect(created.tagIds, [noCard]);
      // The target is only link-edited; it is not a new dance.
      expect((await dances.getById(existingId))!.tagIds, isEmpty);
    });

    test('a re-import of an existing dance does not receive them', () async {
      final first = await pipeline.commit(
        await planOne('Fresh'),
        now: now,
        newId: nextId,
      );
      final id = first.insertedDanceIds.single;
      final again = await planOne('Fresh');
      expect(again.records.single.verdict.isReimport, isTrue);
      final second = await pipeline.commit(
        again,
        now: now,
        newId: nextId,
        defaultTagIds: [noCard],
      );
      expect(second.insertedDanceIds, isEmpty);
      expect((await dances.getById(id))!.tagIds, isEmpty);
    });

    test(
      'undo removes the new dance and its tag joins, and keeps the tag',
      () async {
        final session = await pipeline.commit(
          await planOne('Fresh'),
          now: now,
          newId: nextId,
          defaultTagIds: [noCard],
        );
        final id = session.insertedDanceIds.single;
        expect(await joinRows(id), 1);

        await pipeline.undo(session);

        expect(await dances.getById(id), isNull);
        expect(await joinRows(id), 0);
        expect(await tags.getById(noCard), isNotNull);
      },
    );

    test(
      'an id with no tag row fails that record and leaves no dance behind',
      () async {
        final session = await pipeline.commit(
          await planOne('Fresh'),
          now: now,
          newId: nextId,
          defaultTagIds: ['no-such-tag'],
        );
        expect(session.records.single.succeeded, isFalse);
        expect(await dances.listAll(), isEmpty);
      },
    );
  });

  group('re-import by (source, externalId)', () {
    test('updates the same dance + provenance, preserving createdAt', () async {
      final first = FakeSourceAdapter([
        record('fake-1', 'Original Title', version: 'v1'),
      ]);
      final s1 = await pipeline.commit(
        await pipeline.plan(first, const ImportRequest()),
        now: now,
        newId: nextId,
      );
      final id = s1.insertedDanceIds.single;
      final created = (await dances.getById(id))!.createdAt;

      // Re-fetch the same external record, changed title + version.
      final again = FakeSourceAdapter([
        record('fake-1', 'Revised Title', version: 'v2'),
      ]);
      final later = DateTime.utc(2026, 8, 1);
      final batch = await pipeline.plan(again, const ImportRequest());
      expect(batch.records.single.verdict.isReimport, isTrue);
      expect(batch.records.single.verdict.targetDanceId, id);

      final s2 = await pipeline.commit(batch, now: later, newId: nextId);
      expect(s2.insertedDanceIds, isEmpty);

      final reloaded = (await dances.getById(id))!;
      expect(reloaded.title, 'Revised Title');
      expect(reloaded.createdAt, created);
      expect(reloaded.provenance!.sourceVersion, 'v2');
      expect(reloaded.provenance!.importedAt, later);
      // Exactly one dance exists (no duplicate inserted).
      expect((await dances.listAll()).length, 1);
    });
  });

  group('fuzzy ambiguous match', () {
    Future<String> seedExisting() async {
      final adapter = FakeSourceAdapter([
        record('fake-1', 'The Nice Combination'),
      ]);
      final s = await pipeline.commit(
        await pipeline.plan(adapter, const ImportRequest()),
        now: now,
        newId: nextId,
      );
      return s.insertedDanceIds.single;
    }

    test(
      'unresolved ambiguous record is skipped (no silent mutation)',
      () async {
        final existingId = await seedExisting();
        final incoming = FakeSourceAdapter([
          record('fake-2', 'Nice Combination'),
        ]);
        final batch = await pipeline.plan(incoming, const ImportRequest());
        expect(batch.records.single.verdict.isAmbiguous, isTrue);

        final session = await pipeline.commit(batch, now: now, newId: nextId);
        expect(session.records.single.action, CommitAction.skip);
        // Only the seeded dance remains untouched.
        final all = await dances.listAll();
        expect(all.length, 1);
        expect(all.single.id, existingId);
        expect(all.single.title, 'The Nice Combination');
      },
    );

    test('resolution link updates the chosen existing dance', () async {
      final existingId = await seedExisting();
      final incoming = FakeSourceAdapter([
        record('fake-2', 'Nice Combination'),
      ]);
      final batch = await pipeline.plan(incoming, const ImportRequest());
      final session = await pipeline.commit(
        batch,
        now: now,
        newId: nextId,
        resolutions: {0: DedupeResolution.link(existingId)},
      );
      expect(session.records.single.action, CommitAction.link);
      final all = await dances.listAll();
      expect(all.length, 1);
      expect(all.single.id, existingId);
      expect(all.single.title, 'Nice Combination');
    });

    test('resolution duplicate imports a separate new dance', () async {
      await seedExisting();
      final incoming = FakeSourceAdapter([
        record('fake-2', 'Nice Combination'),
      ]);
      final batch = await pipeline.plan(incoming, const ImportRequest());
      final session = await pipeline.commit(
        batch,
        now: now,
        newId: nextId,
        resolutions: {0: DedupeResolution.duplicate()},
      );
      expect(session.records.single.action, CommitAction.duplicate);
      expect((await dances.listAll()).length, 2);
    });
  });

  group('autoResolveAmbiguous', () {
    test('never links on a title that normalizes to nothing', () async {
      // '花' and '月' both fold to '' under `normalizeTitle`, and two dances
      // with no figures have equal choreography fingerprints — so the
      // exact-normalized-title gate passed on '' == '' and the content check
      // then linked two unrelated dances. The verdict is hand-built because
      // fuzzy scoring no longer produces one for empty titles; this guards the
      // resolver itself against any caller that does.
      final seeded = await pipeline.commit(
        await pipeline.plan(
          FakeSourceAdapter([record('fake-1', '花')]),
          const ImportRequest(),
        ),
        now: now,
        newId: nextId,
      );
      final existingId = seeded.insertedDanceIds.single;

      final adapter = FakeSourceAdapter([record('fake-2', '月')]);
      final discovered = await adapter.discover(const ImportRequest());
      final draft = adapter.parse(await adapter.fetch(discovered.single));
      final batch = ImportBatchResult(
        records: [
          ImportRecordPlan(
            draft: draft,
            verdict: DedupeVerdict.ambiguous([
              DedupeCandidate(danceId: existingId, score: 1.0),
            ]),
          ),
        ],
      );

      final resolutions = await pipeline.autoResolveAmbiguous(
        batch,
        authorNamesOf: (_) => const [],
      );
      expect(resolutions[0]?.kind, DedupeResolutionKind.duplicate);
    });
  });

  group('variation resolution (issue #686)', () {
    // #686: a confident title+author match whose figures DIFFER resolves to
    // `.variation` — a distinct new dance, optionally linked back to the
    // matched dance. Deliberately distinct from `.duplicate` (no link) and
    // never used for the identical-figures case, which stays `.skip`/`.link`
    // (#685, unchanged) — see `figure_diff.dart`/`program_import_online_resolver.dart`.
    Future<String> seedExisting() async {
      final adapter = FakeSourceAdapter([
        record('fake-1', 'The Nice Combination'),
      ]);
      final s = await pipeline.commit(
        await pipeline.plan(adapter, const ImportRequest()),
        now: now,
        newId: nextId,
      );
      return s.insertedDanceIds.single;
    }

    test('linkBack: true creates a new dance AND a symmetric relatedDance link '
        'pair', () async {
      final existingId = await seedExisting();
      final incoming = FakeSourceAdapter([
        record('fake-2', 'Nice Combination'),
      ]);
      final batch = await pipeline.plan(incoming, const ImportRequest());
      final session = await pipeline.commit(
        batch,
        now: now,
        newId: nextId,
        resolutions: {0: DedupeResolution.variation(existingId)},
      );
      expect(session.records.single.action, CommitAction.variation);
      final newId = session.records.single.danceId!;
      expect((await dances.listAll()).length, 2);

      final newDance = (await dances.getById(newId))!;
      expect(newDance.links, hasLength(1));
      expect(newDance.links.single.kind, LinkKind.relatedDance);
      expect(newDance.links.single.targetDanceId, existingId);

      final target = (await dances.getById(existingId))!;
      expect(target.links, hasLength(1));
      expect(target.links.single.kind, LinkKind.relatedDance);
      expect(target.links.single.targetDanceId, newId);
    });

    test(
      'linkBack: false creates a new dance with no links either side',
      () async {
        final existingId = await seedExisting();
        final incoming = FakeSourceAdapter([
          record('fake-2', 'Nice Combination'),
        ]);
        final batch = await pipeline.plan(incoming, const ImportRequest());
        final session = await pipeline.commit(
          batch,
          now: now,
          newId: nextId,
          resolutions: {
            0: DedupeResolution.variation(existingId, linkBack: false),
          },
        );
        expect(session.records.single.action, CommitAction.variation);
        final newId = session.records.single.danceId!;

        final newDance = (await dances.getById(newId))!;
        expect(newDance.links, isEmpty);
        final target = (await dances.getById(existingId))!;
        expect(target.links, isEmpty);
      },
    );

    test('undo fully reverts both sides: the new dance is deleted and the '
        "target's prior (unlinked) state is restored", () async {
      final existingId = await seedExisting();
      final incoming = FakeSourceAdapter([
        record('fake-2', 'Nice Combination'),
      ]);
      final batch = await pipeline.plan(incoming, const ImportRequest());
      final session = await pipeline.commit(
        batch,
        now: now,
        newId: nextId,
        resolutions: {0: DedupeResolution.variation(existingId)},
      );
      final newDanceId = session.records.single.danceId!;
      expect((await dances.listAll()).length, 2);
      expect((await dances.getById(existingId))!.links, isNotEmpty);

      await pipeline.undo(session);

      expect(await dances.getById(newDanceId), isNull);
      final restoredTarget = (await dances.getById(existingId))!;
      expect(restoredTarget.links, isEmpty);
    });
  });

  group('partial-batch tolerance & structured errors', () {
    test('a failed fetch is reported; the rest import', () async {
      final adapter = FakeSourceAdapter(
        [
          record('ok-1', 'Good One'),
          record('bad', 'Never Fetched'),
          record('ok-2', 'Good Two'),
        ],
        failFetchExternalIds: {'bad'},
      );
      final batch = await pipeline.plan(adapter, const ImportRequest());
      expect(batch.records.length, 2);
      expect(batch.errors.length, 1);
      final err = batch.errors.single;
      expect(err.stage, ImportStage.fetch);
      expect(err.externalId, 'bad');
      expect(err.toString(), isNot(contains('#0'))); // no stack trace

      final session = await pipeline.commit(batch, now: now, newId: nextId);
      expect(session.committedCount, 2);
    });

    test('an invalid payload yields a structured parse error', () async {
      // A record with no title triggers a parse ImportError in the adapter.
      final adapter = FakeSourceAdapter([
        {'id': 'no-title', 'figures': const []},
      ]);
      final batch = await pipeline.plan(adapter, const ImportRequest());
      expect(batch.records, isEmpty);
      expect(batch.errors.single.stage, ImportStage.parse);
      expect(batch.errors.single.externalId, 'no-title');
    });

    test('a discovery failure aborts the whole batch as one error', () async {
      final adapter = FakeSourceAdapter([], discoverThrows: true);
      final batch = await pipeline.plan(adapter, const ImportRequest());
      expect(batch.records, isEmpty);
      expect(batch.errors.single.stage, ImportStage.discover);
    });

    test('a second record with the same (source, externalId) in one batch is '
        'dropped, and the kept record says so', () async {
      // The dedupe index is a pre-batch snapshot, so both copies were `isNew`
      // and both were created — two dances with one provenance key, which a
      // later re-import could then only match one of.
      final adapter = FakeSourceAdapter([
        record('dup', 'First Copy'),
        record('other', 'Other Dance'),
        record('dup', 'Second Copy'),
      ]);
      final batch = await pipeline.plan(adapter, const ImportRequest());

      expect(batch.errors, isEmpty);
      expect(batch.records.map((r) => r.draft.dance.title), [
        'First Copy',
        'Other Dance',
      ], reason: 'the first occurrence is kept, in discovery order');
      final kept = batch.records.first.draft;
      final issue = kept.issues.singleWhere(
        (i) => i.code == 'duplicate_external_id_in_batch',
      );
      expect(issue.severity, ImportIssueSeverity.warning);
      expect(
        batch.records[1].draft.issues.map((i) => i.code),
        isNot(contains('duplicate_external_id_in_batch')),
      );

      final session = await pipeline.commit(batch, now: now, newId: nextId);
      expect(session.committedCount, 2);
      final all = await dances.listAll();
      expect(
        all.where((d) => d.provenance?.externalId == 'dup'),
        hasLength(1),
        reason: 'one dance per (source, externalId)',
      );
    });

    test('two records from different sources that only share a legacy alias '
        'do not both reimport the same dance', () async {
      // Pre-namespacing behaviour recorded a bundled dance under its bare
      // upstream id, regardless of which upstream source it came from — so
      // a library that received one dance under the old scheme holds a
      // legacy `(json, "457")` row. A bundle can now contain a *different*
      // dance from each of two upstream sources that both used id 457; each
      // independently falls back to that same bare alias, and letting both
      // reimport would overwrite the one existing dance twice and map two
      // program slots onto it (row 2's data-loss case).
      await dances.create(
        Dance(
          id: 'existing',
          title: 'Old Title',
          provenance: Provenance(
            source: ProvenanceSource.json,
            externalId: '457',
            importedAt: now,
          ),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // GenericJsonAdapter's own RawRecord.source is always `json` (the
      // *receiving* adapter's source); the upstream source only shows up
      // namespaced into the externalId, which is what these two ids model.
      final adapter = FakeSourceAdapter(
        [
          record('contradb:457', 'Fresh From ContraDB'),
          record('callersbox:457', 'Fresh From Callers Box'),
        ],
        priorExternalIdsById: {
          'contradb:457': const ['457'],
          'callersbox:457': const ['457'],
        },
      );
      final batch = await pipeline.plan(adapter, const ImportRequest());

      expect(batch.errors, isEmpty);
      expect(batch.records, hasLength(2));
      expect(
        batch.records.map((r) => r.verdict.kind),
        everyElement(isNot(DedupeKind.reimport)),
        reason:
            'a legacy alias claimed by two distinct current keys in this '
            'batch must not resolve either of them to a reimport of the '
            'same existing dance',
      );
    });
  });

  group('undo', () {
    test('removes freshly inserted dances', () async {
      final adapter = FakeSourceAdapter([
        record('fake-1', 'One'),
        record('fake-2', 'Two'),
      ]);
      final session = await pipeline.commit(
        await pipeline.plan(adapter, const ImportRequest()),
        now: now,
        newId: nextId,
      );
      expect((await dances.listAll()).length, 2);

      await pipeline.undo(session);
      expect(await dances.listAll(), isEmpty);
      expect(session.isUndone, isTrue);

      // Idempotent.
      await pipeline.undo(session);
      expect(await dances.listAll(), isEmpty);
    });

    test('restores an updated dance to its prior state', () async {
      final first = FakeSourceAdapter([record('fake-1', 'Before')]);
      final s1 = await pipeline.commit(
        await pipeline.plan(first, const ImportRequest()),
        now: now,
        newId: nextId,
      );
      final id = s1.insertedDanceIds.single;

      final again = FakeSourceAdapter([record('fake-1', 'After')]);
      final s2 = await pipeline.commit(
        await pipeline.plan(again, const ImportRequest()),
        now: DateTime.utc(2026, 9, 1),
        newId: nextId,
      );
      expect((await dances.getById(id))!.title, 'After');

      await pipeline.undo(s2);
      final restored = (await dances.getById(id))!;
      expect(restored.title, 'Before');
    });

    test('restores a dance two rows linked to in one batch to its true '
        'pre-import state, not the intermediate one', () async {
      final seeded = await pipeline.commit(
        await pipeline.plan(
          FakeSourceAdapter([record('fake-1', 'The Nice Combination')]),
          const ImportRequest(),
        ),
        now: now,
        newId: nextId,
      );
      final targetId = seeded.insertedDanceIds.single;

      // Two review rows (both fuzzy-ambiguous against the seeded dance), both
      // resolved "Link to <The Nice Combination>". The prior state captured
      // for the second link is the first link's result, so a forward-order
      // restore left the dance at 'Nice Combination'.
      final batch = await pipeline.plan(
        FakeSourceAdapter([
          record('fake-2', 'Nice Combination'),
          record('fake-3', 'A Nice Combination'),
        ]),
        const ImportRequest(),
      );
      expect(batch.records.map((r) => r.verdict.isAmbiguous), [true, true]);
      final session = await pipeline.commit(
        batch,
        now: DateTime.utc(2026, 9, 1),
        newId: nextId,
        resolutions: {
          0: DedupeResolution.link(targetId),
          1: DedupeResolution.link(targetId),
        },
      );
      expect(session.records.map((r) => r.action), [
        CommitAction.link,
        CommitAction.link,
      ]);
      expect((await dances.getById(targetId))!.title, 'A Nice Combination');

      await pipeline.undo(session);
      expect((await dances.getById(targetId))!.title, 'The Nice Combination');
    });
    group('author name resolution', () {
      Future<List<String>> authorNamesOf(String danceId) async {
        final dance = (await dances.getById(danceId))!;
        final names = <String>[];
        for (final id in dance.authorIds) {
          final c = await choreographers.getById(id);
          if (c != null) names.add(c.name);
        }
        return names;
      }

      test('matches an existing choreographer (no new row created)', () async {
        // ignore: unused_result
        await choreographers.upsert(
          Choreographer(id: 'gene', name: 'Gene Hubert'),
        );
        final adapter = FakeSourceAdapter([
          record('fake-1', 'A Dance', authorNames: ['Gene Hubert']),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        final id = session.insertedDanceIds.single;
        expect((await dances.getById(id))!.authorIds, ['gene']);
        expect(session.createdChoreographerIds, isEmpty);
        final res = session.records.single.authorResolutions.single;
        expect(res.choreographerId, 'gene');
        expect(res.created, isFalse);
        expect(await choreographers.listAll(), hasLength(1));
      });

      test('creates a new choreographer when no match exists', () async {
        final adapter = FakeSourceAdapter([
          record('fake-1', 'A Dance', authorNames: ['Baby Caller']),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        final id = session.insertedDanceIds.single;
        expect(await authorNamesOf(id), ['Baby Caller']);
        expect(session.createdChoreographerIds, hasLength(1));
        expect(session.records.single.authorResolutions.single.created, isTrue);
      });

      /// Raw `existence_at` for a choreographer, bypassing the repository's
      /// live-row filter so a tombstoned row is still readable.
      Future<int?> existenceOf(String id) async {
        final rows = await db
            .customSelect(
              "SELECT existence_at AS v FROM choreographers WHERE id = ?",
              variables: [Variable.withString(id)],
            )
            .get();
        return rows.single.data['v'] as int?;
      }

      test('adopts a tombstoned choreographer rather than wiring dances to a '
          'phantom id', () async {
        // Schema v25: `choreographers.name` is UNIQUE and a soft-deleted row
        // still occupies its name, so importing that name adopts the tombstone
        // and `upsert` returns the tombstone's id, not the minted one. Using
        // the minted id would point `dance_authors` at a row that does not
        // exist; the FK makes that a failed insert rather than silent
        // corruption, but the import still breaks on an ordinary action.
        // ignore: unused_result
        await choreographers.upsert(
          Choreographer(id: 'ghost', name: 'Baby Caller'),
        );
        await choreographers.delete('ghost');
        expect(await choreographers.listAll(), isEmpty);

        final adapter = FakeSourceAdapter([
          record('fake-1', 'A Dance', authorNames: ['Baby Caller']),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );

        final danceId = session.insertedDanceIds.single;
        expect(await authorNamesOf(danceId), ['Baby Caller']);

        final resolution = session.records.single.authorResolutions.single;
        expect(
          resolution.choreographerId,
          'ghost',
          reason: 'the adopted row keeps its id; the minted one is discarded',
        );

        // Undo must not offer to hard-delete a record it did not create. The
        // row predates this import — the user had merely deleted it — so
        // erasing it on undo would destroy something still restorable.
        expect(
          session.createdChoreographerIds,
          isEmpty,
          reason: 'adopting an existing tombstone is not a creation',
        );
        expect(resolution.created, isFalse);
        expect(session.revivedChoreographerIds, [
          'ghost',
        ], reason: 'undo needs to know the import resurrected this row');
      });

      test('undo re-tombstones a choreographer the import resurrected', () async {
        // The other half of adoption, and the case that was missed: the upsert
        // clears `deleted_at`, so importing a name a tombstone still held
        // brings that author back to life. Undo used to leave it live — the
        // author reappeared permanently after a rolled-back import — and the
        // revival had stamped `existence_at` strictly past the user's deletion,
        // so once a sync client exists the resurrection would outrank that
        // deletion on every peer.
        //
        // Undo must return it to the state it was in (deleted), NOT erase it:
        // the row predates the import and the user may still restore it.
        // ignore: unused_result
        await choreographers.upsert(
          Choreographer(id: 'ghost', name: 'Baby Caller'),
        );
        await choreographers.delete('ghost');

        final adapter = FakeSourceAdapter([
          record('fake-1', 'A Dance', authorNames: ['Baby Caller']),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        expect(
          await choreographers.getById('ghost'),
          isNotNull,
          reason: 'the import revived it — that is the state undo must revert',
        );
        final revivedExistence = await existenceOf('ghost');

        await pipeline.undo(session);

        expect(
          await choreographers.getById('ghost'),
          isNull,
          reason: 'a rolled-back import must not leave the author resurrected',
        );
        expect(await choreographers.listAll(), isEmpty);
        // Tombstoned, not erased: the user can still restore what they deleted.
        final rows = await db
            .customSelect(
              "SELECT deleted_at, existence_at FROM choreographers "
              "WHERE id = 'ghost'",
            )
            .get();
        expect(
          rows,
          hasLength(1),
          reason: 'undo must not destroy a record that predates the import',
        );
        expect(rows.single.data['deleted_at'], isNotNull);
        // The point of the fix, and the part `deleted_at` alone does not pin:
        // the re-tombstone must OUTRANK the revival it reverts. §6.4 orders
        // existence by `existence_at` and resolves a tie in favour of the
        // tombstone — so a re-tombstone that merely tied would still lose to
        // the revival on a peer, and a refactor that restored the original
        // `deleted_at` with a raw UPDATE would pass every other assertion here
        // while reinstating exactly the defect this test is named for.
        expect(
          rows.single.data['existence_at'] as int,
          greaterThan(revivedExistence!),
          reason: 'the re-tombstone must strictly outrank the revival',
        );
      });

      test(
        'undo leaves a resurrected author live if a surviving dance credits it',
        () async {
          // The referential guard still wins: re-tombstoning must not orphan a
          // credit on a dance this import did not insert.
          // ignore: unused_result
          await choreographers.upsert(
            Choreographer(id: 'ghost', name: 'Baby Caller'),
          );
          await choreographers.delete('ghost');

          final adapter = FakeSourceAdapter([
            record('fake-1', 'A Dance', authorNames: ['Baby Caller']),
          ]);
          final session = await pipeline.commit(
            await pipeline.plan(adapter, const ImportRequest()),
            now: now,
            newId: nextId,
          );
          await dances.create(
            Dance(
              id: 'manual-1',
              title: 'Manual',
              authorIds: const ['ghost'],
              createdAt: now,
              updatedAt: now,
            ),
          );

          await pipeline.undo(session);

          expect(
            await choreographers.getById('ghost'),
            isNotNull,
            reason: 'still credited by a surviving dance, so it stays live',
          );
        },
      );

      test('matches case- and whitespace-insensitively', () async {
        // ignore: unused_result
        await choreographers.upsert(
          Choreographer(id: 'bob', name: 'Bob Isaacs'),
        );
        final adapter = FakeSourceAdapter([
          record('fake-1', 'A Dance', authorNames: ['  bob   ISAACS ']),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        expect(
          (await dances.getById(session.insertedDanceIds.single))!.authorIds,
          ['bob'],
        );
        expect(session.createdChoreographerIds, isEmpty);
      });

      test('matches canonically equivalent decomposed author names', () async {
        // ignore: unused_result
        await choreographers.upsert(Choreographer(id: 'chloe', name: 'Chlöe'));
        final adapter = FakeSourceAdapter([
          record('fake-1', 'A Dance', authorNames: ['Chlo\u0308e']),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        expect(
          (await dances.getById(session.insertedDanceIds.single))!.authorIds,
          ['chloe'],
        );
        expect(session.createdChoreographerIds, isEmpty);
      });

      test('de-dups a new author across a batch to ONE row', () async {
        final adapter = FakeSourceAdapter([
          record('fake-1', 'One', authorNames: ['Shared Author']),
          record('fake-2', 'Two', authorNames: ['Shared Author']),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        expect(session.createdChoreographerIds, hasLength(1));
        final ids = [
          for (final id in session.insertedDanceIds)
            (await dances.getById(id))!.authorIds.single,
        ];
        expect(ids[0], ids[1]);
      });

      test('skips blank/whitespace-only names', () async {
        final adapter = FakeSourceAdapter([
          record('fake-1', 'A Dance', authorNames: ['', '   ']),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        expect(
          (await dances.getById(session.insertedDanceIds.single))!.authorIds,
          isEmpty,
        );
        expect(session.createdChoreographerIds, isEmpty);
      });

      test('collapses a name repeated within one record', () async {
        final adapter = FakeSourceAdapter([
          record(
            'fake-1',
            'A Dance',
            authorNames: ['Will Mentor', 'will mentor'],
          ),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        expect(
          (await dances.getById(session.insertedDanceIds.single))!.authorIds,
          hasLength(1),
        );
      });

      test('reuses the seeded Traditional row by name', () async {
        // ignore: unused_result
        await choreographers.upsert(
          Choreographer(id: 'traditional', name: 'Traditional'),
        );
        final adapter = FakeSourceAdapter([
          record('fake-1', 'A Dance', authorNames: ['Traditional']),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        expect(
          (await dances.getById(session.insertedDanceIds.single))!.authorIds,
          ['traditional'],
        );
        expect(session.createdChoreographerIds, isEmpty);
      });

      test(
        'preserves draft authorIds when no author names are carried',
        () async {
          // The generic archive/JSON adapter ships canonical authorIds in the
          // draft and sets no authorNames; commit must NOT clear them.
          // ignore: unused_result
          await choreographers.upsert(
            Choreographer(id: 'canon', name: 'Canonical Author'),
          );
          final adapter = FakeSourceAdapter([
            record('fake-1', 'A Dance', authorIds: ['canon']),
          ]);
          final session = await pipeline.commit(
            await pipeline.plan(adapter, const ImportRequest()),
            now: now,
            newId: nextId,
          );
          final id = session.insertedDanceIds.single;
          expect((await dances.getById(id))!.authorIds, ['canon']);
          expect(session.createdChoreographerIds, isEmpty);
          expect(session.records.single.authorResolutions, isEmpty);
        },
      );

      test('reimport replaces the resolved authors', () async {
        final first = FakeSourceAdapter([
          record('fake-1', 'Same', authorNames: ['First Author']),
        ]);
        final s1 = await pipeline.commit(
          await pipeline.plan(first, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        final id = s1.insertedDanceIds.single;
        expect(await authorNamesOf(id), ['First Author']);

        final again = FakeSourceAdapter([
          record('fake-1', 'Same', authorNames: ['Second Author']),
        ]);
        await pipeline.commit(
          await pipeline.plan(again, const ImportRequest()),
          now: DateTime.utc(2026, 9, 1),
          newId: nextId,
        );
        expect(await authorNamesOf(id), ['Second Author']);
      });

      test('undo removes a choreographer created by the batch', () async {
        final adapter = FakeSourceAdapter([
          record('fake-1', 'A Dance', authorNames: ['Ephemeral Author']),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        final created = session.createdChoreographerIds.single;
        expect(await choreographers.getById(created), isNotNull);

        await pipeline.undo(session);
        expect(await choreographers.getById(created), isNull);
      });

      test('undo keeps a pre-existing matched choreographer', () async {
        // ignore: unused_result
        await choreographers.upsert(
          Choreographer(id: 'gene', name: 'Gene Hubert'),
        );
        final adapter = FakeSourceAdapter([
          record('fake-1', 'A Dance', authorNames: ['Gene Hubert']),
        ]);
        final session = await pipeline.commit(
          await pipeline.plan(adapter, const ImportRequest()),
          now: now,
          newId: nextId,
        );
        await pipeline.undo(session);
        expect(await choreographers.getById('gene'), isNotNull);
      });

      test(
        'undo keeps a created choreographer still referenced elsewhere',
        () async {
          final adapter = FakeSourceAdapter([
            record('fake-1', 'Imported', authorNames: ['Popular Author']),
          ]);
          final session = await pipeline.commit(
            await pipeline.plan(adapter, const ImportRequest()),
            now: now,
            newId: nextId,
          );
          final created = session.createdChoreographerIds.single;

          // A separate (non-import) dance also credits the created choreographer.
          await dances.create(
            Dance(
              id: 'manual-1',
              title: 'Manual',
              authorIds: [created],
              createdAt: now,
              updatedAt: now,
            ),
          );

          await pipeline.undo(session);
          // The imported dance is gone, but the still-referenced choreographer
          // survives the referenced-guard.
          expect(await dances.getById(session.insertedDanceIds.single), isNull);
          expect(await choreographers.getById(created), isNotNull);
        },
      );
    });
  });

  group('commit reuses plan\'s choreographer snapshot (no double load)', () {
    test('the choreographer collection is loaded once across plan + commit, '
        'and dedupe/author-resolution results are unchanged (one matched, one '
        'created, no duplicate rows)', () async {
      final counter = ChoreographerSelectCounter();
      final countingDb = openCountingTestDatabase(counter);
      addTearDown(countingDb.close);
      final countingDances = DanceRepository(countingDb, contraTaxonomy);
      final countingChoreographers = ChoreographerRepository(countingDb);
      final countingPipeline = ImportPipeline(
        countingDances,
        countingChoreographers,
      );
      // ignore: unused_result
      await countingChoreographers.upsert(
        Choreographer(id: 'gene', name: 'Gene Hubert'),
      );
      counter.reset();

      final adapter = FakeSourceAdapter([
        record('fake-1', 'A Dance', authorNames: ['Gene Hubert']),
        record('fake-2', 'Another Dance', authorNames: ['New Author']),
      ]);
      final batch = await countingPipeline.plan(adapter, const ImportRequest());
      expect(
        counter.count,
        1,
        reason: 'plan() builds one DedupeIndex snapshot',
      );

      final session = await countingPipeline.commit(
        batch,
        now: now,
        newId: nextId,
      );
      expect(
        counter.count,
        1,
        reason:
            'commit should reuse the DedupeIndex snapshot plan() already '
            'built instead of reloading the full choreographer collection '
            'a second time',
      );

      // Dedupe/author-resolution results are unchanged: both records
      // import as new dances, the first matches the pre-existing
      // "Gene Hubert" row (not created), the second creates exactly one
      // new choreographer.
      expect(session.committedCount, 2);
      expect(
        session.records.map((r) => r.action),
        everyElement(CommitAction.create),
      );
      final resolutions = session.records
          .expand((r) => r.authorResolutions)
          .toList();
      expect(resolutions[0].choreographerId, 'gene');
      expect(resolutions[0].created, isFalse);
      expect(resolutions[1].created, isTrue);
      expect(session.createdChoreographerIds, hasLength(1));
      expect(await countingChoreographers.listAll(), hasLength(2));
    });
  });

  group('a record that fails leaves no dance or author writes', () {
    late _FailingDanceRepository failing;
    late ImportPipeline failingPipeline;

    setUp(() {
      failing = _FailingDanceRepository(db, contraTaxonomy);
      failingPipeline = ImportPipeline(failing, choreographers);
    });

    Future<List<String>> liveAuthorNames() async => [
      for (final c in await choreographers.listAll()) c.name,
    ];

    // Live and tombstoned rows: tells an erased author from a tombstoned one.
    Future<List<String>> allAuthorNames() async => [
      for (final c in await choreographers.listAll(includeDeleted: true))
        c.name,
    ];

    Future<String> seedDance(String externalId, String title) async {
      final s = await failingPipeline.commit(
        await failingPipeline.plan(
          FakeSourceAdapter([record(externalId, title)]),
          const ImportRequest(),
        ),
        now: now,
        newId: nextId,
      );
      return s.insertedDanceIds.single;
    }

    test('reimport onto a hard-deleted target creates no author', () async {
      final target = await seedDance('fake-1', 'Original');
      final batch = await failingPipeline.plan(
        FakeSourceAdapter([
          record('fake-1', 'Revised', authorNames: ['Fresh Author']),
        ]),
        const ImportRequest(),
      );
      expect(batch.records.single.verdict.isReimport, isTrue);
      await dances.hardDelete([target]);

      final session = await failingPipeline.commit(
        batch,
        now: now,
        newId: nextId,
      );

      expect(
        session.records.single.error?.message,
        contains('no longer exists'),
      );
      expect(await liveAuthorNames(), isNot(contains('Fresh Author')));
      expect(session.createdChoreographerIds, isEmpty);
      expect(session.revivedChoreographerIds, isEmpty);
    });

    test('a throwing create rolls back the new author', () async {
      failing.failTitles.add('Doomed');
      final session = await failingPipeline.commit(
        await failingPipeline.plan(
          FakeSourceAdapter([
            record('fake-1', 'Doomed', authorNames: ['Fresh Author']),
          ]),
          const ImportRequest(),
        ),
        now: now,
        newId: nextId,
      );

      expect(session.records.single.error, isNotNull);
      // Across tombstones too: a created author is erased, not tombstoned —
      // no peer ever saw it, so a deletion record would advertise nothing.
      expect(await allAuthorNames(), isNot(contains('Fresh Author')));
      expect(session.createdChoreographerIds, isEmpty);
    });

    test('a variation whose reciprocal target update throws leaves neither '
        'the new dance nor its author', () async {
      final target = await seedDance('fake-1', 'The Nice Combination');
      final batch = await failingPipeline.plan(
        FakeSourceAdapter([
          record('fake-2', 'Nice Combination', authorNames: ['Fresh Author']),
        ]),
        const ImportRequest(),
      );
      expect(batch.records.single.verdict.isAmbiguous, isTrue);
      // The new dance's create succeeds; only the target's link-back fails.
      failing.failTitles.add('The Nice Combination');

      final session = await failingPipeline.commit(
        batch,
        now: now,
        newId: nextId,
        resolutions: {0: DedupeResolution.variation(target)},
      );

      expect(session.records.single.error, isNotNull);
      expect([for (final d in await dances.listAll()) d.id], [target]);
      expect((await dances.getById(target))!.links, isEmpty);
      expect(session.insertedDanceIds, isEmpty);
      expect(session.updatedDancePriorStates, isEmpty);
      expect(await allAuthorNames(), isNot(contains('Fresh Author')));
      expect(session.createdChoreographerIds, isEmpty);
    });

    test('a throwing reimport update rolls back the new author', () async {
      final target = await seedDance('fake-1', 'Original');
      failing.failTitles.add('Revised');
      final session = await failingPipeline.commit(
        await failingPipeline.plan(
          FakeSourceAdapter([
            record('fake-1', 'Revised', authorNames: ['Fresh Author']),
          ]),
          const ImportRequest(),
        ),
        now: now,
        newId: nextId,
      );

      expect(session.records.single.error, isNotNull);
      expect(await liveAuthorNames(), isNot(contains('Fresh Author')));
      expect((await dances.getById(target))!.title, 'Original');
    });

    test('a failed record puts a revived author back to tombstoned', () async {
      // ignore: unused_result
      await choreographers.upsert(Choreographer(id: 'old', name: 'Old Hand'));
      await choreographers.delete('old');
      expect(await liveAuthorNames(), isNot(contains('Old Hand')));

      failing.failTitles.add('Doomed');
      final session = await failingPipeline.commit(
        await failingPipeline.plan(
          FakeSourceAdapter([
            record('fake-1', 'Doomed', authorNames: ['Old Hand']),
          ]),
          const ImportRequest(),
        ),
        now: now,
        newId: nextId,
      );

      expect(session.records.single.error, isNotNull);
      expect(await liveAuthorNames(), isNot(contains('Old Hand')));
      // Re-tombstoned, not erased: the row predates the import and stays
      // restorable.
      expect(await allAuthorNames(), contains('Old Hand'));
      expect(session.revivedChoreographerIds, isEmpty);
    });

    test('a later record may credit the author a failed record rolled back '
        '(no phantom id left in the batch name map)', () async {
      failing.failTitles.add('Doomed');
      final session = await failingPipeline.commit(
        await failingPipeline.plan(
          FakeSourceAdapter([
            record('fake-1', 'Doomed', authorNames: ['Shared Author']),
            record('fake-2', 'Survivor', authorNames: ['Shared Author']),
          ]),
          const ImportRequest(),
        ),
        now: now,
        newId: nextId,
      );

      expect(session.records[0].error, isNotNull);
      expect(session.records[1].error, isNull);
      final survivor = (await dances.getById(session.insertedDanceIds.single))!;
      final authors = await choreographers.listAll();
      expect(authors.where((c) => c.name == 'Shared Author'), hasLength(1));
      expect(survivor.authorIds, [authors.single.id]);
      expect(session.createdChoreographerIds, [authors.single.id]);
    });

    test('a failed record does not delete an author an earlier record in '
        'the batch created and credited', () async {
      failing.failTitles.add('Doomed');
      final session = await failingPipeline.commit(
        await failingPipeline.plan(
          FakeSourceAdapter([
            record('fake-1', 'Survivor', authorNames: ['Shared Author']),
            record('fake-2', 'Doomed', authorNames: ['Shared Author']),
          ]),
          const ImportRequest(),
        ),
        now: now,
        newId: nextId,
      );

      expect(session.records[1].error, isNotNull);
      final survivor = (await dances.getById(session.insertedDanceIds.single))!;
      final authors = await choreographers.listAll();
      expect(authors.map((c) => c.name), ['Shared Author']);
      expect(survivor.authorIds, [authors.single.id]);
      expect(session.createdChoreographerIds, [authors.single.id]);
    });
  });
}

/// A [FakeSourceAdapter] that notes, at each `parse`, how many event-loop timer
/// ticks had elapsed — so a test can tell whether planning ever yielded.
class _TickRecordingAdapter extends FakeSourceAdapter {
  _TickRecordingAdapter(super.records, this._ticks, this._seen);

  final int Function() _ticks;
  final List<int> _seen;

  @override
  StructuredDraft parse(RawRecord raw) {
    _seen.add(_ticks());
    return super.parse(raw);
  }
}

/// A [DedupeIndex] that records how many event-loop ticks had happened at each
/// `verdictFor` call — the dedupe-side twin of [_TickRecordingAdapter].
class _TickRecordingIndex extends DedupeIndex {
  _TickRecordingIndex(super.entries, this._ticks, this._seen);

  final int Function() _ticks;
  final List<int> _seen;

  @override
  DedupeVerdict verdictFor({
    required ProvenanceSource source,
    String? externalId,
    Iterable<String> priorExternalIds = const [],
    required String title,
    Iterable<String> authorNames = const [],
    double threshold = DedupeIndex.defaultThreshold,
  }) {
    _seen.add(_ticks());
    return super.verdictFor(
      source: source,
      externalId: externalId,
      priorExternalIds: priorExternalIds,
      title: title,
      authorNames: authorNames,
      threshold: threshold,
    );
  }
}

/// A [DanceRepository] whose `create`/`update` throw for chosen titles, to drive
/// a failure after the pipeline has already resolved a record's authors.
class _FailingDanceRepository extends DanceRepository {
  _FailingDanceRepository(super.db, super.taxonomy);

  final Set<String> failTitles = {};

  @override
  Future<void> create(Dance dance) {
    if (failTitles.contains(dance.title)) {
      throw StateError('injected create failure');
    }
    return super.create(dance);
  }

  @override
  Future<void> update(Dance dance, {bool localUserEdit = false}) {
    if (failTitles.contains(dance.title)) {
      throw StateError('injected update failure');
    }
    return super.update(dance, localUserEdit: localUserEdit);
  }
}
