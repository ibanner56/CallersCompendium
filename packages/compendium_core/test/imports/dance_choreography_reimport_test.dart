import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

import '../figures_support.dart';
import '../storage/test_database.dart';

void main() {
  CompendiumRepositories openRepos() {
    final db = openTestDatabase();
    addTearDown(db.close);
    return CompendiumRepositories(db, contraTaxonomy);
  }

  test('a re-import does not cancel a peer\'s pending deletion', () async {
    // sync-spec 6.8 gates cancellation on the write's provenance, and
    // provenance is about where the content comes from rather than who asked
    // for it. A re-import is user-initiated but writes the *source's*
    // choreography, so it must not cancel a held tombstone: doing so would
    // resurrect a dance a peer deleted on the strength of imported content.
    // Copilot caught this opted in on #1374. The user still has a clean path -
    // editing the dance afterwards is authored, and does cancel.
    final repos = openRepos();
    final stamp = DateTime.utc(2026);
    final held = DateTime.utc(2026, 6, 15, 12);

    final original = Dance(
      id: 'saved',
      title: 'My edited title',
      figures: [
        testFigure(move: customMove, params: {'text': 'old'}),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    );
    await repos.dances.create(original);
    // A program slot is a citation, so the peer's tombstone is held rather
    // than applied and the row stays live and re-importable.
    await repos.programs.create(
      Program(
        id: 'citing-program',
        title: 'Citing program',
        slots: [ProgramSlot(id: 'slot', position: 0, danceId: 'saved')],
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
    await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.dance,
            id: 'saved',
            updatedAt: held,
            deletedAt: held,
            existenceAt: held,
            body: syncBodyForEntity(SyncRecordKind.dance, original),
          ),
        ),
      ],
      storage: CompendiumSyncStorage(repos),
    );
    expect(await repos.syncLocal.listPendingDeletions(), hasLength(1));

    expect(
      await replaceDanceChoreography(
        repos,
        targetDanceId: original.id,
        incoming: Dance(
          id: 'remote',
          title: 'Remote title',
          figures: [
            testFigure(move: customMove, params: {'text': 'new'}),
          ],
          createdAt: stamp,
          updatedAt: stamp,
        ),
        expectedUpdatedAt: original.updatedAt,
        now: DateTime.utc(2026, 7),
      ),
      DanceReimportResult.replaced,
    );

    expect(
      await repos.syncLocal.listPendingDeletions(),
      hasLength(1),
      reason:
          'the re-import writes imported content, so it must leave the hold '
          'for a later authored edit to cancel',
    );
  });

  test(
    're-import preserves collection metadata and replaces choreography',
    () async {
      final repos = openRepos();
      final original = Dance(
        id: 'saved',
        title: 'My edited title',
        formation: const Formation(FormationShape.dupleImproper),
        progression: Progression.single,
        figures: [
          testFigure(move: customMove, params: {'text': 'old'}),
        ],
        callingNotes: 'Keep this note',
        rating: 5,
        tagIds: const [],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await repos.dances.create(original);
      final incoming = Dance(
        id: 'remote',
        title: 'Remote title',
        formation: const Formation(FormationShape.becketCw),
        progression: Progression.double,
        figures: [
          testFigure(move: customMove, params: {'text': 'new'}),
        ],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      expect(
        await replaceDanceChoreography(
          repos,
          targetDanceId: original.id,
          incoming: incoming,
          expectedUpdatedAt: original.updatedAt,
          now: DateTime.utc(2026, 2),
        ),
        DanceReimportResult.replaced,
      );

      final saved = await repos.dances.getById(original.id);
      expect(saved!.title, original.title);
      expect(saved.callingNotes, original.callingNotes);
      expect(saved.rating, original.rating);
      expect(saved.formation, incoming.formation);
      expect(saved.progression, incoming.progression);
      expect(figuresOf(saved), figuresOf(incoming));
      expect(saved.updatedAt, DateTime.utc(2026, 2));
    },
  );

  test('re-import reports a target deleted while previewing', () async {
    final repos = openRepos();
    final incoming = Dance(
      id: 'remote',
      title: 'Remote',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    expect(
      await replaceDanceChoreography(
        repos,
        targetDanceId: 'missing',
        incoming: incoming,
        expectedUpdatedAt: DateTime.utc(2026),
      ),
      DanceReimportResult.targetMissing,
    );
  });

  test('re-import reports a target changed while previewing', () async {
    final repos = openRepos();
    final original = Dance(
      id: 'saved',
      title: 'Saved',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await repos.dances.create(original);
    await repos.dances.update(
      original.copyWith(
        callingNotes: 'Changed while previewing',
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    );
    final incoming = original.copyWith(title: 'Incoming');

    expect(
      await replaceDanceChoreography(
        repos,
        targetDanceId: original.id,
        incoming: incoming,
        expectedUpdatedAt: original.updatedAt,
      ),
      DanceReimportResult.targetChanged,
    );
    expect(
      (await repos.dances.getById(original.id))!.callingNotes,
      'Changed while previewing',
    );
  });

  group('an incoming transcription with no usable figures keeps the saved '
      'one', () {
    final stamp = DateTime.utc(2026);
    final provenance = Provenance(
      source: ProvenanceSource.callersbox,
      externalId: '457',
      importedAt: stamp,
    );
    Dance saved(FigureSource figures) => Dance(
      id: 'saved',
      title: 'Saved',
      figuresSource: figures,
      provenance: provenance,
      createdAt: stamp,
      updatedAt: stamp,
    );
    Dance incoming(FigureSource figures) => Dance(
      id: 'remote',
      title: 'Remote',
      figuresSource: figures,
      formation: const Formation(FormationShape.becketCw),
      createdAt: stamp,
      updatedAt: stamp,
    );
    final decoded = DecodedFigures([
      testFigure(move: customMove, params: {'text': 'kept'}),
    ]);
    const unreadable = UnreadableFigures('{"saved": "bytes"}');
    const incomingUnreadable = UnreadableFigures('{"other": "bytes"}');

    for (final (name, existingFigures, incomingFigures) in <(
      String,
      FigureSource,
      FigureSource,
    )>[
      ('unreadable over decoded', decoded, incomingUnreadable),
      ('unreadable over unreadable', unreadable, incomingUnreadable),
      ('empty over decoded', decoded, DecodedFigures(const [])),
      ('empty over unreadable', unreadable, DecodedFigures(const [])),
    ]) {
      test(name, () {
        final existing = saved(existingFigures);
        final result = withReimportedChoreography(
          existing,
          incoming(incomingFigures),
          updatedAt: DateTime.utc(2026, 2),
        );

        expect(result.figuresSource, existing.figuresSource);
        expect(result.formation, const Formation(FormationShape.becketCw));
        expect(result.provenance, provenance);
      });
    }
  });
}
