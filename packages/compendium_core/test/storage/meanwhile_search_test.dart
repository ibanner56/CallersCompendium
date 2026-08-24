import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// The search indexer flattens a `meanwhile` container (#590) so each concurrent
/// side stays individually matchable: `filterByMove` matches every constituent
/// and FTS matches each side's canonical text, while the container occupies one
/// beat placement.
void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('flattens each side into its own move-indexed row', () async {
    final container = Figure.meanwhile(
      figures: [
        Figure(move: 'do_si_do', params: const {'who': 'neighbors'}),
        Figure(move: 'petronella'),
      ],
      beats: 8,
    );
    final dance = sampleDance(
      figures: [
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 8}),
        container,
      ],
    );
    await dances.create(dance);

    final rows = await (db.select(
      db.danceFigures,
    )..where((t) => t.danceId.equals(dance.id))).get();
    rows.sort((a, b) => a.idx.compareTo(b.idx));
    // 1 (swing) + 2 (the two concurrent sides) = 3 rows, with contiguous idx.
    expect(rows.map((r) => r.move), ['swing', 'do_si_do', 'petronella']);
    expect(rows.map((r) => r.idx), [0, 1, 2]);
    // `group_idx` correlates by top-level figure (#748): the leading swing is
    // its own group (0); the two concurrent container sides SHARE one group (1),
    // so `Then` never reads them as sequential.
    expect(rows.map((r) => r.groupIdx), [0, 1, 1]);
    // The container itself is not indexed as a `meanwhile` move.
    expect(rows.any((r) => r.move == meanwhileMove), isFalse);
  });

  test('filterByMove matches each constituent side', () async {
    final container = Figure.meanwhile(
      figures: [
        Figure(move: 'do_si_do', params: const {'who': 'neighbors'}),
        Figure(move: 'petronella'),
      ],
      beats: 8,
    );
    await dances.create(sampleDance(id: 'mw', figures: [container]));
    await dances.create(
      sampleDance(
        id: 'other',
        figures: [
          Figure(move: 'swing', params: const {'beats': 16}),
        ],
      ),
    );

    expect(await dances.search(FigureFilter.leaf('do_si_do')), ['mw']);
    expect(await dances.search(FigureFilter.leaf('petronella')), ['mw']);
  });

  test('FTS matches each side canonical text', () async {
    final container = Figure.meanwhile(
      figures: [
        Figure(move: 'do_si_do', params: const {'who': 'neighbors'}),
        Figure(move: 'petronella'),
      ],
      beats: 8,
    );
    await dances.create(sampleDance(id: 'mw', figures: [container]));
    await dances.create(
      sampleDance(
        id: 'see-saw',
        figures: [Figure(move: 'see_saw')],
      ),
    );

    expect(await dances.searchText('petronella'), contains('mw'));
    expect(await dances.searchText('dosido'), contains('mw'));
    expect(await dances.searchText('do si do'), contains('mw'));
    expect(await dances.searchText('do-si-do'), contains('mw'));
    expect(await dances.searchText('seesaw'), contains('see-saw'));
    expect(await dances.searchText('see saw'), contains('see-saw'));
    expect(await dances.searchText('see-saw'), contains('see-saw'));
  });

  test(
    'empty meanwhile container is not dropped — indexes a fallback row',
    () async {
      // A legacy/partial `{move:"meanwhile"}` decodes to zero sub-figures. The
      // flatten loop must NOT emit zero rows (which would erase the figure from
      // dance_figures + FTS, making the dance unsearchable by it, #590 review).
      // It falls back to indexing the container itself.
      final empty = figureFromJson({
        'move': meanwhileMove,
        'params': {'beats': 8},
      });
      expect(empty.isMeanwhile, isTrue);
      expect(empty.subFigures, isEmpty);

      final dance = sampleDance(
        id: 'empty-mw',
        figures: [
          Figure(move: 'swing', params: const {'beats': 8}),
          empty,
        ],
      );
      await dances.create(dance);

      final rows = await (db.select(
        db.danceFigures,
      )..where((t) => t.danceId.equals(dance.id))).get();
      rows.sort((a, b) => a.idx.compareTo(b.idx));
      // 1 (swing) + 1 (fallback container row) = 2 rows with contiguous idx.
      expect(rows.map((r) => r.move), ['swing', meanwhileMove]);
      expect(rows.map((r) => r.idx), [0, 1]);
      // The container stays searchable by its move.
      expect(
        await dances.search(FigureFilter.leaf(meanwhileMove)),
        contains('empty-mw'),
      );
    },
  );
}
