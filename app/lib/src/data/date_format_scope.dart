import 'package:flutter/widgets.dart';

import 'regional_formats.dart';

/// Exposes the program-event-date format preference (ROADMAP G.8) as a live
/// [ValueNotifier] to the widget tree.
///
/// Descendants that call [DateFormatScope.of] rebuild automatically when the
/// setting changes, so on-screen event dates re-render live. Use
/// [DateFormatScope.notifierOf] when you need to *change* the setting (e.g. from
/// the settings screen).
class DateFormatScope extends InheritedNotifier<ValueNotifier<DateFormatPref>> {
  const DateFormatScope({
    super.key,
    required ValueNotifier<DateFormatPref> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The active date-format preference. Registers a rebuild dependency so the
  /// caller rebuilds whenever the setting changes.
  ///
  /// Returns [DateFormatPref.system] (the default) when there is no
  /// [DateFormatScope] ancestor, so callers — and tests that don't wire the
  /// scope — get the platform-locale medium date.
  static DateFormatPref of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DateFormatScope>();
    return scope?.notifier?.value ?? DateFormatPref.system;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<DateFormatPref> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<DateFormatScope>();
    if (scope == null) {
      throw FlutterError(
        'DateFormatScope.notifierOf() called with a context that has no '
        'DateFormatScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
