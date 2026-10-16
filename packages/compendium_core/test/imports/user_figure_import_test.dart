import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// Adding a shared archive's figures (#1023, maintainer decision 3; plan
/// C12): what each would do, and pointing the imported dances at a copy.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final created = DateTime.utc(2026, 10, 16, 9);
  final now = DateTime.utc(2026, 10, 16, 10);

  UserGlossaryEntry entry(
    String id, {
    String kind = 'customFigure',
    String name = 'zoom',
    String template = '{move}',
    String? notes,
    DateTime? at,
  }) => UserGlossaryEntry(
    id: id,
    kindName: kind,
    name: name,
    definition: 'A figure.',
    description: 'Of your own.',
    notes: notes,
    payload: {'template': template, 'defaultBeats': 8, 'params': <Object?>[]},
    createdAt: at ?? created,
  );

  group('planUserFigureImport', () {
    test('sorts each figure by what adding it would do', () {
      final plan = planUserFigureImport(
        [
          entry('new'),
          entry('same', notes: null),
          entry('changed', template: '{move} twice'),
          entry('a-compound'),
          entry('deleted'),
        ],
        entries: [
          entry('same', notes: 'mine', at: now),
          entry('changed'),
          entry('a-compound', kind: 'compound'),
        ],
        deletedIds: {'deleted'},
      );
      expect(plan.map((i) => (i.incoming.id, i.kind)), [
        ('new', UserFigureImportKind.add),
        ('same', UserFigureImportKind.same),
        ('changed', UserFigureImportKind.differs),
        ('a-compound', UserFigureImportKind.copy),
        ('deleted', UserFigureImportKind.copy),
      ]);
      expect(plan[1].mine?.notes, 'mine');
      expect(plan[2].mine?.id, 'changed');
      expect(plan[3].mine, isNull);
    });

    test('content is name, definition, description, keywords and payload; '
        'not notes or creation time', () {
      final mine = entry('z', notes: 'mine', at: now);
      expect(sameUserFigureContent(mine, entry('z')), isTrue);
      expect(sameUserFigureContent(mine, entry('z', name: 'whizz')), isFalse);
      expect(
        sameUserFigureContent(mine, entry('z', template: '{move}!')),
        isFalse,
      );
      expect(
        sameUserFigureContent(
          mine,
          UserGlossaryEntry(
            id: 'z',
            kindName: 'customFigure',
            name: 'zoom',
            definition: 'A figure.',
            description: 'Of your own.',
            keywords: const ['fast'],
            payload: mine.payload,
            createdAt: created,
          ),
        ),
        isFalse,
      );
    });
  });

  List<Figure> figuresOf(Dance d) =>
      (d.figuresSource as DecodedFigures).figures;

  group('remapUserFigureUses', () {
    late CompendiumRepositories repos;
    setUp(
      () => repos = CompendiumRepositories(openTestDatabase(), contraTaxonomy),
    );
    tearDown(() => repos.db.close());

    Figure use(String id) =>
        userFigureUseFigure(id: id, args: const {}, text: 'zoom');

    Dance dance(String id, List<Figure> figures) => Dance(
      id: id,
      title: 'Dance $id',
      figures: figures,
      createdAt: created,
      updatedAt: created,
    );

    test('points the named dances\' uses at the new id, inside containers '
        'too, and leaves them attached', () async {
      await repos.dances.create(
        dance('d1', [
          use('old'),
          Figure.meanwhile(figures: [use('old'), use('other')], beats: 8),
        ]),
      );
      await repos.dances.create(dance('d2', [use('old')]));

      final changed = await repos.dances.remapUserFigureUses(
        ['d1'],
        {'old': 'new'},
        now: now,
      );

      expect(changed, 1);
      final d1 = (await repos.dances.getById('d1'))!;
      final ids = [
        for (final f in [figuresOf(d1).first, ...figuresOf(d1)[1].subFigures])
          userFigureUseOf(f),
      ];
      expect(ids.map((u) => u?.id), ['new', 'new', 'other']);
      expect(ids.every((u) => u!.attached), isTrue);
      expect(d1.updatedAt, now);
      final d2 = (await repos.dances.getById('d2'))!;
      expect(
        userFigureUseOf(figuresOf(d2).single)?.id,
        'old',
        reason: 'a dance not named is not written',
      );
    });

    test('a dance using none of them is not written', () async {
      await repos.dances.create(dance('d1', [use('other')]));
      expect(
        await repos.dances.remapUserFigureUses(
          ['d1'],
          {'old': 'new'},
          now: now,
        ),
        0,
      );
      expect((await repos.dances.getById('d1'))!.updatedAt, created);
    });

    test('a detached use keeps its id', () async {
      await repos.dances.create(dance('d1', [detachUserFigureUse(use('old'))]));
      expect(
        await repos.dances.remapUserFigureUses(
          ['d1'],
          {'old': 'new'},
          now: now,
        ),
        0,
      );
    });
  });
}
