import 'dart:isolate';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
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
        testFigure(move: move, params: {'beats': beats}),
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

  /// Turns of the event loop until [done], failing after [turns] of them.
  Future<void> until(bool Function() done, {int turns = 100000}) async {
    for (var i = 0; i < turns && !done(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(done(), isTrue, reason: 'condition not reached');
  }

  test('a newer call stops an older one mid-send, and the older one cannot '
      'send its revisions over the newer ones', () async {
    final worker = SuggestionWorker(chunkSize: 1);
    addTearDown(worker.dispose);
    final fillers = [
      for (var i = 0; i < 40; i++) candidate('f$i', [('petronella', 16)]),
    ];
    // "a" swings on the previous dance's beats at revision 1, not at 2. It
    // is last in the older call and first in the newer one.
    final a1 = candidate('a', [('do_si_do', 16), ('swing', 16)], revision: 1);
    final a2 = candidate('a', [('swing', 16), ('do_si_do', 16)], revision: 2);
    final b = candidate('b', [('swing', 16), ('do_si_do', 16)]);

    final older = worker.rank(request([...fillers, a1, b]));
    await until(() => worker.debugChunksSent >= 5);
    final sentBefore = worker.debugChunksSent;
    final newerRequest = request([a2, ...fillers, b]);
    final newer = worker.rank(newerRequest);

    await expectLater(older, throwsA(isA<SuggestionRankSuperseded>()));
    final ranking = await newer;
    // The newer call sent "a" and every filler and "b" the older had not;
    // the older sent nothing more once the newer started.
    // (With a chunk of one, that is one chunk per candidate of the newer
    // call: the fillers the older sent are the same revision.)
    expect(sentBefore, lessThan(newerRequest.candidates.length));
    expect(worker.debugChunksSent, newerRequest.candidates.length);
    expect(
      ranking.order
          .singleWhere((r) => r.danceId == 'a')
          .reasons
          .map((r) => r.kind),
      isNot(contains(SuggestionReasonKind.beatOverlap)),
      reason: 'ranked at revision 2',
    );
    // And the worker still holds revision 2.
    final again = await worker.rank(newerRequest);
    expect(worker.debugChunksSent, newerRequest.candidates.length);
    expect(ids(again), ids(ranking));
  });

  test('the worker ranks only the newest request waiting, and answers the '
      'older ones as superseded', () {
    final replies = <Object?>[];
    final inbox = SuggestionWorkerInbox(replies.add);
    final c = candidate('c', [('swing', 16)]);
    inbox.receive([c]);
    expect(inbox.receive((1, request(const []), ['c'])), isTrue);
    expect(inbox.receive((2, request(const []), ['c'])), isTrue);
    inbox.rankWaiting();
    inbox.rankWaiting();
    expect(replies, hasLength(2));
    expect(replies.first, ('superseded', 1));
    expect(replies.last, isA<(int, SuggestionRanking)>());
    expect((replies.last! as (int, SuggestionRanking)).$1, 2);
  });

  test('dispose while the worker is still starting stops it', () async {
    final worker = SuggestionWorker();
    final call = worker.rank(
      request([
        candidate('c', [('swing', 16)]),
      ]),
    );
    worker.dispose();
    await expectLater(call, throwsStateError);
    await worker.debugExited.timeout(const Duration(seconds: 30));
  });

  test('a worker that dies fails the waiting call, and the next call starts '
      'a new one', () async {
    final worker = SuggestionWorker();
    addTearDown(worker.dispose);
    final req = request([
      candidate('c', [('swing', 16)]),
    ]);
    await worker.rank(req);
    final first = worker.debugIsolate!;
    final waiting = worker.rank(req);
    first.kill(priority: Isolate.immediate);
    await expectLater(
      waiting.timeout(const Duration(seconds: 30)),
      throwsStateError,
    );
    expect(ids(await worker.rank(req)), ['c']);
    expect(worker.debugIsolate, isNot(same(first)));
  });

  test('a re-rank for a new position, with the candidates already held, '
      'ranks for that position (#2344)', () async {
    final worker = SuggestionWorker();
    addTearDown(worker.dispose);
    // "next" swings on beats 16-32; "prev" (above) does too.
    final next = candidate('next', [('circle', 16), ('swing', 16)]);
    final overlaps = candidate('overlaps', [('petronella', 16), ('swing', 16)]);
    final clean = candidate('clean', [('swing', 16), ('petronella', 16)]);
    SuggestionRequest at(SuggestionPosition position) => SuggestionRequest(
      slotsBefore: position.slotsBefore,
      slotsAfter: position.slotsAfter,
      candidateIsAlternate: position.isAlternate,
      programDances: {'prev': previous, 'next': next},
      candidates: [overlaps, clean],
      settings: SuggestionSettings.defaults,
      today: today,
      taxonomy: shippedTaxonomies.anyForm,
    );
    final slots = [
      ProgramSlot(id: 's0', position: 0, danceId: 'prev'),
      ProgramSlot(id: 's1', position: 1, text: Program.breakSlotText),
      ProgramSlot(id: 's2', position: 2, danceId: 'next'),
      ProgramSlot(id: 's3', position: 3, danceId: 'prev', isAlt: true),
    ];
    String reasonsOf(SuggestionRanking r) => [
      for (final s in r.order)
        '${s.danceId}: ${[for (final x in s.reasons) '${x.kind.name}/${x.neighbor?.name}/${x.neighborDanceId}'].join(', ')}',
    ].join('\n');
    for (final position in [
      SuggestionPosition.atEnd(slots),
      SuggestionPosition.inserting(slots, 2, after: false),
      SuggestionPosition.replacing(slots, 3),
      SuggestionPosition.replacing(slots, 2),
    ]) {
      // The first pass sends the candidates; the later ones only their ids.
      final direct = rankSuggestions(at(position));
      expect(
        reasonsOf(await worker.rank(at(position))),
        reasonsOf(direct),
        reason: '${position.slotsBefore.length} before',
      );
    }
    // The positions really differ: before "next", the overlap is with it.
    final before = await worker.rank(
      at(SuggestionPosition.inserting(slots, 2, after: false)),
    );
    expect(ids(before), ['clean', 'overlaps']);
    final reason = before.order.last.reasons.firstWhere(
      (x) => x.kind == SuggestionReasonKind.beatOverlap,
    );
    expect(reason.neighborDanceId, 'next');
    expect(reason.neighbor, SuggestionNeighbor.next);
  });
}
