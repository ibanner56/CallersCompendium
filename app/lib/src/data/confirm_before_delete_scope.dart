import 'package:flutter/widgets.dart';

/// Persisted-settings key for the "Confirm before delete" accessibility toggle
/// (ROADMAP G.7). Stored as a `bool`; unset means off.
const String kConfirmBeforeDeleteKey = 'confirm_before_delete';

/// Exposes the "Confirm before delete" accessibility setting (ROADMAP G.7) as a
/// live [ValueNotifier] to the widget tree.
///
/// When `true`, delete actions show an explicit confirmation dialog before
/// performing the (still-undoable) soft-delete. When `false` (the default) the
/// existing immediate soft-delete + Undo-snackbar behavior is preserved — the
/// accessibility baseline prefers undo/soft-delete over confirmation dialogs,
/// so this is strictly opt-in. Descendants that call
/// [ConfirmBeforeDeleteScope.of] rebuild automatically when the setting changes.
///
/// Use [ConfirmBeforeDeleteScope.notifierOf] when you need to *change* the
/// setting (e.g. from the settings screen).
class ConfirmBeforeDeleteScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ConfirmBeforeDeleteScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether a confirmation dialog is shown before deleting. Registers a
  /// rebuild dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [ConfirmBeforeDeleteScope] ancestor, so callers — and tests that don't
  /// wire the scope — get the product default of immediate soft-delete + Undo.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ConfirmBeforeDeleteScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<ConfirmBeforeDeleteScope>();
    if (scope == null) {
      throw FlutterError(
        'ConfirmBeforeDeleteScope.notifierOf() called with a context that has '
        'no ConfirmBeforeDeleteScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
