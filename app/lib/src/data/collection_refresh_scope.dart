import 'package:flutter/widgets.dart';

/// Broadcasts "the dance collection changed — reload the live list" to the
/// running Collection screen without coupling the caller to it.
///
/// A screen that mutates the collection outside the Collection tab's own
/// action handlers — notably the import review flow (ROADMAP 6.3), reached from
/// Settings while the Collection tab is kept alive in an `IndexedStack` — bumps
/// [revision] after a commit or undo. [DanceListScreen] listens and re-boots so
/// imported dances appear immediately, mirroring how a G.5 restore refreshes
/// the app via `BackupControllerScope`.
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
  static void bump(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<CollectionRefreshScope>();
    final revision = scope?.notifier;
    if (revision != null) revision.value++;
  }

  static ValueNotifier<int>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CollectionRefreshScope>()
      ?.notifier;
}
