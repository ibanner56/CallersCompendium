import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final today = DateTime.utc(2026, 11, 23);

  SuggestionCandidate candidate(
    String id,
    List<(String, int)> moves, {
    int revision = 0,
  }) => SuggestionCandidate(
    id: id,
    figures: [
      for (final (move, beats) in moves)
        Figure(move: move, params: {'beats': beats}),
    ],
    revision: revision,
  );

  final previous = candidate('prev', [('circle', 16), ('swing', 16)]);

  SuggestionRequest request(List<SuggestionCandidate> candidates) =>
      SuggestionRequest(
        slotsBefore: [ProgramSlot(id: 's0', position: 0, danceId: 'prev')],
        programDances: {'prev': previous},
        candidates: candidates,
        settings: SuggestionSettings.defaults,
        today: today,
        taxonomy: shippedTaxonomies.anyForm,
      );

  List<String> ids(SuggestionRanking r) => [for (final s in r.order) s.danceId];

  test('ranks as rankSuggestions does, across chunks', () async {
    final worker = SuggestionWorker(chunkSize: 2);
    addTearDown(worker.dispose);
    final candidates = [
      for (var i = 0; i < 7; i++)
        candidate('c$i', [
          if (i.isEven) ('swing', 16) else ('do_si_do', 16),
          ('petronella', 16),
        ]),
    ];
    final direct = rankSuggestions(request(candidates));
    final viaWorker = await worker.rank(request(candidates));
    expect(ids(viaWorker), ids(direct));
    // Again, now held by the worker: the same answer.
    expect(ids(await worker.rank(request(candidates))), ids(direct));
  });

  test(
    'a candidate at a new revision replaces the one the worker holds',
    () async {
      final worker = SuggestionWorker();
      addTearDown(worker.dispose);
      // "a" swings on the previous dance's beats; "b" does not.
      final a = candidate('a', [('do_si_do', 16), ('swing', 16)]);
      final b = candidate('b', [('swing', 16), ('do_si_do', 16)]);
      expect(ids(await worker.rank(request([a, b]))), ['b', 'a']);

      // "a" is edited so it no longer collides, and "b" so it does.
      final a2 = candidate('a', [('swing', 16), ('do_si_do', 16)], revision: 1);
      final b2 = candidate('b', [('do_si_do', 16), ('swing', 16)], revision: 1);
      expect(ids(await worker.rank(request([a2, b2]))), ['a', 'b']);
    },
  );
}
