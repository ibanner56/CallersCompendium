import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:test/test.dart';

import '../figures_support.dart';
import 'test_database.dart';

/// The dance index and figures of your own (#1023): their uses are indexed as
/// they render, from the live definition, and follow it when it changes.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final created = DateTime.utc(2026, 10, 15, 9);
  final saved = DateTime.utc(2026, 10, 15, 10);
  final edited = DateTime.utc(2026, 10, 15, 11);
  final removed = DateTime.utc(2026, 10, 15, 12);

  late CompendiumRepositories repos;
  setUp(
    () => repos = CompendiumRepositories(openTestDatabase(), contraTaxonomy),
  );
  tearDown(() => repos.db.close());

  UserGlossaryEntry figure({
    String id = 'zoom-id',
    String template = '{who} zoom {hand}',
  }) => UserGlossaryEntry(
    id: id,
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: 'zoom',
    definition: 'A zoom.',
    description: 'Fast.',
    payload: {
      'form': 'contra',
      'template': template,
      'defaultBeats': 8,
      'params': [
        {'key': 'who', 'kind': 'dancerSet', 'default': 'neighbors'},
        {'key': 'hand', 'kind': 'handedness'},
      ],
    },
    createdAt: created,
  );

  Figure use({String id = 'zoom-id', String text = 'neighbors zoom right'}) =>
      userFigureUseFigure(id: id, args: const {'hand': 'right'}, text: text);

  Dance dance(String id, List<Figure> figures) => Dance(
    id: id,
    title: 'Dance $id',
    figures: figures,
    createdAt: saved,
    updatedAt: saved,
  );

  Future<List<Map<String, Object?>>> indexedParams(String danceId) async => [
    for (final row in await (repos.db.select(
      repos.db.danceFigures,
    )..where((t) => t.danceId.equals(danceId))).get())
      if (row.move == customMove)
        (jsonDecode(row.paramsJson) as Map).cast<String, Object?>(),
  ];

  test('a use is indexed from the live definition, and follows an edit '
      'without its dance being rewritten', () async {
    await repos.userGlossary.upsert(figure(), at: created);
    await repos.dances.create(dance('d1', [use(text: 'a stale stored line')]));

    expect(await repos.dances.searchText('stale'), isEmpty);
    expect(await repos.dances.searchText('zoom'), ['d1']);

    await repos.userGlossary.upsert(
      figure(template: '{who} whirl {otherHand}'),
      at: edited,
    );
    expect(await repos.dances.searchText('whirl'), ['d1']);
    expect(await repos.dances.searchText('zoom'), isEmpty);
    final stored = (await repos.dances.getById('d1'))!;
    expect(stored.updatedAt, saved, reason: 'the dance was not rewritten');
    expect(
      figuresOf(stored).single.params['text'],
      'a stale stored line',
      reason: 'the dance itself is not rewritten',
    );
  });

  test(
    'a use inside a container is found when its definition changes',
    () async {
      await repos.userGlossary.upsert(figure(), at: created);
      await repos.dances.create(
        dance('d1', [
          Figure.meanwhile(
            figures: [
              use(),
              Figure(move: 'swing'),
            ],
            beats: 8,
          ),
        ]),
      );
      await repos.userGlossary.upsert(
        figure(template: '{who} whirl'),
        at: edited,
      );
      expect(await repos.dances.searchText('whirl'), ['d1']);
    },
  );

  test('the index keeps a use\'s reference only while it is attached and '
      'its figure is live', () async {
    await repos.userGlossary.upsert(figure(), at: created);
    final detached = use().copyWith(
      params: {...use().params, 'text': 'typed on an older device'},
    );
    final outOfRange = userFigureUseFigure(
      id: 'zoom-id',
      args: const {'hand': 'sideways'},
      text: 'neighbors zoom sideways',
    );
    await repos.dances.create(dance('d1', [use(), detached, outOfRange]));
    final params = await indexedParams('d1');
    expect(params[0][userFigureRefKey], 'zoom-id');
    expect(params[1].containsKey(userFigureRefKey), isFalse);
    expect(
      params[2].containsKey(userFigureRefKey),
      isFalse,
      reason: 'an argument the figure no longer takes shows the stored line',
    );

    await repos.userGlossary.delete('zoom-id', at: removed);
    expect(
      (await indexedParams('d1')).any((p) => p.containsKey(userFigureRefKey)),
      isFalse,
      reason: 'a deleted figure\'s uses show their stored line',
    );
    expect(await repos.dances.searchText('neighbors'), ['d1']);
  });

  test('the "has figure" filter finds a live use at the top level, in a '
      'meanwhile and in a modifier, and not a detached or deleted one '
      '(#1023)', () async {
    Future<List<String>> hasFigure(String id) => repos.dances.search(
      FigureFilter.leaf(customMove, params: {userFigureRefKey: id}),
    );
    await repos.userGlossary.upsert(figure(), at: created);
    await repos.userGlossary.upsert(figure(id: 'other-id'), at: created);
    final detached = use().copyWith(
      params: {...use().params, 'text': 'typed on an older device'},
    );
    await repos.dances.create(dance('top', [use()]));
    await repos.dances.create(
      dance('side', [
        Figure.meanwhile(
          figures: [
            Figure(move: 'swing'),
            use(),
          ],
          beats: 8,
        ),
      ]),
    );
    await repos.dances.create(
      dance('mod', [
        Figure.modifier(
          figures: [
            Figure(move: 'swing'),
            use(),
          ],
          beats: 8,
        ),
      ]),
    );
    await repos.dances.create(dance('detached', [detached]));
    await repos.dances.create(dance('other', [use(id: 'other-id')]));

    expect(await hasFigure('zoom-id'), unorderedEquals(['top', 'side', 'mod']));
    expect(await hasFigure('other-id'), ['other']);

    await repos.userGlossary.delete('other-id', at: removed);
    expect(
      await hasFigure('other-id'),
      isEmpty,
      reason: 'a deleted figure\'s uses are plain text',
    );
  });

  test('a use of a figure this device does not have yet is indexed as its '
      'line, and reindexed when the figure arrives', () async {
    await repos.dances.create(dance('d1', [use(text: 'neighbors zoom')]));
    expect(await repos.dances.searchText('zoom'), ['d1']);
    await repos.userGlossary.upsert(
      figure(template: '{who} whirl'),
      at: created,
    );
    expect(await repos.dances.searchText('whirl'), ['d1']);
    expect((await indexedParams('d1')).single[userFigureRefKey], 'zoom-id');
  });

  test('deleting a figure freezes each live use to the line it renders to '
      'now', () async {
    await repos.userGlossary.upsert(figure(), at: created);
    await repos.dances.create(
      dance('d1', [use(text: 'a stale stored line'), Figure(move: 'swing')]),
    );
    await repos.dances.create(dance('d2', [Figure(move: 'swing')]));
    expect(await repos.dances.countDancesUsingUserFigure('zoom-id'), 1);

    final frozen = await repos.deleteUserFigure('zoom-id', at: removed);
    expect(frozen, 1);
    final d1 = (await repos.dances.getById('d1'))!;
    expect(d1.updatedAt, removed);
    expect(figuresOf(d1).first.params, {'text': 'neighbors zoom right'});
    expect((await repos.dances.getById('d2'))!.updatedAt, saved);
    expect(await repos.userGlossary.getById('zoom-id'), isNull);
    expect(await repos.dances.countDancesUsingUserFigure('zoom-id'), 0);
  });

  test('a use inside a container is frozen too', () async {
    await repos.userGlossary.upsert(figure(), at: created);
    await repos.dances.create(
      dance('d1', [
        Figure.meanwhile(
          figures: [
            use(text: 'stale'),
            Figure(move: 'swing'),
          ],
          beats: 8,
        ),
      ]),
    );
    expect(await repos.deleteUserFigure('zoom-id', at: removed), 1);
    final side = figuresOf(
      (await repos.dances.getById('d1'))!,
    ).single.subFigures.first;
    expect(side.params, {'text': 'neighbors zoom right'});
  });

  test('a dance in the Trash is not counted or frozen, and restored shows '
      'the line its use last stored', () async {
    await repos.userGlossary.upsert(figure(), at: created);
    await repos.dances.create(dance('d1', [use(text: 'neighbors zoom right')]));
    await repos.userGlossary.upsert(
      figure(template: '{who} whirl {hand}'),
      at: edited,
    );
    await repos.dances.softDelete('d1', at: edited);
    expect(await repos.dances.countDancesUsingUserFigure('zoom-id'), 0);
    expect(await repos.deleteUserFigure('zoom-id', at: removed), 0);
    await repos.dances.restore('d1', at: removed.add(const Duration(hours: 1)));
    expect(await repos.dances.searchText('zoom'), ['d1']);
    expect(await repos.dances.searchText('whirl'), isEmpty);
  });

  test('a soft-deleted dance is not counted or frozen', () async {
    await repos.userGlossary.upsert(figure(), at: created);
    await repos.dances.create(dance('d1', [use()]));
    await repos.dances.softDelete('d1', at: edited);
    expect(await repos.dances.countDancesUsingUserFigure('zoom-id'), 0);
    expect(await repos.deleteUserFigure('zoom-id', at: removed), 0);
  });

  test('freezing and deleting are one transaction', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final repos = CompendiumRepositories(
      db,
      contraTaxonomy,
      dances: _FailAfterFreeze(db),
    );
    await repos.userGlossary.upsert(figure(), at: created);
    await repos.dances.create(dance('d1', [use(text: 'stale')]));
    await expectLater(
      repos.deleteUserFigure('zoom-id', at: removed),
      throwsStateError,
    );
    final d1 = (await repos.dances.getById('d1'))!;
    expect(d1.updatedAt, saved, reason: 'the freeze rolled back');
    expect(userFigureUseOf(figuresOf(d1).single), isNotNull);
    expect(await repos.userGlossary.getById('zoom-id'), isNotNull);
  });

  // A sync apply batch rebuilds every dance's rows: these pin that the
  // rebuild reads the live figures, whichever arrives first.
  group('by sync', () {
    late CompendiumRepositories peer;
    setUp(
      () => peer = CompendiumRepositories(openTestDatabase(), contraTaxonomy),
    );
    tearDown(() => peer.db.close());

    Future<SyncMergeCandidate> held(
      CompendiumRepositories from,
      SyncRecordAddress address,
    ) async => (await CompendiumSyncStorage(from).snapshot()).local[address]!;

    Future<void> receive(SyncMergeCandidate candidate) async {
      final result = await const SyncApplyEngine().apply(
        candidates: [SyncMergeCandidate(blob: candidate.blob)],
        storage: CompendiumSyncStorage(repos),
      );
      expect(result.reports, isEmpty);
    }

    const entryAddress = (
      kind: SyncRecordKind.glossaryEntry,
      recordId: 'zoom-id',
    );
    const danceAddress = (kind: SyncRecordKind.dance, recordId: 'd1');

    test('a definition arriving after its dance reindexes the dance, and '
        'its tombstone does too', () async {
      await peer.userGlossary.upsert(
        figure(template: '{who} whirl'),
        at: created,
      );
      await peer.dances.create(dance('d1', [use(text: 'neighbors zoom')]));

      await receive(await held(peer, danceAddress));
      expect(await repos.dances.searchText('zoom'), ['d1']);
      await receive(await held(peer, entryAddress));
      expect(await repos.dances.searchText('whirl'), ['d1']);

      await peer.userGlossary.delete('zoom-id', at: removed);
      await receive(await held(peer, entryAddress));
      expect(await repos.dances.searchText('whirl'), isEmpty);
      expect(await repos.dances.searchText('zoom'), ['d1']);
      final stored = (await repos.dances.getById('d1'))!;
      expect(
        userFigureUseOf(figuresOf(stored).single),
        isNotNull,
        reason: 'a sync delete leaves the dance alone',
      );
    });

    test(
      'a definition arriving first indexes a dance arriving after it',
      () async {
        await peer.userGlossary.upsert(
          figure(template: '{who} whirl'),
          at: created,
        );
        await peer.dances.create(dance('d1', [use(text: 'neighbors zoom')]));
        await receive(await held(peer, entryAddress));
        await receive(await held(peer, danceAddress));
        expect(await repos.dances.searchText('whirl'), ['d1']);
      },
    );
  });
}

/// A dance repository whose freeze succeeds and then fails, to show the
/// delete that follows it in one transaction is rolled back with it.
class _FailAfterFreeze extends DanceRepository {
  _FailAfterFreeze(CompendiumDatabase db) : super(db, contraTaxonomy);

  @override
  Future<int> freezeUserFigureUses(
    String userFigureId, {
    required DateTime now,
  }) async {
    await super.freezeUserFigureUses(userFigureId, now: now);
    throw StateError('injected');
  }
}
