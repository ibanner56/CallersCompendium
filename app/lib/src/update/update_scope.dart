import 'package:flutter/widgets.dart';

import 'update_controller.dart';

/// Exposes the [UpdateController] to the widget tree. Descendants that call
/// [UpdateScope.of] rebuild when the controller notifies (a check completes, a
/// pref changes, or the banner is dismissed); use [UpdateScope.controllerOf] to
/// *mutate* without a rebuild dependency.
///
/// Mirrors [CustomThemesScope]/[AppThemeScope] so the update state slots into
/// the same plain-InheritedNotifier approach the rest of the app uses.
class UpdateScope extends InheritedNotifier<UpdateController> {
  const UpdateScope({
    super.key,
    required UpdateController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, registering a rebuild dependency.
  static UpdateController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UpdateScope>();
    if (scope == null) {
      throw FlutterError(
        'UpdateScope.of() called with a context that has no UpdateScope '
        'ancestor.',
      );
    }
    return scope.notifier!;
  }

  /// The controller for read-and-mutate use, without a rebuild dependency.
  static UpdateController controllerOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<UpdateScope>();
    if (scope == null) {
      throw FlutterError(
        'UpdateScope.controllerOf() called with a context that has no '
        'UpdateScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
