import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Exposes [CoalesceTrailing] to tests that want to exercise the transformer in
/// isolation, without a database or a snapshot loader behind it.
@visibleForTesting
StreamTransformerBase<T, T> debugCoalesceTrailing<T>(Duration window) =>
    CoalesceTrailing<T>(window);

/// Collapses events arriving within [window] of each other, emitting the
/// **first** immediately and then at most one per window for as long as the
/// burst continues.
///
/// Not "one leading plus one trailing": the window is deliberately re-armed
/// after each trailing emit, so a burst longer than [window] keeps reporting
/// progress at that rate instead of going silent until it ends. A 200-dance
/// batch should move the UI while it runs. The bound this guarantees is
/// therefore a *rate* — one emit per window — not a total.
///
/// Leading-edge rather than a plain trailing debounce, so the first change a
/// user makes is reflected without waiting out the window; the trailing emit
/// then covers everything that arrived during it. A pure trailing debounce
/// would delay every single-write update by the full window for no benefit.
///
/// ## What it replaces, and why every reactive snapshot needs one
///
/// A snapshot re-read driven by a refresh broadcast had an implicit batch
/// boundary: the mutation site knew when its loop ended and broadcast once,
/// after it. A reactive read loses that boundary by construction, because the
/// notification source is the database and the database sees N commits rather
/// than one user action. This restores the one-action / one-reload property at
/// the point the events now originate.
///
/// The window itself is **not** declared here, deliberately. It has to be
/// measured against the burst shape a given consumer actually faces, and a
/// shared default would be a number no caller had checked — so each states its
/// own and shows its working.
class CoalesceTrailing<T> extends StreamTransformerBase<T, T> {
  const CoalesceTrailing(this.window);

  final Duration window;

  @override
  Stream<T> bind(Stream<T> stream) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    Timer? timer;
    var pending = false;
    late T last;

    void flush() {
      timer = null;
      if (!pending) return;
      pending = false;
      controller.add(last);
      // Keep the window open after a trailing emit so a burst that continues
      // past it is still collapsed rather than emitting once per window.
      timer = Timer(window, flush);
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = stream.listen(
          (event) {
            last = event;
            if (timer == null) {
              controller.add(event); // leading edge
              timer = Timer(window, flush);
            } else {
              pending = true;
            }
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            timer = null;
            // Emit anything still held before closing. Without this the final
            // state of a burst is lost whenever the source ends mid-window —
            // a database closed during teardown, or a screen disposed while a
            // batch is still committing — which would contradict the trailing
            // guarantee this transformer exists to provide.
            if (pending) {
              pending = false;
              controller.add(last);
            }
            controller.close();
          },
        );
      },
      // Forward backpressure to the source. A consumer that maps each event to
      // an async load — the shape every caller here has — pauses its
      // subscription while that load runs. Without these hooks the pause stops
      // at this controller: the upstream keeps delivering, the controller
      // buffers, and every buffered event becomes another queued reload the
      // moment the slow one finishes — so a burst arriving during a long load
      // costs MORE work than the same burst arriving when idle, which is the
      // opposite of what the coalescing is for.
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        timer?.cancel();
        timer = null;
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
