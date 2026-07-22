import 'package:flutter/widgets.dart';

import 'regional_formats.dart';

/// Exposes the first-day-of-week preference (ROADMAP G.8) as a live
/// [ValueNotifier] to the widget tree, mirroring [DateFormatScope].
///
/// Descendants that call [FirstDayOfWeekScope.of] rebuild automatically when
/// the setting changes. Use [FirstDayOfWeekScope.notifierOf] when you need to
/// *change* it (e.g. from the Settings screen).
///
/// NOTE: this preference only affects date surfaces the app draws itself;
/// Flutter's [showDatePicker] derives its first day of week from the locale and
/// can't be overridden per-call. See `docs/dev/localization.md`.
class FirstDayOfWeekScope
    extends InheritedNotifier<ValueNotifier<FirstDayOfWeekPref>> {
  const FirstDayOfWeekScope({
    super.key,
    required ValueNotifier<FirstDayOfWeekPref> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The active first-day-of-week preference. Registers a rebuild dependency so
  /// the caller rebuilds whenever the setting changes.
  ///
  /// Returns [FirstDayOfWeekPref.system] (the default) when there is no
  /// [FirstDayOfWeekScope] ancestor, so callers — and tests that don't wire the
  /// scope — degrade gracefully to the platform default.
  static FirstDayOfWeekPref of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<FirstDayOfWeekScope>();
    return scope?.notifier?.value ?? FirstDayOfWeekPref.system;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<FirstDayOfWeekPref> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<FirstDayOfWeekScope>();
    if (scope == null) {
      throw FlutterError(
        'FirstDayOfWeekScope.notifierOf() called with a context that has no '
        'FirstDayOfWeekScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
