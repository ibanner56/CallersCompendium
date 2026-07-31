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

    expect(await dances.searchText('petronella'), contains('mw'));
    expect(await dances.searchText('do si do'), contains('mw'));
  });
}
