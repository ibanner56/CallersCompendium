import 'package:flutter/widgets.dart';

import 'custom_themes_controller.dart';

/// Exposes the [CustomThemesController] to the widget tree. Descendants that
/// call [CustomThemesScope.of] rebuild when the controller notifies (a theme is
/// added, edited, deleted, or the active one changes); use
/// [CustomThemesScope.controllerOf] to *mutate* without a rebuild dependency.
///
/// Mirrors [AppThemeScope]/[ActiveDialectScope] so custom themes slot into the
/// same plain-InheritedWidget approach the rest of the app uses.
class CustomThemesScope extends InheritedNotifier<CustomThemesController> {
  const CustomThemesScope({
    super.key,
    required CustomThemesController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, registering a rebuild dependency.
  static CustomThemesController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CustomThemesScope>();
    if (scope == null) {
      throw FlutterError(
        'CustomThemesScope.of() called with a context that has no '
        'CustomThemesScope ancestor.',
      );
    }
    return scope.notifier!;
  }

  /// The controller for read-and-mutate use, without a rebuild dependency.
  static CustomThemesController controllerOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<CustomThemesScope>();
    if (scope == null) {
      throw FlutterError(
        'CustomThemesScope.controllerOf() called with a context that has no '
        'CustomThemesScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
