import 'dart:async';

import 'package:flutter/foundation.dart';

/// Collapses several refresh broadcasts that arrive in the same synchronous
/// block into a single reload.
///
/// A write that touches both dances and programs — a shared-bundle import, for
/// instance — bumps `CollectionRefreshScope` and `ProgramsRefreshScope` one
/// after the other, and both notifiers fire synchronously. Any view listening
/// to more than one bump in a single block would otherwise reload once per
/// bump; this keeps it at one reload per user action, which is the constraint
/// issue #340 records: fixing a stale view must not produce a thrashing one.
///
/// No view subscribes to *both* channels any more — the two that did now read
/// their program-derived data from a stream instead (issue #768). What remains
/// is the single-channel case: one mutation site can bump the same notifier
/// more than once in a block (a commit followed by its own follow-up write),
/// and a screen that re-boots per bump would load twice for one action.
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
