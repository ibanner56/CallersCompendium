import 'package:flutter/widgets.dart';

/// Persisted-settings key for the Experimental **Weekends and series**
/// toggle (#2349). Stored as a `bool`; unset means off (the default).
const String kWeekendsAndSeriesEnabledKey = 'weekends_and_series_enabled';

/// Exposes the Weekends and series toggle as a live [ValueNotifier]. While it
/// is `true`, the Programs list's ⋮ menu offers **Select programs**, whose
/// selection bar opens the combined view. While it is `false` (the default)
/// neither appears.
class WeekendsAndSeriesScope extends InheritedNotifier<ValueNotifier<bool>> {
  const WeekendsAndSeriesScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether Weekends and series is on. Registers a rebuild dependency.
  /// `false` with no ancestor: the off-by-default product behaviour.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WeekendsAndSeriesScope>()
          ?.notifier
          ?.value ??
      false;

  /// The notifier, to change the setting. Does not register a dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<WeekendsAndSeriesScope>();
    if (scope == null) {
      throw FlutterError(
        'WeekendsAndSeriesScope.notifierOf() called with a context that has '
        'no WeekendsAndSeriesScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
