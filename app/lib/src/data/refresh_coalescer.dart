import 'dart:async';

import 'package:flutter/foundation.dart';

/// Collapses several refresh broadcasts that arrive in the same synchronous
/// block into a single reload.
///
/// A write that touches both dances and programs — a shared-bundle import, for
/// instance — bumps `CollectionRefreshScope` and `ProgramsRefreshScope` one
/// after the other. Both notifiers fire synchronously, so a view subscribed to
/// both would reload twice for one user action. Routing both listeners through
/// a coalescer keeps that at one reload per mutation, which is the constraint
/// issue #340 records: fixing a stale view must not produce a thrashing one.
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
