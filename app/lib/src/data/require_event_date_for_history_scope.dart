import 'package:flutter/widgets.dart';

/// Exposes the "Require an event date" calling-history setting as a live
/// [ValueNotifier] to the widget tree, the same way
/// `RequirePerformedForHistoryScope` exposes "Require mark performed".
///
/// When `true`, a program with no event date counts nowhere calling history is
/// read: the "called ×N" count, the Called filter, the dance's history rows,
/// the Last-called sort, venue counts and half stats. When `false` (the
/// default) a program counts whether or not it is dated. Descendants that call
/// [RequireEventDateForHistoryScope.of] rebuild automatically when the setting
/// changes (live update).
///
/// Use [RequireEventDateForHistoryScope.notifierOf] when you need to *change*
/// the setting (e.g. from the settings screen).
class RequireEventDateForHistoryScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const RequireEventDateForHistoryScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether calling history is restricted to programs with an event date.
  /// Registers a rebuild dependency so the caller rebuilds whenever the
  /// setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [RequireEventDateForHistoryScope] ancestor, so callers — and tests that
  /// don't wire the scope — count undated programs.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RequireEventDateForHistoryScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<RequireEventDateForHistoryScope>();
    if (scope == null) {
      throw FlutterError(
        'RequireEventDateForHistoryScope.notifierOf() called with a context '
        'that has no RequireEventDateForHistoryScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
