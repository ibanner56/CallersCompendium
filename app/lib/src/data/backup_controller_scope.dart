import 'package:flutter/widgets.dart';

/// Provides the restore lifecycle hooks to the Settings screen's backup
/// controls (ROADMAP G.5).
///
/// A [BackupService] restore writes the restored data into the database and the
/// `settings` table, while the running app also owns an optional database-backed
/// sync coordinator. [beforeRestore] must quiesce that coordinator before any
/// restore write begins, and [afterRestore] must recreate it after the restore
/// operation completes. [onRestored] remains the separate in-memory refresh
/// callback: it re-reads preferences so the UI reflects the restored state
/// without a relaunch. The running app wires these callbacks in `main.dart`.
///
/// Optional by design: [maybeOf] returns `null` in focused widget tests that
/// don't exercise restore. The running app always provides it.
class BackupControllerScope extends InheritedWidget {
  const BackupControllerScope({
    super.key,
    required this.onRestored,
    this.beforeRestore,
    this.afterRestore,
    required super.child,
  });

  /// Stops new sync work and awaits any active pass before restore writes.
  final Future<void> Function()? beforeRestore;

  /// Recreates the database-backed sync coordinator after restore completes.
  final Future<void> Function()? afterRestore;

  /// Reloads the dialect/theme controllers and preference notifiers from the
  /// (freshly restored) `settings` table so the live UI updates immediately.
  final Future<void> Function() onRestored;

  static BackupControllerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackupControllerScope>();

  @override
  bool updateShouldNotify(BackupControllerScope oldWidget) =>
      oldWidget.onRestored != onRestored ||
      oldWidget.beforeRestore != beforeRestore ||
      oldWidget.afterRestore != afterRestore;
}
