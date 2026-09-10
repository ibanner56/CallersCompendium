import 'package:flutter/widgets.dart';

/// Preference controlling how many repeatedly used venues appear in a dance's
/// calling-history summary.
const int kVenueCallCountDefault = 3;
const int kVenueCallCountMax = 10;

/// Resolves an untrusted stored value to the bounded live preference.
int venueCallCountFromStored(Object? stored) {
  if (stored is int && stored >= 0 && stored <= kVenueCallCountMax) {
    return stored;
  }
  return kVenueCallCountDefault;
}

/// Exposes the calling-history venue-summary limit as a live preference.
class VenueCallCountScope extends InheritedNotifier<ValueNotifier<int>> {
  const VenueCallCountScope({
    super.key,
    required ValueNotifier<int> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static int of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<VenueCallCountScope>();
    return scope?.notifier?.value ?? kVenueCallCountDefault;
  }

  static ValueNotifier<int> notifierOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<VenueCallCountScope>();
    if (scope == null) {
      throw FlutterError(
        'VenueCallCountScope.notifierOf() called with a context that has no '
        'VenueCallCountScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
