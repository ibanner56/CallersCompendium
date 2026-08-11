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
/// `BackupControllerScope`; `DanceDetailScreen` and the program summary pane
/// listen too, because both render dance fields that can be edited elsewhere
/// (issue #768).
///
/// Program data has its own channel, `ProgramsRefreshScope`. Keeping the two
/// separate means a view subscribes to the data it actually renders rather than
/// re-booting on every write (issue #340).
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
    final scope = context
        .getInheritedWidgetOfExactType<CollectionRefreshScope>();
    final revision = scope?.notifier;
    if (revision == null) return false;
    revision.value++;
    return true;
  }

  static ValueNotifier<int>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CollectionRefreshScope>()
      ?.notifier;
}
