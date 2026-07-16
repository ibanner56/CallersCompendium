import 'package:flutter/widgets.dart';

/// Provides the "refresh the live app after a restore" hook to the Settings
/// screen's backup controls (ROADMAP G.5).
///
/// A [BackupService] restore writes the restored data into the database and the
/// `settings` table, but the running app holds preference values in notifiers
/// and the dialect/theme controllers in memory. [onRestored] re-reads all of
/// those so the UI reflects the restored state without a relaunch. It is wired
/// in `main.dart` to `_CompendiumAppState`'s reload sequence.
///
/// Optional by design: [maybeOf] returns `null` in focused widget tests that
/// don't exercise restore. The running app always provides it.
class BackupControllerScope extends InheritedWidget {
  const BackupControllerScope({
    super.key,
    required this.onRestored,
    required super.child,
  });

  /// Reloads the dialect/theme controllers and preference notifiers from the
  /// (freshly restored) `settings` table so the live UI updates immediately.
  final Future<void> Function() onRestored;

  static BackupControllerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackupControllerScope>();

  @override
  bool updateShouldNotify(BackupControllerScope oldWidget) =>
      oldWidget.onRestored != onRestored;
}
