import 'package:flutter/widgets.dart';

/// Broadcasts "dance data changed — reload the views that render it" without
/// coupling the caller to them.
///
/// A screen that mutates a dance outside the view showing it bumps [revision];
/// subscribers reload. That covers the import review flow (ROADMAP 6.3),
/// reached from Settings while the Collection tab is kept alive in an
/// `IndexedStack`, the dance editor, and the Collection list's own batch
/// operations. `DanceListScreen` re-boots so imported and batch-edited dances
/// appear immediately, mirroring how a G.5 restore refreshes the app via
/// `BackupControllerScope`.
///
/// **One screen subscribes: `DanceDetailScreen`.** It renders dance fields that
/// can be edited elsewhere and still loads them with a one-shot future, so this
/// channel is the only thing that makes such an edit appear in the detail pane.
/// The program summary pane used to listen as well and no longer does — it
/// moved to `CollectionData.watch` (issue #768; see
/// `program_summary_screen.dart`, which records the same fact from its side).
/// Every other reader here captures the notifier in order to *bump* it.
///
/// Program data used to have its own channel, `ProgramsRefreshScope`, kept
/// separate so that a view subscribed to the data it actually renders rather
/// than re-booting on every write (issue #340). It has been retired: every
/// program view watches the database directly now, so it had no subscribers
/// left. This is the last channel standing, and it goes the same way once
/// `DanceDetailScreen` is converted.
///
/// The dedupe rule that keeps that promise: **a mutation site either broadcasts
/// or reloads itself, never both.** [bump] reports whether a scope was found so
/// a site can fall back to its own reload when unscoped:
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
  /// bumper that depends
  /// on this scope is rebuilt by every other bumper, which is issue #340's
  /// over-firing bought with no benefit.
  ///
  /// Also the right choice for a caller that must broadcast after its own
  /// context is gone — an undo callback outliving the screen that showed the
  /// snackbar — since the notifier has to be captured before the pop either
  /// way.
  ///
  /// Returning `null` when unscoped is load-bearing beyond the focused-test
  /// case below: several sites use the captured value's *nullness* as the test
  /// for "can I broadcast at all?", falling back to reloading themselves when
  /// they cannot (`dance_list_screen.dart`, `dance_detail_screen.dart`). That
  /// is the dedupe rule above, implemented. [notifierOf] and [maybeOf] agree on
  /// it, so swapping one for the other cannot disturb it — **deleting this
  /// scope would**, and those sites would then need unconditional self-reloads.
  static ValueNotifier<int>? notifierOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CollectionRefreshScope>()?.notifier;

  /// The revision notifier, **registering a rebuild dependency**.
  ///
  /// Only for a widget that genuinely wants rebuilding when the collection
  /// changes. Exactly one does: `DanceDetailScreen`, which listens. Anything
  /// that merely bumps wants [notifierOf] instead.
  static ValueNotifier<int>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CollectionRefreshScope>()
      ?.notifier;
}
