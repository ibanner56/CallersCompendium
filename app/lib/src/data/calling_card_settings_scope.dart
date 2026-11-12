import 'package:flutter/widgets.dart';

import '../export/calling_card_layout.dart';

export '../export/calling_card_layout.dart' show CallingCardSettings;

/// Persisted-settings key for Settings › Experimental › Calling cards: one
/// JSON object holding whether calling cards are offered, the card size, and
/// the layout (see [CallingCardSettings.toJson]). Unset means off, 3 × 5
/// inches, and the default layout.
const String kCallingCardSettingsKey = 'calling_card_print';

/// Exposes the calling-card settings as a live [ValueNotifier] to the widget
/// tree: the Export menus read [CallingCardSettings.enabled] to offer the
/// print actions, and the print actions read the size and layout.
///
/// Use [CallingCardSettingsScope.notifierOf] to change the settings.
class CallingCardSettingsScope
    extends InheritedNotifier<ValueNotifier<CallingCardSettings>> {
  const CallingCardSettingsScope({
    super.key,
    required ValueNotifier<CallingCardSettings> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The current settings. Registers a rebuild dependency. Returns the
  /// defaults (calling cards off) when there is no ancestor.
  static CallingCardSettings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CallingCardSettingsScope>();
    return scope?.notifier?.value ?? CallingCardSettings.defaults;
  }

  /// Returns the underlying notifier so callers can change the settings. Does
  /// *not* register a rebuild dependency.
  static ValueNotifier<CallingCardSettings> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<CallingCardSettingsScope>();
    if (scope == null) {
      throw FlutterError(
        'CallingCardSettingsScope.notifierOf() called with a context that has '
        'no CallingCardSettingsScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
