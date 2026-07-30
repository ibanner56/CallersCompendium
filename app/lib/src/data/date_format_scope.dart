import 'package:flutter/widgets.dart';

import 'regional_formats.dart';

/// Exposes the program-event-date format preference (ROADMAP G.8) as a live
/// [ValueNotifier] to the widget tree.
///
/// The value is a [DateFormatSetting] (preference plus, for the custom variant,
/// the raw user-entered pattern — issue #584), so a custom pattern reaches every
/// render/parse call site through this single scope.
///
/// Descendants that call [DateFormatScope.of] rebuild automatically when the
/// setting changes, so on-screen event dates re-render live. Use
/// [DateFormatScope.notifierOf] when you need to *change* the setting (e.g. from
/// the settings screen).
class DateFormatScope
    extends InheritedNotifier<ValueNotifier<DateFormatSetting>> {
  const DateFormatScope({
    super.key,
    required ValueNotifier<DateFormatSetting> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The active date-format setting. Registers a rebuild dependency so the
  /// caller rebuilds whenever the setting changes.
  ///
  /// Returns [DateFormatSetting.system] (the default) when there is no
  /// [DateFormatScope] ancestor, so callers — and tests that don't wire the
  /// scope — get the platform-locale medium date.
  static DateFormatSetting of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DateFormatScope>();
    return scope?.notifier?.value ?? DateFormatSetting.system;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<DateFormatSetting> notifierOf(BuildContext context) {
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
