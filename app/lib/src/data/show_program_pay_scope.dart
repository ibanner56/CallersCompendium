import 'package:flutter/widgets.dart';

export 'settings_keys.dart' show kShowProgramPayKey;

/// Exposes the "Show pay" Programs setting ([kShowProgramPayKey], issue #2355)
/// as a live [ValueNotifier] to the widget tree.
///
/// When `true` (the default), the program editor's More details carries the
/// Pay amount and currency, and the program summary shows a pay line. When
/// `false`, both are hidden. Hiding is display-only: a program's stored pay is
/// never cleared or changed by it, and a save from the editor while it is off
/// keeps the stored amount and currency. Descendants that call
/// [ShowProgramPayScope.of] rebuild automatically when the setting changes.
///
/// Use [ShowProgramPayScope.notifierOf] when you need to *change* the setting
/// (e.g. from the settings screen).
class ShowProgramPayScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ShowProgramPayScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether pay is shown. Registers a rebuild dependency so the caller
  /// rebuilds whenever the setting changes.
  ///
  /// Returns `true` (the on-by-default behaviour) when there is no
  /// [ShowProgramPayScope] ancestor, so callers — and tests that don't wire the
  /// scope — get the product default.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShowProgramPayScope>();
    return scope?.notifier?.value ?? true;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ShowProgramPayScope>();
    if (scope == null) {
      throw FlutterError(
        'ShowProgramPayScope.notifierOf() called with a context that has no '
        'ShowProgramPayScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
