import 'package:flutter/widgets.dart';

/// Persisted-settings key for the "Reduce motion" accessibility toggle
/// (ROADMAP G.7). The value is tri-state (issue #447, WCAG 2.3.3):
///
/// * **absent** — unset; follow the OS-level Reduce Motion preference
///   (`MediaQuery.disableAnimations`).
/// * **`true` / `false`** — an explicit in-app override that wins over the OS
///   value in either direction.
const String kReduceMotionKey = 'reduce_motion';

/// Exposes the effective "Reduce motion" accessibility setting (ROADMAP G.7,
/// issue #447) to the widget tree.
///
/// The in-app setting is *tri-state*, carried by a `ValueNotifier<bool?>`:
///
/// * **`null`** — unset. The scope follows the OS-level Reduce Motion
///   preference (`MediaQuery.disableAnimations`). This is the default so a
///   user who enabled Reduce Motion at the OS level gets reduced motion
///   immediately, without hunting for the in-app switch (WCAG 2.3.3 Animation
///   from Interactions).
/// * **`true` / `false`** — an explicit in-app override that wins over the OS
///   value in either direction (force-reduce or force-full motion).
///
/// [of] resolves this tri-state to the single effective `bool` that
/// animation-gated widgets consume, and registers rebuild dependencies on both
/// this scope *and* the OS `disableAnimations` value, so dependents rebuild
/// live when either the in-app override or the OS preference changes at
/// runtime.
///
/// Use [ReduceMotionScope.notifierOf] when you need to *change* the setting
/// (e.g. from the settings screen).
class ReduceMotionScope extends InheritedNotifier<ValueNotifier<bool?>> {
  const ReduceMotionScope({
    super.key,
    required ValueNotifier<bool?> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether non-essential motion should be reduced, resolving the tri-state
  /// override against the OS preference: an explicit in-app override (`true`
  /// or `false`) wins; otherwise the OS `MediaQuery.disableAnimations` value
  /// applies.
  ///
  /// Registers a rebuild dependency on both the scope and the OS
  /// `disableAnimations` aspect (via [MediaQuery.maybeDisableAnimationsOf]), so
  /// the caller rebuilds whenever the in-app override *or* the OS preference
  /// changes. The OS dependency is registered even while an override is active
  /// so that clearing the override later still reflects the live OS value.
  ///
  /// Returns `false` (full motion) when there is neither an in-app override nor
  /// a [MediaQuery] ancestor, so callers — and tests that don't wire either —
  /// get the product default of full motion.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ReduceMotionScope>();
    final osReduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return scope?.notifier?.value ?? osReduceMotion;
  }

  /// The explicit in-app override (`true` or `false`), or `null` when the
  /// setting is unset and the OS preference is being followed. Registers a
  /// rebuild dependency on the scope but, unlike [of], does *not* consult the
  /// OS value.
  static bool? overrideOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ReduceMotionScope>();
    return scope?.notifier?.value;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool?> notifierOf(BuildContext context) {
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
