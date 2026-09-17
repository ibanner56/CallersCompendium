import 'package:flutter/widgets.dart';

/// Provides the lifecycle hooks that serialize every database-backed writer
/// with the running sync coordinator (ROADMAP G.5).
///
/// A restore or shared archive import writes the restored data into the
/// database while the running app also owns an optional database-backed sync
/// coordinator. [beforeWrite] must quiesce that coordinator before any writer
/// begins, and [afterWrite] must recreate it after the writer completes.
/// [onRestored] remains the separate in-memory refresh callback used by the
/// backup controls: it re-reads preferences so the UI reflects restored state
/// without a relaunch. The running app wires these callbacks in `main.dart`.
///
/// Optional by design: [maybeOf] returns `null` in focused widget tests that
/// don't exercise a database-backed writer. The running app always provides it.
class SyncWriterLifecycleScope extends InheritedWidget {
  const SyncWriterLifecycleScope({
    super.key,
    this.onRestored,
    this.beforeWrite,
    this.afterWrite,
    required super.child,
  });

  /// Stops new sync work and awaits any active pass before writer operations.
  final Future<void> Function()? beforeWrite;

  /// Recreates the database-backed sync coordinator after writer operations.
  final Future<void> Function()? afterWrite;

  /// Reloads the dialect/theme controllers and preference notifiers from the
  /// (freshly restored) `settings` table so the live UI updates immediately.
  final Future<void> Function()? onRestored;

  static SyncWriterLifecycleScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncWriterLifecycleScope>();

  @override
  bool updateShouldNotify(SyncWriterLifecycleScope oldWidget) =>
      oldWidget.onRestored != onRestored ||
      oldWidget.beforeWrite != beforeWrite ||
      oldWidget.afterWrite != afterWrite;
}
