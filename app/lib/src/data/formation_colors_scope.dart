import 'package:flutter/widgets.dart';

import 'formation_colors_controller.dart';

/// Exposes the [FormationColorsController] to the widget tree (issue #367).
/// Descendants that call [FormationColorsScope.of] rebuild when the controller
/// notifies (an override is set or cleared); use
/// [FormationColorsScope.controllerOf] to *mutate* without a rebuild
/// dependency.
///
/// Mirrors [CustomThemesScope] so per-formation colors slot into the same
/// plain-InheritedNotifier approach the rest of the app uses.
class FormationColorsScope
    extends InheritedNotifier<FormationColorsController> {
  const FormationColorsScope({
    super.key,
    required FormationColorsController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, registering a rebuild dependency. Returns `null` when
  /// there is no [FormationColorsScope] ancestor, so callers — and tests that
  /// don't wire the scope — safely fall back to "no overrides".
  static FormationColorsController? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FormationColorsScope>()
        ?.notifier;
  }

  /// The controller for read-and-mutate use, without a rebuild dependency.
  static FormationColorsController controllerOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<FormationColorsScope>();
    if (scope == null) {
      throw FlutterError(
        'FormationColorsScope.controllerOf() called with a context that has '
        'no FormationColorsScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
