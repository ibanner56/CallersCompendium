import 'dart:async';

import 'package:flutter/foundation.dart';

/// Collapses several refresh broadcasts that arrive in the same synchronous
/// block into a single reload.
///
/// A single user action can request several reloads in one synchronous block —
/// a batch edit touching several dances, for instance. A caller would otherwise
/// reload once per request; this keeps it at one reload per action, the
/// constraint issue #340 records: fixing a stale view must not produce a
/// thrashing one.
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
