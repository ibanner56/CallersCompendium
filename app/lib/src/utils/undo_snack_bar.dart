import 'package:flutter/material.dart';

/// How long an undo prompt stays visible before auto-dismissing on the default
/// (non-assistive) path. Chosen to give a comfortable window to react without
/// lingering over the bottom controls (issue #463).
const Duration kUndoSnackBarDuration = Duration(seconds: 6);

/// Shows the app-wide "Undo" prompt as a **transient** SnackBar.
///
/// Every undoable action in the app used to build a bare
/// `SnackBar(action: SnackBarAction(...))`. In Flutter 3.44.6 the `SnackBar`
/// constructor computes `persist = persist ?? action != null`, so any snackbar
/// with an action defaults to `persist: true` — and the scaffold's auto-dismiss
/// timer bails out (`if (snackBar.persist) return;`) for persisting snackbars.
/// The prompts therefore never went away, stacked on rapid actions, and sat over
/// the bottom navigation/controls (issue #463).
///
/// Routing every undo site through this helper fixes all of that centrally:
/// - [messenger].clearSnackBars() first, so rapid successive undoable actions
///   replace rather than stack.
/// - [SnackBarBehavior.floating] so the prompt floats above bottom-anchored
///   controls instead of covering them.
/// - a bounded [duration] so it auto-dismisses on its own.
/// - `persist: accessibleNavigation` so the deliberate, non-timed behavior is
///   preserved when assistive tech is active (screen-reader users keep as long
///   as they need to reach the action), while everyone else gets the transient
///   prompt. This is required because — contrary to a common assumption — the
///   scaffold's `_accessibleNavigation` handling only chooses jump-vs-animated
///   *exit*; it does not by itself disable the auto-dismiss timer, so the
///   persistence has to be expressed through `persist`.
///
/// Takes a [ScaffoldMessengerState] (not a [BuildContext]) because several
/// callers capture the messenger up-front and only show the prompt after an
/// async gap / navigation that may have unmounted the originating widget.
/// Callers should likewise capture [accessibleNavigation] (via
/// `MediaQuery.accessibleNavigationOf(context)`) and [undoLabel] (via
/// `AppLocalizations.of(context).commonUndo`) before that gap.
///
/// [key] is forwarded to the [SnackBar] so existing widget-test keys are kept.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showUndoSnackBar(
  ScaffoldMessengerState messenger, {
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
  required bool accessibleNavigation,
  Key? key,
  Duration duration = kUndoSnackBarDuration,
}) {
  messenger.clearSnackBars();
  return messenger.showSnackBar(
    SnackBar(
      key: key,
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: duration,
      persist: accessibleNavigation,
      action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    ),
  );
}
