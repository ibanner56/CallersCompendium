import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:test/test.dart';

import '../figures_support.dart';
import 'test_database.dart';

/// Switching a figure of your own's uses to the shipped figure of its name,
/// then retiring it (#1023, maintainer decision 5), in storage.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final created = DateTime.utc(2026, 10, 16, 9);
  final saved = DateTime.utc(2026, 10, 16, 10);
  final edited = DateTime.utc(2026, 10, 16, 11);
  final switchedAt = DateTime.utc(2026, 10, 16, 12);

  late CompendiumRepositories repos;
  setUp(
    () => repos = CompendiumRepositories(openTestDatabase(), contraTaxonomy),
  );
  tearDown(() => repos.db.close());

  // Saved by restore: the name is the shipped "swing", as it is once a later
  // version ships a figure of the name the user had already taken.
  UserGlossaryEntry mine() => UserGlossaryEntry(
    id: 'mine',
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: 'swing',
    definition: 'Mine.',
    description: 'Mine.',
    payload: {
      'form': 'contra',
      'template': '{who} {move}',
      'defaultBeats': 8,
      'params': [
        {'key': 'who', 'kind': 'dancerSet', 'default': 'neighbors'},
      ],
    },
    createdAt: created,
  );
  final mapping = UserFigureSwitch(target: 'swing', params: {'who': 'who'});

  Figure use([String who = 'partners']) =>
      userFigureUseFigure(id: 'mine', args: {'who': who}, text: '$who swing');

  Dance dance(String id, List<Figure> figures) => Dance(
    id: id,
    title: 'Dance $id',
    figures: figures,
    createdAt: saved,
    updatedAt: saved,
  );

  Future<List<String>> indexedMoves(String danceId) async => [
    for (final row in await (repos.db.select(
      repos.db.danceFigures,
    )..where((t) => t.danceId.equals(danceId))).get())
      row.move,
  ];

  test('each use becomes the shipped figure, the dance is reindexed, and '
      'the figure is retired', () async {
    await repos.userGlossary.upsertFromRestore(mine());
    await repos.dances.create(dance('d1', [use(), Figure(move: 'balance')]));
    await repos.dances.create(dance('d2', [Figure(move: 'allemande')]));
    expect(await indexedMoves('d1'), [customMoveId, 'balance']);

    final switched = await repos.switchUserFigureToBuiltIn(
      'mine',
      mapping,
      at: switchedAt,
    );

    expect(switched, 1);
    final d1 = (await repos.dances.getById('d1'))!;
    expect(d1.updatedAt, switchedAt);
    expect(figuresOf(d1).first.move, 'swing');
    expect(figuresOf(d1).first.params, {'who': 'partners', 'beats': 8});
    expect(await indexedMoves('d1'), ['swing', 'balance']);
    expect((await repos.dances.getById('d2'))!.updatedAt, saved);
    expect(await repos.userGlossary.getById('mine'), isNull);
    expect(await repos.dances.countDancesUsingUserFigure('mine'), 0);
  });

  test('a dance in the Trash is not written', () async {
    await repos.userGlossary.upsertFromRestore(mine());
    await repos.dances.create(dance('d1', [use()]));
    await repos.dances.softDelete('d1', at: edited);
    expect(
      await repos.switchUserFigureToBuiltIn('mine', mapping, at: switchedAt),
      0,
    );
    final d1 = (await repos.dances.getById('d1', includeDeleted: true))!;
    expect(d1.updatedAt, edited);
    expect(userFigureUseOf(figuresOf(d1).single), isNotNull);
  });

  test('an incomplete mapping, or no live figure, writes nothing', () async {
    await repos.userGlossary.upsertFromRestore(mine());
    await repos.dances.create(dance('d1', [use()]));
    await expectLater(
      repos.switchUserFigureToBuiltIn(
        'mine',
        UserFigureSwitch(target: 'swing'),
        at: switchedAt,
      ),
      throwsStateError,
    );
    await expectLater(
      repos.switchUserFigureToBuiltIn('other', mapping, at: switchedAt),
      throwsStateError,
    );
    expect((await repos.dances.getById('d1'))!.updatedAt, saved);
    expect(await repos.userGlossary.getById('mine'), isNotNull);
  });

  test('switching and retiring are one transaction', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final failing = CompendiumRepositories(
      db,
      contraTaxonomy,
      dances: _FailAfterSwitch(db),
    );
    await failing.userGlossary.upsertFromRestore(mine());
    await failing.dances.create(dance('d1', [use()]));
    await expectLater(
      failing.switchUserFigureToBuiltIn('mine', mapping, at: switchedAt),
      throwsStateError,
    );
    final d1 = (await failing.dances.getById('d1'))!;
    expect(d1.updatedAt, saved, reason: 'the switch rolled back');
    expect(userFigureUseOf(figuresOf(d1).single), isNotNull);
    expect(await failing.userGlossary.getById('mine'), isNotNull);
  });
}

class _FailAfterSwitch extends DanceRepository {
  _FailAfterSwitch(CompendiumDatabase db) : super(db, contraTaxonomy);

  @override
  Future<int> switchUserFigureUses(
    String userFigureId,
    UserFigureSwitch mapping, {
    required DateTime now,
  }) async {
    await super.switchUserFigureUses(userFigureId, mapping, now: now);
    throw StateError('injected');
  }
}
