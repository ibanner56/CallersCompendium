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
///
/// ## A non-positive window short-circuits to an identity transformer
///
/// A zero window means "coalesce nothing", and without a short-circuit it does
/// **not** deliver that. `Timer(Duration.zero, …)` is still a real timer: the
/// leading edge emits, the timer is armed, and any event arriving before it
/// fires is held and replaced. A synchronous burst of `1, 2, 3` therefore
/// emitted `1, 3` — the middle value silently dropped by a window that was
/// supposed to be inert.
///
/// That is a trap for exactly the caller most likely to pass zero: a test using
/// it as the disabled control arm against which a real window is measured. Such
/// a control was quietly doing some coalescing of its own.
///
/// So a zero — or negative — window returns the source stream untouched. A
/// negative one is a programmer error and the `assert` in [bind] says so, but
/// asserts are stripped in release, so the release behaviour has to be defined
/// rather than merely disapproved of.
///
/// The two figures that justify
/// the detail screen's window were re-measured under both implementations and
/// are identical (`1 vs 2` for a burst written one transaction at a time,
/// `1 vs 1` for one issued all at once), so this changes no conclusion already
/// drawn from them — those bursts have real time between their events, which is
/// why they never exercised the same-turn case above.
class CoalesceTrailing<T> extends StreamTransformerBase<T, T> {
  const CoalesceTrailing(this.window);

  final Duration window;

  /// Whether [window] makes this transformer a pass-through.
  ///
  /// A named predicate rather than an inline comparison so the **release**
  /// half of the negative-window contract is testable. The `assert` in [bind]
  /// fires first in debug, which is where tests run, so the identity path for a
  /// negative window cannot be observed through [bind] at all — a test for it
  /// could only ever be skipped, and a guard that never runs is
  /// indistinguishable from one that does nothing.
  static bool isInert(Duration window) => window <= Duration.zero;

  @override
  Stream<T> bind(Stream<T> stream) {
    // A negative window is meaningless, and the interesting part is what
    // happens without a guard: `Timer` does not reject a negative duration, it
    // constructs fine and fires as soon as possible (verified, not assumed —
    // "Timer throws on a negative duration" is the intuitive reason to check
    // for this and it is false). So the failure is silent.
    //
    // Two mechanisms, because they hold in different build modes and neither
    // covers the other:
    //
    // * the `assert` catches it in debug and in tests, where a programmer error
    //   should be loud and immediate;
    // * folding it into the zero case below is what holds in **release**, where
    //   asserts are stripped. Without that, the guard would protect exactly the
    //   builds that never ship.
    //
    // Deliberately not an `ArgumentError`. The consequence of no coalescing is
    // extra reloads, never a wrong result — every emit carries a complete
    // snapshot — so throwing in production would convert a performance
    // degradation into a crashed screen. Defined-and-inert is the proportionate
    // release behaviour; the assert is what makes it findable before then.
    assert(
      !window.isNegative,
      'a coalescing window cannot be negative (got $window): Timer would '
      'accept it and fire immediately, silently disabling coalescing',
    );
    // See the doc above for zero; a negative window joins it rather than
    // reaching the timers below.
    if (isInert(window)) return stream;
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
