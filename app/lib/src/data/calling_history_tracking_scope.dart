import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The four performance-tracking toggles as live notifiers, plus the global
/// "Require mark-performed" notifier that the second toggle follows until the
/// caller sets it.
///
/// [recencyRequirePerformed] holds `null` while the caller has not chosen: no
/// stored value means follow, and a stored value wins (so turning the toggle
/// off while the global setting is on really means off).
class CallingHistoryTrackingSettings {
  const CallingHistoryTrackingSettings({
    required this.requirePerformedForHistory,
    required this.recencyRequireEventDate,
    required this.recencyRequirePerformed,
    required this.orderIgnoreUndated,
    required this.orderIgnoreUnperformed,
  });

  final ValueListenable<bool> requirePerformedForHistory;
  final ValueNotifier<bool> recencyRequireEventDate;
  final ValueNotifier<bool?> recencyRequirePerformed;
  final ValueNotifier<bool> orderIgnoreUndated;
  final ValueNotifier<bool> orderIgnoreUnperformed;

  /// Fires when any input to [resolve] changes.
  Listenable get listenable => Listenable.merge([
    requirePerformedForHistory,
    recencyRequireEventDate,
    recencyRequirePerformed,
    orderIgnoreUndated,
    orderIgnoreUnperformed,
  ]);

  /// The values the repositories take.
  CallingHistoryTracking resolve() => CallingHistoryTracking(
    recencyRequireEventDate: recencyRequireEventDate.value,
    recencyRequirePerformed:
        recencyRequirePerformed.value ?? requirePerformedForHistory.value,
    orderIgnoreUndated: orderIgnoreUndated.value,
    orderIgnoreUnperformed: orderIgnoreUnperformed.value,
  );
}

/// Exposes [CallingHistoryTrackingSettings] to the widget tree. Descendants that
/// call [CallingHistoryTrackingScope.of] rebuild when any toggle changes, or
/// when the global "Require mark-performed" setting changes while the second
/// toggle is following it.
class CallingHistoryTrackingScope extends InheritedNotifier<Listenable> {
  CallingHistoryTrackingScope({
    super.key,
    required this.settings,
    required super.child,
  }) : super(notifier: settings.listenable);

  final CallingHistoryTrackingSettings settings;

  /// The resolved toggles. Falls back to the shipped defaults when no scope is
  /// above, so a test that does not wire it sees the default behaviour.
  static CallingHistoryTracking of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CallingHistoryTrackingScope>()
          ?.settings
          .resolve() ??
      CallingHistoryTracking.defaults;

  /// The notifiers, for the settings screen to change. Registers no rebuild
  /// dependency.
  static CallingHistoryTrackingSettings settingsOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<CallingHistoryTrackingScope>();
    if (scope == null) {
      throw FlutterError(
        'CallingHistoryTrackingScope.settingsOf() called with a context that '
        'has no CallingHistoryTrackingScope ancestor.',
      );
    }
    return scope.settings;
  }
}
