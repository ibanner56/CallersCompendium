import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// An import-gap custom figure carrying [text] as its stored scrubbed source.
Figure importGap(String text, {int beats = 0}) =>
    customFigure(text, beats: beats, origin: CustomOrigin.importGap);

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ChoreographerRepository choreographers;
  late TagRepository tags;
  late CustomFieldDefRepository customFieldDefs;

  final now = DateTime.utc(2026, 6, 1);

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    tags = TagRepository(db);
    customFieldDefs = CustomFieldDefRepository(db);
  });

  tearDown(() => db.close());

  group('previewImportGapReparse', () {
    test('lists only dances with upgradeable import-gap customs', () async {
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Alpha',
          figures: [importGap('Neighbor swing')],
        ),
      );
      await dances.create(
        sampleDance(
          id: 'b',
          title: 'Bravo',
          figures: [importGap('hey for four')],
        ),
      );
      await dances.create(
        sampleDance(
          id: 'c',
          title: 'Charlie',
          figures: [customFigure('Neighbor swing')],
        ),
      );

      final previews = await dances.previewImportGapReparse();

      expect(previews.map((p) => p.danceId), ['a']);
      expect(previews.single.title, 'Alpha');
      expect(previews.single.upgradeCount, 1);
    });

    test('counts multiple upgradeable figures in one dance', () async {
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Alpha',
          figures: [
            importGap('Neighbor swing'),
            importGap('Partner swing'),
            importGap('hey for four'),
          ],
        ),
      );

      final previews = await dances.previewImportGapReparse();
      expect(previews.single.upgradeCount, 2);
    });

    test('is empty when nothing can be upgraded', () async {
      await dances.create(
        sampleDance(id: 'a', figures: [importGap('hey for four')]),
      );
      expect(await dances.previewImportGapReparse(), isEmpty);
    });

    test('orders previews case-insensitively by title', () async {
      await dances.create(
        sampleDance(
          id: 'z',
          title: 'zebra',
          figures: [importGap('Neighbor swing')],
        ),
      );
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Apple',
          figures: [importGap('Neighbor swing')],
        ),
      );
      await dances.create(
        sampleDance(
          id: 'b',
          title: 'banana',
          figures: [importGap('Neighbor swing')],
        ),
      );

      final previews = await dances.previewImportGapReparse();
      expect(previews.map((p) => p.title), ['Apple', 'banana', 'zebra']);
    });

    test('writes nothing (dry-run leaves updatedAt untouched)', () async {
      await dances.create(
        sampleDance(id: 'a', figures: [importGap('Neighbor swing')]),
      );
      final before = (await dances.getById('a'))!.updatedAt;

      await dances.previewImportGapReparse();

      expect((await dances.getById('a'))!.updatedAt, before);
      expect((await dances.getById('a'))!.figures.single.isCustom, isTrue);
    });
  });

  group('reparseImportGapFiguresForMany', () {
    test('upgrades import-gap customs and reports the change count', () async {
      await dances.create(
        sampleDance(id: 'a', figures: [importGap('Neighbor swing', beats: 16)]),
      );

      final changed = await dances.reparseImportGapFiguresForMany([
        'a',
      ], now: now);

      expect(changed, 1);
      final f = (await dances.getById('a'))!.figures.single;
      expect(f.isCustom, isFalse);
      expect(f.move, 'swing');
      expect(f.params['beats'], 16);
    });

    test('stamps updatedAt only on dances that actually change', () async {
      await dances.create(
        sampleDance(id: 'a', figures: [importGap('Neighbor swing')]),
      );
      await dances.create(
        sampleDance(id: 'b', figures: [importGap('hey for four')]),
      );
      final bBefore = (await dances.getById('b'))!.updatedAt;

      await dances.reparseImportGapFiguresForMany(['a', 'b'], now: now);

      expect((await dances.getById('a'))!.updatedAt, now);
      expect((await dances.getById('b'))!.updatedAt, bBefore);
    });

    test('never touches user-entered customs or structured figures', () async {
      await dances.create(
        sampleDance(
          id: 'a',
          figures: [
            Figure(
              move: 'swing',
              params: const {'who': 'partners', 'beats': 8},
            ),
            customFigure('Neighbor swing'), // user-entered
          ],
        ),
      );

      final changed = await dances.reparseImportGapFiguresForMany([
        'a',
      ], now: now);

      expect(changed, 0);
      final figures = (await dances.getById('a'))!.figures;
      expect(figures[0].move, 'swing');
      expect(figures[1].isCustom, isTrue);
      expect(figures[1].customOrigin, CustomOrigin.userEntered);
    });

    test('preserves ALL dance metadata across the upgrade', () async {
      // ignore: unused_result
      await choreographers.upsert(Choreographer(id: 'c1', name: 'Ada'));
      // ignore: unused_result
      await tags.upsert(Tag(id: 't1', name: 'chestnut'));
      // ignore: unused_result
      await customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'region',
          label: 'Region',
          type: CustomFieldType.text,
        ),
      );

      final original =
          sampleDance(
            id: 'a',
            title: 'Alpha',
            authorIds: ['c1'],
            tagIds: ['t1'],
            customFields: [
              CustomFieldValue(fieldId: 'f1', value: 'New England'),
            ],
            figures: [importGap('Neighbor swing')],
          ).copyWith(
            rating: 4,
            tunes: ['Reel of Rio'],
            callingNotes: 'Teach the swing.',
          );
      await dances.create(original);

      await dances.reparseImportGapFiguresForMany(['a'], now: now);

      final loaded = (await dances.getById('a'))!;
      expect(loaded.title, 'Alpha');
      expect(loaded.authorIds, ['c1']);
      expect(loaded.tagIds, ['t1']);
      expect(loaded.customFields.single.fieldId, 'f1');
      expect(loaded.customFields.single.value, 'New England');
      expect(loaded.rating, 4);
      expect(loaded.tunes, ['Reel of Rio']);
      expect(loaded.callingNotes, 'Teach the swing.');
      // Only the figure changed.
      expect(loaded.figures.single.move, 'swing');
      expect(loaded.figures.single.isCustom, isFalse);
    });

    test('is idempotent — a second run changes nothing', () async {
      await dances.create(
        sampleDance(id: 'a', figures: [importGap('Neighbor swing')]),
      );

      expect(await dances.reparseImportGapFiguresForMany(['a'], now: now), 1);
      final afterFirst = (await dances.getById('a'))!;

      final secondNow = now.add(const Duration(days: 1));
      expect(
        await dances.reparseImportGapFiguresForMany(['a'], now: secondNow),
        0,
      );
      final afterSecond = (await dances.getById('a'))!;
      // No further change, and updatedAt was not re-stamped.
      expect(afterSecond.updatedAt, afterFirst.updatedAt);
      expect(afterSecond.figures.single.move, 'swing');
    });

    test('empty ids is a no-op returning 0', () async {
      expect(await dances.reparseImportGapFiguresForMany([], now: now), 0);
    });

    test('skips unknown ids', () async {
      expect(
        await dances.reparseImportGapFiguresForMany(['nope'], now: now),
        0,
      );
    });

    test('rejects a non-UTC now', () async {
      expect(
        () => dances.reparseImportGapFiguresForMany([
          'a',
        ], now: DateTime(2026, 6, 1)),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
