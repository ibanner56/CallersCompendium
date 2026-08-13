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
/// It was built for a listener on two refresh channels, collapsing the pair of
/// bumps a dances-and-programs write emitted. Both of those channels have since
/// lost their subscribers to the reactive conversion (issue #768), so what it
/// collapses now is a burst from a single source — which is still worth
/// collapsing, and is why this survives rather than retiring with them.
///
/// Deliberately not a list of which screens use it. That list was wrong twice
/// while the conversion was in progress, in both directions, and a consumer
/// list is exactly the kind of claim a file cannot keep true about other files.
/// The type is useful to any caller with a bursty signal and a reload to
/// protect; the callers say so themselves.
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
