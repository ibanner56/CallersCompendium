import 'dart:convert';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';
import 'support/fmp_fixture_builder.dart';

/// #1973: Caller's Companion's `Level` is a multi-select, one value per line.
/// Several steps make a difficulty level of their own ("Easy/Intermediate"),
/// placed among the receiver's levels by CC's scale.
void main() {
  group('mapping', () {
    final adapter = CallersCompanionUsrAdapter();
    StructuredDraft parse(String level) => adapter.parse(
      RawRecord(
        source: ProvenanceSource.callersCompanion,
        externalId: '7',
        sourceVersion: CallersCompanionUsrAdapter.sourceVersion,
        payload: jsonEncode({
          'rowId': '7',
          'columns': {'Name': 'D', 'Level': level},
        }),
        contentType: 'application/json',
      ),
    );

    test('one value maps to a shipped level, Easy to Beginner', () {
      for (final (level, id) in [
        ('Easy', DifficultyLevel.beginnerId),
        ('Beginner', DifficultyLevel.beginnerId),
        ('Intermediate', DifficultyLevel.intermediateId),
        ('Advanced', DifficultyLevel.advancedId),
      ]) {
        final draft = parse(level);
        expect(draft.dance.difficultyLevelId, id, reason: level);
        expect(draft.issues, isEmpty, reason: level);
      }
    });

    test('several steps name a level of their own, lowest first', () {
      for (final (level, name) in [
        ('Easy\nIntermediate', 'Easy/Intermediate'),
        ('Intermediate\nEasy', 'Easy/Intermediate'),
        ('Intermediate\r\nAdvanced', 'Intermediate/Advanced'),
        ('Beginner\nEasy', 'Beginner/Easy'),
        ('Easy\rBeginner', 'Beginner/Easy'),
      ]) {
        final draft = parse(level);
        expect(draft.dance.difficultyLevelId, isNull, reason: level);
        expect(draft.difficultyLevelLabel, name, reason: level);
        expect(draft.issues.map((i) => i.code), [
          ccNewLevelIssueCode,
        ], reason: level);
      }
    });

    test('an unknown value is still unrecognised, without a line break', () {
      final issue = parse('Easy\nWobbly').issues.single;
      expect(issue.code, 'cc_unmapped_level');
      expect(
        issue.message,
        'Level "Easy/Wobbly" is unrecognized; left '
        'unspecified.',
      );
    });
  });

  group('at commit', () {
    late CompendiumDatabase db;
    late DanceRepository dances;
    late DifficultyLevelRepository levels;
    late CallersCompanionUsrImporter importer;
    var n = 0;
    String nextId() => 'id-${++n}';
    final now = DateTime.utc(2026, 7, 15);

    CallersCompanionUsrImporter importerWith(ProgramRepository programs) =>
        CallersCompanionUsrImporter(
          ImportPipeline(
            dances,
            ChoreographerRepository(db),
            difficultyLevels: levels,
          ),
          programs,
          VenueRepository(db),
          CustomFieldDefRepository(db),
          publishedSources: PublishedSourceRepository(db),
          difficultyLevels: levels,
        );

    setUp(() {
      db = openTestDatabase();
      dances = DanceRepository(db, contraTaxonomy);
      levels = DifficultyLevelRepository(db);
      importer = importerWith(ProgramRepository(db));
    });
    tearDown(() => db.close());

    Uint8List usr(List<String> levelsByDance, {bool withSet = false}) =>
        buildFmp12Fixture([
          FmpFixtureTable(
            index: 1,
            name: 'Dance',
            columnNames: ['zk_Dance_ID', 'Name', 'Level'],
            rows: [
              for (final (i, level) in levelsByDance.indexed)
                MapEntry(10 + i, {1: '${i + 1}', 2: 'Dance $i', 3: level}),
            ],
          ),
          if (withSet)
            FmpFixtureTable(
              index: 2,
              name: 'Set',
              columnNames: ['zk_Set_ID', 'Location'],
              rows: [
                MapEntry(20, {1: '1', 2: 'Hall'}),
              ],
            ),
        ]);

    Future<CcUsrImportResult> import(Uint8List bytes) =>
        importer.import(bytes, now: now, venueEntityMode: false, newId: nextId);

    Future<List<String>> labels() async => [
      for (final level in await levels.listAll()) level.label,
    ];

    /// Every live level's row as stored: what sync publishes.
    Future<Map<String, (int, DateTime?)>> rows() async => {
      for (final row in await db.select(db.difficultyLevels).get())
        if (row.deletedAt == null) row.id: (row.position, row.updatedAt),
    };

    Future<String?> levelOf(String title) async {
      final dance = (await dances.listAll()).firstWhere(
        (d) => d.title == title,
      );
      final id = dance.difficultyLevelId;
      return id == null ? null : (await levels.getById(id))?.label;
    }

    test('creates each combined level once, in CC\'s order; undo removes '
        'them', () async {
      final result = await import(
        usr([
          'Intermediate\nAdvanced',
          'Easy\nIntermediate',
          'Beginner\nEasy',
          'Intermediate\nEasy',
          'Easy',
        ]),
      );
      expect(await labels(), [
        'Beginner',
        'Beginner/Easy',
        'Easy/Intermediate',
        'Intermediate',
        'Intermediate/Advanced',
        'Advanced',
      ]);
      expect(result.insertedDifficultyLevelIds, hasLength(3));
      expect(await levelOf('Dance 0'), 'Intermediate/Advanced');
      expect(await levelOf('Dance 1'), 'Easy/Intermediate');
      expect(await levelOf('Dance 3'), 'Easy/Intermediate');
      expect(await levelOf('Dance 4'), 'Beginner');
      for (final dance in await dances.listAll()) {
        expect(dance.difficultyLevelId, isNotNull, reason: dance.title);
      }

      await importer.undo(result);
      expect(await labels(), ['Beginner', 'Intermediate', 'Advanced']);
    });

    test('a level the user already has is reused, ignoring case and '
        'spacing', () async {
      final mine = await levels.createCustom(
        label: 'easy / intermediate',
        position: 3,
      );
      final result = await import(usr(['Easy\nIntermediate']));
      expect(result.insertedDifficultyLevelIds, isEmpty);
      expect(result.restoredDifficultyLevelIds, isEmpty);
      expect((await dances.listAll()).single.difficultyLevelId, mine.id);
      await importer.undo(result);
      expect(await labels(), contains('easy / intermediate'));
    });

    test('a deleted level of that name is restored; undo deletes it '
        'again', () async {
      // Spaced differently: only the importer sees deleted levels, so this
      // is its own match, not the pipeline's.
      final old = await levels.createCustom(
        label: 'Easy / Intermediate',
        position: 3,
      );
      await levels.delete(old.id, at: now);
      final result = await import(usr(['Easy\nIntermediate']));
      expect(result.restoredDifficultyLevelIds, [old.id]);
      expect(result.insertedDifficultyLevelIds, isEmpty);
      expect((await dances.listAll()).single.difficultyLevelId, old.id);
      // Placed like a created level, not left where it was deleted.
      expect(await labels(), [
        'Beginner',
        'Easy / Intermediate',
        'Intermediate',
        'Advanced',
      ]);
      await importer.undo(result);
      expect(await labels(), isNot(contains('Easy / Intermediate')));
    });

    test('the plan already shows a level the user has', () async {
      // What the review shows: the pipeline reuses it before commit.
      final mine = await levels.createCustom(
        label: 'easy / intermediate',
        position: 3,
      );
      final draft = (await importer.plan(
        usr(['Easy\nIntermediate']),
      )).records.single.draft;
      expect(draft.dance.difficultyLevelId, mine.id);
      expect(
        draft.issues.map((i) => i.code),
        isNot(contains(ccNewLevelIssueCode)),
      );
    });

    test(
      'undo keeps a created level one of your own dances now uses',
      () async {
        final result = await import(usr(['Easy\nIntermediate']));
        final id = result.insertedDifficultyLevelIds.single;
        await dances.create(
          Dance(
            id: 'mine',
            title: 'Mine',
            form: DanceForm.contra,
            difficultyLevelId: id,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await importer.undo(result);
        expect(await labels(), contains('Easy/Intermediate'));
      },
    );

    test('a level among your own goes after the last one below it', () async {
      // The user has their own "Easy" between Beginner and Intermediate.
      final easy = await levels.createCustom(label: 'Easy', position: 1);
      await levels.reorder([
        DifficultyLevel.beginnerId,
        easy.id,
        DifficultyLevel.intermediateId,
        DifficultyLevel.advancedId,
      ]);
      await import(usr(['Easy\nIntermediate', 'Beginner\nEasy']));
      expect(await labels(), [
        'Beginner',
        'Beginner/Easy',
        'Easy',
        'Easy/Intermediate',
        'Intermediate',
        'Advanced',
      ]);
    });

    test('a level the scale says nothing about keeps its place', () async {
      // The user's own "Party" sits between Beginner and Intermediate; the
      // new level goes straight after Beginner, the last level below it.
      final party = await levels.createCustom(label: 'Party', position: 1);
      await levels.reorder([
        DifficultyLevel.beginnerId,
        party.id,
        DifficultyLevel.intermediateId,
        DifficultyLevel.advancedId,
      ]);
      await import(usr(['Easy\nIntermediate']));
      expect(await labels(), [
        'Beginner',
        'Easy/Intermediate',
        'Party',
        'Intermediate',
        'Advanced',
      ]);
    });

    test('a list ordered hardest first is read hardest first', () async {
      await levels.reorder([
        DifficultyLevel.advancedId,
        DifficultyLevel.intermediateId,
        DifficultyLevel.beginnerId,
      ]);
      await import(usr(['Easy\nIntermediate', 'Intermediate\nAdvanced']));
      expect(await labels(), [
        'Advanced',
        'Intermediate/Advanced',
        'Intermediate',
        'Easy/Intermediate',
        'Beginner',
      ]);
    });

    test('an import that keeps no level rewrites no level', () async {
      final before = await rows();
      final batch = await importer.plan(usr(['Easy\nIntermediate']));
      await importer.commit(
        ImportBatchResult(
          records: [
            ImportRecordPlan(
              draft: batch.records.single.draft,
              verdict: DedupeVerdict.ambiguous(const []),
            ),
          ],
        ),
        CcUsrArchive(dances: const [], sets: const [], warnings: const []),
        now: now,
        venueEntityMode: false,
        newId: nextId,
      );
      expect(await rows(), before);
    });

    test('a failed import rewrites no level', () async {
      final before = await rows();
      final failing = importerWith(_FailingProgramRepository(db));
      await expectLater(
        failing.import(
          usr(['Easy\nIntermediate'], withSet: true),
          now: now,
          venueEntityMode: false,
          newId: nextId,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await rows(), before);
    });

    test('placing a level rewrites only the levels that move', () async {
      final before = await rows();
      final result = await import(usr(['Intermediate\nAdvanced']));
      final after = await rows();
      // Beginner and Intermediate keep their places and their rows.
      expect(
        after[DifficultyLevel.beginnerId],
        before[DifficultyLevel.beginnerId],
      );
      expect(
        after[DifficultyLevel.intermediateId],
        before[DifficultyLevel.intermediateId],
      );
      expect(after[DifficultyLevel.advancedId]!.$1, 3);
      await importer.undo(result);
      expect(await labels(), ['Beginner', 'Intermediate', 'Advanced']);
    });

    test('a batch after an Edit reuses the level the Edit made', () async {
      // Planned together, so neither row's plan saw the other's level.
      final batch = await importer.plan(
        usr(['Easy\nIntermediate', 'Easy\nIntermediate']),
      );
      await importer.commitDances(
        ImportBatchResult(records: [batch.records[0]]),
        now: now,
        newId: nextId,
      );
      final result = await importer.commit(
        ImportBatchResult(records: [batch.records[1]]),
        CcUsrArchive(dances: const [], sets: const [], warnings: const []),
        now: now,
        venueEntityMode: false,
        newId: nextId,
      );
      expect(result.insertedDifficultyLevelIds, isEmpty);
      expect(
        (await labels()).where((l) => l == 'Easy/Intermediate'),
        hasLength(1),
      );
      expect({
        for (final d in await dances.listAll()) d.difficultyLevelId,
      }, hasLength(1));
      await importer.undo(result);
      expect(await labels(), contains('Easy/Intermediate'));
    });

    test('a failed commit removes the level it created', () async {
      final failing = importerWith(_FailingProgramRepository(db));
      await expectLater(
        failing.import(
          usr(['Easy\nIntermediate'], withSet: true),
          now: now,
          venueEntityMode: false,
          newId: nextId,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await dances.listAll(includeDeleted: true), isEmpty);
      expect(await labels(), ['Beginner', 'Intermediate', 'Advanced']);
    });

    test('a skipped dance leaves no level behind', () async {
      final batch = await importer.plan(usr(['Easy\nIntermediate']));
      final result = await importer.commit(
        ImportBatchResult(
          records: [
            ImportRecordPlan(
              draft: batch.records.single.draft,
              verdict: DedupeVerdict.ambiguous(const []),
            ),
          ],
        ),
        CcUsrArchive(dances: const [], sets: const [], warnings: const []),
        now: now,
        venueEntityMode: false,
        newId: nextId,
      );
      expect(result.danceSession.committedCount, 0);
      expect(result.insertedDifficultyLevelIds, isEmpty);
      expect(await labels(), ['Beginner', 'Intermediate', 'Advanced']);
    });

    test('the per-row Edit creates the level too', () async {
      final batch = await importer.plan(usr(['Intermediate\nAdvanced']));
      final session = await importer.commitDances(
        batch,
        now: now,
        newId: nextId,
      );
      expect(session.committedCount, 1);
      expect(await levelOf('Dance 0'), 'Intermediate/Advanced');
    });
  });
}

class _FailingProgramRepository extends ProgramRepository {
  _FailingProgramRepository(super.db);

  @override
  Future<void> create(Program program, {LiveVenueIds? knownVenueIds}) async =>
      throw StateError('simulated program persist failure');
}
