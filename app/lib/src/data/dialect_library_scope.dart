import 'package:flutter/widgets.dart';

import 'dialect_library_controller.dart';

/// Exposes the [DialectLibraryController] to the widget tree. Descendants that
/// call [DialectLibraryScope.of] rebuild when the controller notifies (a
/// dialect is added, edited, renamed, deleted, or the active one changes); use
/// [DialectLibraryScope.controllerOf] to *mutate* without a rebuild dependency.
///
/// Mirrors [CustomThemesScope]/`ActiveDialectScope` so the dialect library
/// slots into the same plain-InheritedWidget approach the rest of the app uses.
class DialectLibraryScope extends InheritedNotifier<DialectLibraryController> {
  const DialectLibraryScope({
    super.key,
    required DialectLibraryController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, registering a rebuild dependency.
  static DialectLibraryController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DialectLibraryScope>();
    if (scope == null) {
      throw FlutterError(
        'DialectLibraryScope.of() called with a context that has no '
        'DialectLibraryScope ancestor.',
      );
    }
    return scope.notifier!;
  }

  /// The controller for read-and-mutate use, without a rebuild dependency.
  static DialectLibraryController controllerOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<DialectLibraryScope>();
    if (scope == null) {
      throw FlutterError(
        'DialectLibraryScope.controllerOf() called with a context that has no '
        'DialectLibraryScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
