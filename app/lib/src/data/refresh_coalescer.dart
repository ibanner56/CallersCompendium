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
/// `ProgramSummaryScreen` is the remaining both-channels subscriber: it renders
/// program data and the dances inside it, so it listens to each. The two
/// Collection-side views that used to — the "called ×N" badge and the dance
/// detail's calling history — no longer do, because they read their
/// program-derived data from a stream now (issue #768). They still route their
/// one remaining channel through here, for the case where a single mutation
/// site bumps the same notifier more than once in a block.
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
