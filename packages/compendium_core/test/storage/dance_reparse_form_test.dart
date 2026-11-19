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
    Dance gapDance(String id, DanceForm form) => sampleDance(
      id: id,
      title: id,
      figures: [customFigure('set', beats: 4, origin: CustomOrigin.importGap)],
    ).copyWith(form: form);
    await repo.create(gapDance('contra-dance', DanceForm.contra));
    await repo.create(gapDance('ecd-dance', DanceForm.ecd));

    final seen = <Taxonomy>[];
    FigureReparseOutcome reparse(List<Figure> figures, {Taxonomy? taxonomy}) {
      seen.add(taxonomy!);
      return FigureReparseOutcome(figures: figures, upgradedCount: 0);
    }

    await repo.previewImportGapReparse(reparse: reparse);
    expect(
      seen,
      unorderedEquals([contraTaxonomy, registry.forForm(DanceForm.ecd)]),
    );

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
      reparse: (figures, {taxonomy}) {
        seen.add(taxonomy);
        return FigureReparseOutcome(figures: figures, upgradedCount: 0);
      },
    );
    expect(seen, [same(contraTaxonomy)]);
  });
}
