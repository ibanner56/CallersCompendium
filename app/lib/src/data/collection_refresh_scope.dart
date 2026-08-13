import 'package:flutter/widgets.dart';

/// Broadcasts "dance data changed — reload the views that render it" without
/// coupling the caller to them.
///
/// A screen that mutates a dance outside the view showing it bumps [revision].
/// The bumpers are the import review flow (ROADMAP 6.3), reached from Settings
/// while the Collection tab is kept alive in an `IndexedStack`, the dance
/// editor, the re-parse batch, and the Collection list's own batch operations.
///
/// **Nothing subscribes any more, and the channel still has bumpers.** Those
/// are two separate facts and the pairing is the point: a bump is not an error
/// or a leak, it is a broadcast that currently reaches nobody. Each view that
/// used to reload from it now watches the database directly, the last of them
/// being the dance detail screen (issue #768). [maybeOf] — the only resolver
/// that registers a rebuild dependency, and therefore the only way to
/// subscribe — has no callers; `refresh_scopes_test.dart` holds that as a
/// ratchet rather than as a claim here.
///
/// So this channel is now removable, and removing it is its own step. What
/// makes it so is precisely the above: while a subscriber existed, deleting it
/// would have stranded that subscriber; while bumpers exist, deleting it means
/// visiting each of them.
///
/// Program data used to have its own channel, `ProgramsRefreshScope`, kept
/// separate so that a view subscribed to the data it actually renders rather
/// than re-booting on every write (issue #340). It has been retired: every
/// program view watches the database directly, so it had no subscribers left.
/// This is the last channel standing, for the same reason and pending the same
/// removal.
///
/// The dedupe rule that made the migration safe: **a mutation site either
/// broadcasts or reloads itself, never both.** [bump] reports whether a scope
/// was found so a site can fall back to its own reload when unscoped:
///
/// ```dart
/// if (!CollectionRefreshScope.bump(context)) await _boot();
/// ```
///
/// Optional by design: [maybeOf] returns `null` in focused widget tests that
/// don't mount it. The running app always provides it (wired in `main.dart`).
class CollectionRefreshScope extends InheritedNotifier<ValueNotifier<int>> {
  const CollectionRefreshScope({
    super.key,
    required ValueNotifier<int> revision,
    required super.child,
  }) : super(notifier: revision);

  /// The revision counter; incrementing it asks listeners to reload.
  ValueNotifier<int>? get revision => notifier;

  /// Requests a collection reload by advancing the revision counter.
  ///
  /// Returns `true` when a scope was found and notified, so an unscoped caller
  /// (a focused widget test) can fall back to reloading itself.
  static bool bump(BuildContext context) {
    final revision = notifierOf(context);
    if (revision == null) return false;
    revision.value++;
    return true;
  }

  /// The revision notifier, resolved **without** registering a dependency.
  ///
  /// The right choice for every caller that only intends to *broadcast*: a
  /// bumper that depends on this scope is rebuilt by every other bumper, which
  /// is issue #340's over-firing bought with no benefit.
  ///
  /// Also the right choice for a caller that must broadcast after its own
  /// context is gone — an undo callback outliving the screen that showed the
  /// snackbar — since the notifier has to be captured before the pop either
  /// way.
  ///
  /// Returning `null` when unscoped is load-bearing beyond the focused-test
  /// case below: a site can use the captured value's *nullness* as the test for
  /// "can I broadcast at all?", falling back to reloading itself when it
  /// cannot. That is the dedupe rule above, implemented. [notifierOf] and
  /// [maybeOf] agree on it, so swapping one for the other cannot disturb it —
  /// **deleting this scope would**, and any such site would then need an
  /// unconditional self-reload.
  static ValueNotifier<int>? notifierOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CollectionRefreshScope>()?.notifier;

  /// The revision notifier, **registering a rebuild dependency**.
  ///
  /// The only resolver here that subscribes, and it currently has no callers —
  /// every view that renders dance data watches the database instead. Kept
  /// rather than deleted because it is what the removal step above will act on,
  /// and because its behavioural difference from [notifierOf] is the thing that
  /// makes "no subscribers" checkable rather than assumed.
  ///
  /// Anything that merely bumps wants [notifierOf] instead: depending on this
  /// scope in order to broadcast on it means being rebuilt by every other
  /// broadcaster.
  static ValueNotifier<int>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CollectionRefreshScope>()
      ?.notifier;
}
