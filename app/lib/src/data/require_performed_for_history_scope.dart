import 'package:flutter/widgets.dart';

/// Exposes the "Require mark-performed for calling history" General setting
/// (ROADMAP G.2) as a live [ValueNotifier] to the widget tree.
///
/// When `true`, a dance's calling-history section only lists programs whose
/// slot for that dance was marked performed (`ProgramSlot.performedAt` set);
/// when `false` (the default) a program appears as soon as it contains the
/// dance. Descendants that call [RequirePerformedForHistoryScope.of] rebuild
/// automatically when the setting changes (live update).
///
/// Use [RequirePerformedForHistoryScope.notifierOf] when you need to *change*
/// the setting (e.g. from the settings screen).
class RequirePerformedForHistoryScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const RequirePerformedForHistoryScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether calling history is restricted to performed slots. Registers a
  /// rebuild dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [RequirePerformedForHistoryScope] ancestor, so callers — and tests that
  /// don't wire the scope — safely fall back to showing all programs that
  /// contain the dance.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RequirePerformedForHistoryScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<RequirePerformedForHistoryScope>();
    if (scope == null) {
      throw FlutterError(
        'RequirePerformedForHistoryScope.notifierOf() called with a context '
        'that has no RequirePerformedForHistoryScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
