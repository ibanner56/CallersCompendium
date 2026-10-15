import 'package:flutter/widgets.dart';

import 'show_glossary_scope.dart';

/// Persisted-settings key for the Experimental "Custom Figures" toggle (#709),
/// nested under "Show Glossary". Stored as a `bool`; unset means off (the
/// default).
const String kShowCustomFiguresKey = 'show_custom_figures';

/// Exposes the "Custom Figures" setting as a live [ValueNotifier] to the
/// widget tree.
///
/// When `true` — and only while "Show Glossary" is on too — the user's own
/// compound figures are listed in the Glossary, can be added and edited
/// there, and are offered in the dance editor. When `false` they are hidden,
/// never deleted: turning it back on shows them again.
///
/// Use [ShowCustomFiguresScope.notifierOf] to change the setting.
class ShowCustomFiguresScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ShowCustomFiguresScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether the setting is on. Registers a rebuild dependency. Returns
  /// `false`, the default, when there is no [ShowCustomFiguresScope]
  /// ancestor.
  ///
  /// This is the setting alone; whether custom figures are shown also needs
  /// "Show Glossary" on, which [customFiguresShown] combines.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShowCustomFiguresScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<ShowCustomFiguresScope>();
    if (scope == null) {
      throw FlutterError(
        'ShowCustomFiguresScope.notifierOf() called with a context that has no '
        'ShowCustomFiguresScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// Whether the user's own compound figures are shown: "Show Glossary" and,
/// nested under it, "Custom Figures" are both on. Registers a rebuild
/// dependency on both.
bool customFiguresShown(BuildContext context) =>
    ShowGlossaryScope.of(context) && ShowCustomFiguresScope.of(context);
