import 'package:flutter/widgets.dart';

typedef SyncWriterCallback =
    Future<T> Function<T>(Future<T> Function() operation);

/// Provides the lifecycle hooks that serialize every database-backed writer
/// with the running sync coordinator (ROADMAP G.5).
///
/// A restore or shared archive import writes the restored data into the
/// database while the running app also owns an optional database-backed sync
/// coordinator. [runWrite] owns the whole writer operation, so shutdown can
/// wait for it and prevent the coordinator from being recreated after shutdown
/// begins.
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
    this.runWrite,
    required super.child,
  });

  /// Serializes a database-backed writer with sync and application shutdown.
  final SyncWriterCallback? runWrite;

  /// Reloads the dialect/theme controllers and preference notifiers from the
  /// (freshly restored) `settings` table so the live UI updates immediately.
  final Future<void> Function()? onRestored;

  static SyncWriterLifecycleScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncWriterLifecycleScope>();

  @override
  bool updateShouldNotify(SyncWriterLifecycleScope oldWidget) =>
      oldWidget.onRestored != onRestored || oldWidget.runWrite != runWrite;
}
