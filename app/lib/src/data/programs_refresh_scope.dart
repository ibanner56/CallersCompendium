import 'package:flutter/widgets.dart';

/// Broadcasts "program data changed — reload the live program views" without
/// coupling the caller to them.
///
/// The Programs counterpart to `CollectionRefreshScope`. The two are separate
/// channels on purpose: a view subscribes to the data it actually renders, so a
/// dance edit does not re-boot the Programs list and a slot change does not
/// re-boot views that show no program-derived data. Program-derived data does
/// reach the Collection — the "called N times" badge and the dance detail
/// screen's calling history are both computed from `ProgramSlot` — so those two
/// views subscribe here as well as to the collection channel.
///
/// Bumped by every screen that writes a program or its slots: the builder's
/// explicit save/duplicate/delete, the summary's mark-all-performed and
/// in-event Perform adjustments, the "add to program" sheet, the program
/// import routes, and recently-deleted restore/purge. Deliberately **not**
/// bumped by the program builder's debounced autosave, which fires once per
/// slot edit — broadcasting from there would re-boot every subscriber on every
/// drag (issue #340).
///
/// The dedupe rule that keeps that promise: **a mutation site either broadcasts
/// or reloads itself, never both.** [bump] reports whether a scope was found so
/// a site can fall back to its own reload when unscoped:
///
/// ```dart
/// if (!ProgramsRefreshScope.bump(context)) await _load();
/// ```
///
/// Optional by design: [maybeOf] returns `null` in focused widget tests that
/// don't mount it. The running app always provides it (wired in `main.dart`).
class ProgramsRefreshScope extends InheritedNotifier<ValueNotifier<int>> {
  const ProgramsRefreshScope({
    super.key,
    required ValueNotifier<int> revision,
    required super.child,
  }) : super(notifier: revision);

  /// The revision counter; incrementing it asks listeners to reload.
  ValueNotifier<int>? get revision => notifier;

  /// Requests a program-view reload by advancing the revision counter.
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
  /// For callers that must broadcast after their own context is gone — the
  /// "add to program" sheet pops before its undo callback runs — capture this
  /// up-front and bump the notifier directly.
  static ValueNotifier<int>? notifierOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ProgramsRefreshScope>()?.notifier;

  static ValueNotifier<int>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ProgramsRefreshScope>()
      ?.notifier;
}
