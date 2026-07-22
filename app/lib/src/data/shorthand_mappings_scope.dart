import 'package:flutter/widgets.dart';

import 'shorthand_mappings_controller.dart';

/// Exposes the [ShorthandMappingsController] to the widget tree (issue #420).
/// Descendants that call [ShorthandMappingsScope.of] rebuild when the
/// controller notifies (a mapping is added, edited, or deleted); use
/// [ShorthandMappingsScope.controllerOf] to *mutate* without a rebuild
/// dependency.
///
/// Mirrors `DialectLibraryScope`/`FormationColorsScope` so the shorthand
/// library slots into the same plain-InheritedWidget approach the rest of the
/// app uses.
class ShorthandMappingsScope
    extends InheritedNotifier<ShorthandMappingsController> {
  const ShorthandMappingsScope({
    super.key,
    required ShorthandMappingsController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, registering a rebuild dependency.
  static ShorthandMappingsController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShorthandMappingsScope>();
    if (scope == null) {
      throw FlutterError(
        'ShorthandMappingsScope.of() called with a context that has no '
        'ShorthandMappingsScope ancestor.',
      );
    }
    return scope.notifier!;
  }

  /// Like [of], but returns `null` instead of throwing when there is no
  /// [ShorthandMappingsScope] ancestor. Registers a rebuild dependency when one
  /// is present. Used by optional consumers (e.g. the free-text entry path)
  /// that should simply see "no shorthands" outside a scoped tree.
  static ShorthandMappingsController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ShorthandMappingsScope>()
      ?.notifier;

  /// The controller for read-and-mutate use, without a rebuild dependency.
  static ShorthandMappingsController controllerOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<ShorthandMappingsScope>();
    if (scope == null) {
      throw FlutterError(
        'ShorthandMappingsScope.controllerOf() called with a context that has '
        'no ShorthandMappingsScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
