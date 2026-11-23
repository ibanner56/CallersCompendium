/// Runs [rankSuggestions] in a long-lived isolate that keeps the candidates it
/// has been sent (#2343).
///
/// Sending a request copies it, synchronously, on the calling isolate. For a
/// picker showing the whole collection that is tens of thousands of dances'
/// figures: one copy would hold the UI thread for hundreds of milliseconds,
/// and the builder re-ranks after every add. So the worker:
///
/// - keeps every candidate it has received, by id and
///   [SuggestionCandidate.revision], for its whole life (nothing is evicted);
/// - is sent only the candidates it does not hold at that revision, in chunks
///   of [SuggestionWorker.chunkSize], yielding to the event loop between
///   chunks so no single copy is long;
/// - is then sent the request with the candidates as ids.
///
/// Only the newest call matters. A call to [SuggestionWorker.rank] supersedes
/// every earlier one: an earlier call still sending chunks stops before its
/// next chunk, and the worker ranks only the newest request waiting for it,
/// answering the older ones as superseded. Either way the earlier call fails
/// with [SuggestionRankSuperseded].
///
/// The figures for the benchmark's 20,000 dances are in
/// `docs/design/suggestions.md`, "Performance".
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:math' show min;

import 'package:meta/meta.dart';

import 'suggestions.dart';

/// A [SuggestionWorker.rank] call that a newer call replaced before it
/// finished. Not an error: its result would be out of date.
class SuggestionRankSuperseded implements Exception {
  const SuggestionRankSuperseded();

  @override
  String toString() => 'SuggestionRankSuperseded';
}

/// See the library comment.
class SuggestionWorker {
  SuggestionWorker({this.chunkSize = 250});

  /// How many candidates one message to the worker carries.
  final int chunkSize;

  Isolate? _isolate;
  ReceivePort? _fromWorker;
  Future<SendPort>? _toWorker;
  Completer<SendPort>? _ready;

  /// What the running worker holds, by id: the revision last sent.
  final _held = <String, int>{};
  final _pending = <int, Completer<SuggestionRanking>>{};

  /// The newest call's number. A call whose number is no longer this one is
  /// superseded.
  var _generation = 0;

  /// Bumped each time a worker stops, so a call that started against a worker
  /// now gone does not wait for it.
  var _epoch = 0;
  var _disposed = false;
  final _exited = Completer<void>();

  /// Completes once a worker isolate this object started has exited after
  /// [dispose]. For tests.
  @visibleForTesting
  Future<void> get debugExited => _exited.future;

  var _chunksSent = 0;

  /// How many chunks of candidates this object has sent. For tests.
  @visibleForTesting
  int get debugChunksSent => _chunksSent;

  /// The running worker isolate, if any. For tests.
  @visibleForTesting
  Isolate? get debugIsolate => _isolate;

  Future<SendPort> _start() => _toWorker ??= _spawn();

