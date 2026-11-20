import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// A stand-in for ECD's own taxonomy (ADR-006 §5.1): its IDs carry `ecd_`.
final _ecd = Taxonomy(
  version: 1,
  form: DanceForm.ecd,
  moves: const [
    MoveDef(id: 'ecd_set', displayName: 'set', renderTemplate: '{move}'),
  ],
);

void main() {
  final now = DateTime.utc(2026, 6, 1);

  test('the import-gap re-parse reads each dance with its own form\'s '
      'taxonomy', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final registry = TaxonomyRegistry(base: contraTaxonomy, forms: [_ecd]);
    final repo = DanceRepository(
      db,
      registry.anyForm,
      taxonomyForForm: registry.forForm,
    );
    Dance gapDance(String id, DanceForm form) =>
        sampleDance(
          id: id,
          title: id,
          figures: [
            customFigure('set', beats: 4, origin: CustomOrigin.importGap),
          ],
        ).copyWith(
          form: form,
          meter: form == DanceForm.ecd ? '3/4' : '',
          phraseStructure: form == DanceForm.ecd ? '4*8*3' : '',
        );
    await repo.create(gapDance('contra-dance', DanceForm.contra));
    await repo.create(gapDance('ecd-dance', DanceForm.ecd));

    final seen = <Taxonomy>[];
    final meters = <String?>[];
    final phrases = <String?>[];
    FigureReparseOutcome reparse(
      List<Figure> figures, {
      Taxonomy? taxonomy,
      String? meter,
      PhraseStructure? phraseStructure,
    }) {
      seen.add(taxonomy!);
      meters.add(meter);
      phrases.add(phraseStructure?.raw);
      return FigureReparseOutcome(figures: figures, upgradedCount: 0);
    }

    await repo.previewImportGapReparse(reparse: reparse);
    expect(
      seen,
      unorderedEquals([contraTaxonomy, registry.forForm(DanceForm.ecd)]),
    );
    // Each dance's own meter, so an English line counts bars by it.
    expect(meters, unorderedEquals(['', '3/4']));
    // And its phrase structure, the bars' fallback when it states no meter.
    expect(phrases, unorderedEquals(['', '4*8*3']));
    meters.clear();
    phrases.clear();

    seen.clear();
    await repo.reparseImportGapFiguresForMany(
      ['contra-dance', 'ecd-dance'],
      reparse: reparse,
      now: now,
    );
    expect(
      seen,
      unorderedEquals([contraTaxonomy, registry.forForm(DanceForm.ecd)]),
    );
    expect(meters, unorderedEquals(['', '3/4']));
    expect(phrases, unorderedEquals(['', '4*8*3']));
  });

  test('a phrase structure stored out of bounds reads as the apply reads it, '
      'and does not stop the preview', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final repo = DanceRepository(db, contraTaxonomy);
    await repo.create(
      sampleDance(
        id: 'old',
        figures: [
          customFigure('set', beats: 4, origin: CustomOrigin.importGap),
        ],
      ).copyWith(form: DanceForm.ecd),
    );
    // Written before the bounds existed: the row mapper loads it as standard.
    await db.customStatement(
      "UPDATE dances SET phrase_structure = '4*8*2000' WHERE id = 'old'",
    );
    final phrases = <String?>[];
    FigureReparseOutcome reparse(
      List<Figure> figures, {
      Taxonomy? taxonomy,
      String? meter,
      PhraseStructure? phraseStructure,
    }) {
      phrases.add(phraseStructure?.raw);
      return FigureReparseOutcome(figures: figures, upgradedCount: 0);
    }

    await repo.previewImportGapReparse(reparse: reparse);
    await repo.reparseImportGapFiguresForMany(
      ['old'],
      reparse: reparse,
      now: now,
    );
    expect(phrases, hasLength(2));
    expect(phrases.first, phrases.last);
  });

  test('without taxonomyForForm every dance re-parses with the repository\'s '
      'taxonomy', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final repo = DanceRepository(db, contraTaxonomy);
    await repo.create(
      sampleDance(
        figures: [
          customFigure('set', beats: 4, origin: CustomOrigin.importGap),
        ],
      ).copyWith(form: DanceForm.ecd),
    );
    final seen = <Taxonomy?>[];
    await repo.previewImportGapReparse(
      reparse: (figures, {taxonomy, meter, phraseStructure}) {
        seen.add(taxonomy);
        return FigureReparseOutcome(figures: figures, upgradedCount: 0);
      },
    );
    expect(seen, [same(contraTaxonomy)]);
  });
}
