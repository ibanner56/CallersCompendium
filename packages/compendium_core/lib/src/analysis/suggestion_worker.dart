/// Runs [rankSuggestions] in a long-lived isolate that keeps the candidates it
/// has been sent (#2343).
///
/// Sending a request copies it, synchronously, on the calling isolate. For a
/// picker showing the whole collection that is tens of thousands of dances'
/// figures: one copy would hold the UI thread for hundreds of milliseconds,
/// and the builder re-ranks after every add. So the worker:
///
/// - keeps every candidate it has received, by id and [SuggestionCandidate.revision];
/// - is sent only the candidates it does not hold at that revision, in chunks
///   of [SuggestionWorker.chunkSize], yielding to the event loop between
///   chunks so no single copy is long;
/// - is then sent the request with the candidates as ids.
///
/// A re-rank of the same results (a dance added to the program) therefore
/// sends only the program and the ids. The figures for the benchmark's 20,000
/// dances are in `docs/design/suggestions.md`, "Performance".
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:math' show min;

import 'suggestions.dart';

/// See the library comment.
class SuggestionWorker {
  SuggestionWorker({this.chunkSize = 250});

  /// How many candidates one message to the worker carries.
  final int chunkSize;

  Isolate? _isolate;
  ReceivePort? _fromWorker;
  Future<SendPort>? _toWorker;
  final _held = <String, int>{};
  final _pending = <int, Completer<SuggestionRanking>>{};
  var _nextRequest = 0;
  var _disposed = false;

  Future<SendPort> _start() => _toWorker ??= () async {
    final port = ReceivePort();
    _fromWorker = port;
    final ready = Completer<SendPort>();
    port.listen((Object? message) {
      switch (message) {
        case SendPort send:
          ready.complete(send);
        case (int id, SuggestionRanking ranking):
          _pending.remove(id)?.complete(ranking);
        case (int id, String error):
          _pending.remove(id)?.completeError(StateError(error));
      }
    });
    _isolate = await Isolate.spawn(_workerMain, port.sendPort);
    return ready.future;
  }();

  /// Ranks [request] in the worker. Every candidate comes back once, as
  /// [rankSuggestions] returns it.
  Future<SuggestionRanking> rank(SuggestionRequest request) async {
    if (_disposed) throw StateError('SuggestionWorker used after dispose');
    final send = await _start();
    final missing = [
      for (final c in request.candidates)
        if (_held[c.id] != c.revision) c,
    ];
    for (var i = 0; i < missing.length; i += chunkSize) {
      if (_disposed) throw StateError('SuggestionWorker disposed');
      final chunk = missing.sublist(i, min(i + chunkSize, missing.length));
      send.send(chunk);
      for (final c in chunk) {
        _held[c.id] = c.revision;
      }
      // Let a frame through between chunks.
      if (i + chunkSize < missing.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    final id = _nextRequest++;
    final result = Completer<SuggestionRanking>();
    _pending[id] = result;
    send.send((
      id,
      request.withCandidates(const []),
      [for (final c in request.candidates) c.id],
    ));
    return result.future;
  }

  /// Stops the worker. A ranking still in flight never completes.
  void dispose() {
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _fromWorker?.close();
    _pending.clear();
  }
}

void _workerMain(SendPort toCaller) {
  final inbox = ReceivePort();
  toCaller.send(inbox.sendPort);
  final held = <String, SuggestionCandidate>{};
  inbox.listen((Object? message) {
    switch (message) {
      case List<SuggestionCandidate> chunk:
        for (final c in chunk) {
          held[c.id] = c;
        }
      case (int id, SuggestionRequest request, List<String> ids):
        try {
          final ranking = rankSuggestions(
            request.withCandidates([for (final i in ids) held[i]!]),
          );
          toCaller.send((id, ranking));
        } catch (error) {
          toCaller.send((id, '$error'));
        }
    }
  });
}
