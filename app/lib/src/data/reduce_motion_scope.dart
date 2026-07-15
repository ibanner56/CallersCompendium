import 'package:flutter/widgets.dart';

/// Persisted-settings key for the "Reduce motion" accessibility toggle
/// (ROADMAP G.7). Stored as a `bool`; unset means off.
const String kReduceMotionKey = 'reduce_motion';

/// Exposes the "Reduce motion" accessibility setting (ROADMAP G.7) as a live
/// [ValueNotifier] to the widget tree.
///
/// When `true`, the app dampens or skips its own non-essential animations
/// (e.g. animated scroll-into-view jumps run instantly). When `false` (the
/// default) animations play as usual. Descendants that call
/// [ReduceMotionScope.of] rebuild automatically when the setting changes (live
/// update).
///
/// Use [ReduceMotionScope.notifierOf] when you need to *change* the setting
/// (e.g. from the settings screen).
class ReduceMotionScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ReduceMotionScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether non-essential motion should be reduced. Registers a rebuild
  /// dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [ReduceMotionScope] ancestor, so callers — and tests that don't wire the
  /// scope — get the product default of full motion.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ReduceMotionScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ReduceMotionScope>();
    if (scope == null) {
      throw FlutterError(
        'ReduceMotionScope.notifierOf() called with a context that has no '
        'ReduceMotionScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