  Future<SendPort> _spawn() async {
    final port = ReceivePort();
    _fromWorker = port;
    final ready = _ready = Completer<SendPort>();
    // A worker that stops before it is ready fails [ready]; nobody may be
    // waiting on it by then (a call disposed while spawning).
    ready.future.ignore();
    port.listen((Object? message) {
      switch (message) {
        case SendPort send:
          if (!ready.isCompleted) ready.complete(send);
        case (int id, SuggestionRanking ranking):
          _pending.remove(id)?.complete(ranking);
        case (int id, String error):
          _pending.remove(id)?.completeError(StateError(error));
        case ('superseded', int id):
          _pending.remove(id)?.completeError(const SuggestionRankSuperseded());
        case [final Object? error, _]:
          // The worker's uncaught error (onError); it is fatal.
          if (identical(_fromWorker, port)) {
            _stop('suggestion worker failed: $error');
          }
        case null:
          // The worker exited (onExit).
          if (identical(_fromWorker, port)) _stop('suggestion worker exited');
          if (_disposed && !_exited.isCompleted) _exited.complete();
          port.close();
      }
    });
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _workerMain,
        port.sendPort,
        onError: port.sendPort,
        onExit: port.sendPort,
      );
    } catch (_) {
      port.close();
      if (identical(_fromWorker, port)) {
        _fromWorker = null;
        _toWorker = null;
        _ready = null;
      }
      rethrow;
    }
    _isolate = isolate;
    if (_disposed) {
      // Disposed while spawning: stop it now (the exit closes the port).
      isolate.kill(priority: Isolate.immediate);
      throw StateError('SuggestionWorker disposed');
    }
    return ready.future;
  }

  /// Fails every waiting call and forgets the worker, so the next call
  /// starts a new one.
  void _stop(String reason) {
    _epoch++;
    final pending = [..._pending.values];
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(StateError(reason));
    }
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError(reason));
    }
    _held.clear();
    _toWorker = null;
    _ready = null;
    _fromWorker = null;
    _isolate = null;
  }

  /// Ranks [request] in the worker. Every candidate comes back once, as
  /// [rankSuggestions] returns it. Fails with [SuggestionRankSuperseded] when
  /// a newer call replaces this one first, and with a [StateError] when the
  /// worker fails or exits.
  Future<SuggestionRanking> rank(SuggestionRequest request) async {
    if (_disposed) throw StateError('SuggestionWorker used after dispose');
    final generation = ++_generation;
    // Taken before the wait: a worker that stops while this call waits for it
    // fails the call rather than leaving it waiting on a dead isolate.
    final epoch = _epoch;
    final send = await _start();
    void check() {
      if (_disposed) throw StateError('SuggestionWorker disposed');
      if (generation != _generation) throw const SuggestionRankSuperseded();
      if (epoch != _epoch) throw StateError('suggestion worker stopped');
    }

    check();
    final missing = [
      for (final c in request.candidates)
        if (_held[c.id] != c.revision) c,
    ];
    for (var i = 0; i < missing.length; i += chunkSize) {
      // Checked right before each send, with no wait in between: once a newer
      // call has started, this one sends nothing more, so it cannot send a
      // candidate over the revision the newer call sent.
      check();
      final chunk = missing.sublist(i, min(i + chunkSize, missing.length));
      send.send(chunk);
      _chunksSent++;
      for (final c in chunk) {
        _held[c.id] = c.revision;
      }
      // Let a frame through between chunks.
      if (i + chunkSize < missing.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    check();
    final result = Completer<SuggestionRanking>();
    _pending[generation] = result;
    send.send((
      generation,
      request.withCandidates(const []),
      [for (final c in request.candidates) c.id],
    ));
    return result.future;
  }

  /// Stops the worker, including one still starting. A call still waiting
  /// never completes.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending.clear();
    final isolate = _isolate;
    if (isolate != null) {
      isolate.kill(priority: Isolate.immediate);
    } else if (_toWorker == null) {
      // Never started: nothing will exit.
      _exited.complete();
    }
    // Otherwise it is still spawning: [_spawn] kills it once it exists.
  }
}

/// The worker's side, apart from the isolate so it can be tested directly:
/// holds candidates, and ranks only the newest request waiting.
@visibleForTesting
class SuggestionWorkerInbox {
  SuggestionWorkerInbox(this.reply);

  /// Sends a message to the caller.
  final void Function(Object? message) reply;

  final _held = <String, SuggestionCandidate>{};
  (int, SuggestionRequest, List<String>)? _waiting;

  /// Takes one message from the caller. True when a request is now waiting
  /// and [rankWaiting] should run once the messages already queued are in.
  bool receive(Object? message) {
    switch (message) {
      case List<SuggestionCandidate> chunk:
        for (final c in chunk) {
          _held[c.id] = c;
        }
        return false;
      case (int id, SuggestionRequest request, List<String> ids):
        // A later request supersedes one not yet ranked.
        if (_waiting case (final older, _, _)?) {
          reply(('superseded', older));
        }
        _waiting = (id, request, ids);
        return true;
    }
    return false;
  }

  /// Ranks the waiting request, if any, and replies.
  void rankWaiting() {
    final job = _waiting;
    _waiting = null;
    if (job == null) return;
    final (id, request, ids) = job;
    try {
      final ranking = rankSuggestions(
        request.withCandidates([for (final i in ids) _held[i]!]),
      );
      reply((id, ranking));
    } catch (error) {
      reply((id, '$error'));
    }
  }
}

void _workerMain(SendPort toCaller) {
  final inbox = ReceivePort();
  toCaller.send(inbox.sendPort);
  final worker = SuggestionWorkerInbox(toCaller.send);
  var scheduled = false;
  inbox.listen((Object? message) {
    if (worker.receive(message) && !scheduled) {
      scheduled = true;
      // After the messages already queued, so a newer request that is
      // already on its way replaces this one before any ranking starts.
      Timer.run(() {
        scheduled = false;
        worker.rankWaiting();
      });
    }
  });
}
