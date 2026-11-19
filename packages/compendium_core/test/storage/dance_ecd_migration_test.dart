import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// The opt-in ECD migration (ADR-006 §12.1 F5) at the repository: preview
/// and apply agree, only English dances are touched, and every other field
/// is kept.
void main() {
  final now = DateTime.utc(2026, 6, 1);

  DanceRepository repoFor(CompendiumDatabase db) => DanceRepository(
    db,
    shippedTaxonomies.anyForm,
    taxonomyForForm: shippedTaxonomies.forForm,
  );

  Dance englishDance(String id, {DanceForm form = DanceForm.ecd}) =>
      sampleDance(
        id: id,
        title: id,
        figures: [
          Figure(move: 'circle', params: {'direction': 'left', 'beats': 8}),
          customFigure(
            'partners set and turn single',
            beats: 8,
            origin: CustomOrigin.importGap,
          ),
        ],
      ).copyWith(
        form: form,
        formation: const Formation(FormationShape.dupleProper),
        hook: 'keep me',
      );

  test(
    'previews and migrates only English dances, keeping other fields',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repo = repoFor(db);
      await repo.create(englishDance('b-english'));
      await repo.create(englishDance('a-contra', form: DanceForm.contra));
      await repo.create(
        sampleDance(
          id: 'c-done',
          title: 'c-done',
          figures: [
            Figure(move: 'ecd_circle', params: {'direction': 'left'}),
          ],
        ).copyWith(
          form: DanceForm.ecd,
          formation: const Formation(FormationShape.dupleMinor),
        ),
      );

      final previews = await repo.previewEcdMigration(
        migrate: migrateEcdDanceForStorage,
      );
      expect(previews.map((p) => p.danceId), ['b-english']);
      expect(previews.single.movesConverted, 1);
      expect(previews.single.linesReread, 1);
      expect(previews.single.shapeChanged, isTrue);

      final changed = await repo.migrateEcdDances(
        ['a-contra', 'b-english', 'c-done', 'missing'],
        migrate: migrateEcdDanceForStorage,
        now: now,
      );
      expect(changed, 1);
      final english = (await repo.getById('b-english'))!;
      expect(english.formation, const Formation(FormationShape.dupleMinor));
      expect(english.hook, 'keep me');
      expect(english.updatedAt, now);
      final figures = (english.figuresSource as DecodedFigures).figures;
      expect(figures.first.move, 'ecd_circle');
      expect(figures.last.isSequence, isTrue);

      final contra = (await repo.getById('a-contra'))!;
      expect(
        (contra.figuresSource as DecodedFigures).figures.first.move,
        'circle',
      );
      expect(contra.formation.shape, FormationShape.dupleProper);

      // Applying again changes nothing more.
      expect(
        await repo.migrateEcdDances(
          ['b-english'],
          migrate: migrateEcdDanceForStorage,
          now: now,
        ),
        0,
      );
      expect(
        await repo.previewEcdMigration(migrate: migrateEcdDanceForStorage),
        isEmpty,
      );
    },
  );
  test('the migration is not a local user edit: it leaves a held sync '
      'tombstone in place', () async {
    // §6.8: only a deliberate user edit cancels a pending tombstone; the
    // migration re-expresses stored content, as the re-check does.
    // `_updateMany` defaults the flag to true, so this pins the explicit false.
    final db = openTestDatabase();
    addTearDown(db.close);
    final repos = CompendiumRepositories(db, shippedTaxonomies.anyForm);
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final dance = englishDance('held');
    await repos.dances.create(dance);
    await repos.syncLocal.upsertPendingDeletion(
      kind: SyncRecordKind.dance,
      recordId: 'held',
      tombstonedAt: stamp,
      tombstoneHash: 'hash',
      tombstoneBlob: encodeSyncRecordBlob(
        SyncRecordBlob(
          kind: SyncRecordKind.dance,
          id: 'held',
          updatedAt: stamp,
          deletedAt: stamp,
          existenceAt: stamp,
          body: syncBodyForEntity(SyncRecordKind.dance, dance),
        ),
      ),
    );

    final changed = await repos.dances.migrateEcdDances(
      ['held'],
      migrate: migrateEcdDanceForStorage,
      now: now,
    );

    expect(changed, 1);
    expect(
      await repos.syncLocal.getPendingDeletion(
        kind: SyncRecordKind.dance,
        recordId: 'held',
      ),
      isNotNull,
      reason: 'the migration must not cancel a pending tombstone',
    );
  });
}
