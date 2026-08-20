import 'package:flutter/widgets.dart';

/// Exposes the opt-in program-editor auto-commit preference as a live notifier.
///
/// When enabled, a valid program-editor draft is committed after the existing
/// debounce rather than waiting for the explicit Save action. The default is
/// `false`, so descendants and tests without this scope retain explicit-save
/// behavior.
class ProgramAutoCommitScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ProgramAutoCommitScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether valid program-editor changes should be committed automatically.
  static bool of(BuildContext context) {
    return maybeOf(context) ?? false;
  }

  /// Returns the live value, or `null` when a standalone screen has no scope.
  static bool? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ProgramAutoCommitScope>();
    return scope?.notifier?.value;
  }

  /// Returns the notifier for the settings screen's live mutation.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<ProgramAutoCommitScope>();
    if (scope == null) {
      throw FlutterError(
        'ProgramAutoCommitScope.notifierOf() called with a context that '
        'has no ProgramAutoCommitScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
