import 'package:flutter/widgets.dart';

typedef SyncWriterCallback =
    Future<T> Function<T>(Future<T> Function() operation);

/// Provides the lifecycle hooks that serialize every database-backed writer
/// with the running sync coordinator (ROADMAP G.5).
///
/// A restore, a shared archive import, or a sync review-queue resolution (the
/// review screen and the conflict sheet) writes into the database while the
/// running app also owns an optional database-backed sync coordinator.
/// [runWrite] owns the whole writer operation, so shutdown can wait for it and
/// prevent the coordinator from being recreated after shutdown begins. The
/// review screen uses [runRecordWrite] instead, the same boundary without the
/// coordinator rebuild; the conflict sheet still uses [runWrite].
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
    this.runRecordWrite,
    required super.child,
  });

  /// Serializes a database-backed writer with sync and application shutdown.
  final SyncWriterCallback? runWrite;

  /// [runWrite]'s serialization for a write that changes records the way an
  /// ordinary local edit does, rather than replacing the library: it still
  /// waits for the in-flight pass, starts no pass until the write returns, and
  /// is awaited by shutdown, but keeps the running coordinator and its session
  /// state instead of rebuilding it with a fresh pass. A sync trigger during
  /// the write is deferred until it returns, not dropped. The sync review screen resolves through this, where several
  /// resolves in a row are normal.
  final SyncWriterCallback? runRecordWrite;

  /// Reloads the dialect/theme controllers and preference notifiers from the
  /// (freshly restored) `settings` table so the live UI updates immediately.
  final Future<void> Function()? onRestored;

  static SyncWriterLifecycleScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncWriterLifecycleScope>();

  @override
  bool updateShouldNotify(SyncWriterLifecycleScope oldWidget) =>
      oldWidget.onRestored != onRestored ||
      oldWidget.runWrite != runWrite ||
      oldWidget.runRecordWrite != runRecordWrite;
}
