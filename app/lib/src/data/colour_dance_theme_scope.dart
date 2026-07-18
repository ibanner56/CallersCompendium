import 'package:flutter/widgets.dart';

/// Exposes the "colour-named dances tint the theme" easter egg (issue #307) as
/// a live [ValueNotifier] to the widget tree.
///
/// When `true`, a dance whose title contains a recognised colour word has its
/// view (dance detail and Perform) tinted with that colour via a scoped theme
/// override. When `false` (the default) the feature is off — it is strictly
/// opt-in because it deliberately overrides the user's chosen theme.
///
/// Descendants that call [ColourDanceThemeScope.of] rebuild automatically when
/// the setting changes (live update). Use [ColourDanceThemeScope.notifierOf]
/// when you need to *change* the setting (e.g. from the settings screen).
class ColourDanceThemeScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ColourDanceThemeScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether the colour-tint easter egg is enabled. Registers a rebuild
  /// dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [ColourDanceThemeScope] ancestor, so callers — and tests that don't wire
  /// the scope — get the product default of no tint.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ColourDanceThemeScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<ColourDanceThemeScope>();
    if (scope == null) {
      throw FlutterError(
        'ColourDanceThemeScope.notifierOf() called with a context that has no '
        'ColourDanceThemeScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
