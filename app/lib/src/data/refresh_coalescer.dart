import 'dart:async';

import 'package:flutter/foundation.dart';

/// Collapses several refresh broadcasts that arrive in the same synchronous
/// block into a single reload.
///
/// A single user action can bump `CollectionRefreshScope` more than once in one
/// synchronous block — a batch edit committing several dances, for instance —
/// and the notifier fires synchronously each time. A listener would otherwise
/// reload once per bump; this keeps it at one reload per action, the constraint
/// issue #340 records: fixing a stale view must not produce a thrashing one.
///
/// It used to collapse *two channels* as well, when a dances-and-programs write
/// bumped `ProgramsRefreshScope` immediately after. That scope was retired once
/// every program view became stream-driven (issue #768), so only the
/// same-channel burst remains — and the coalescer is still load-bearing for it,
/// as `program_summary_screen.dart` records for the stream-side equivalent.
///
/// Two screens use it, and neither is a "both-channels subscriber" any more —
/// a claim this comment carried until #768 retired the second channel, and
/// which was already false before that:
///
/// * `DanceDetailScreen` — driven by `CollectionRefreshScope`, the app's last
///   surviving refresh-scope subscription. A batch edit can bump it several
///   times in one block, which is the case this collapses.
/// * `ProgramSummaryScreen` — driven by no scope at all. It coalesces
///   `CollectionData.watch` emits, since that stream leads-and-trails and one
///   burst can deliver two. Its own file records the same fact from its side.
///
/// So this type outlived the two-channel problem it was built for, and is kept
/// for the single-source bursts that remain — not for the reason its name and
/// this comment used to give.
///
/// Deferral is a microtask, not a frame, so a reload still starts before the
/// next build and `pumpAndSettle` observes it without extra pumps.
class RefreshCoalescer {
  RefreshCoalescer(this._reload);

  /// Invoked once per batch of [request] calls. Responsible for its own
  /// `mounted` check — it runs after the current synchronous block.
  final VoidCallback _reload;

  bool _scheduled = false;

  /// Asks for a reload, joining any request already pending this microtask.
  void request() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      _reload();
    });
  }
}
