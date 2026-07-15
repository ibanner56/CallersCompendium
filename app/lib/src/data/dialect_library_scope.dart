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

  /// Like [of], but returns `null` instead of throwing when there is no
  /// [DialectLibraryScope] ancestor. Registers a rebuild dependency when one is
  /// present. Used by optional affordances (e.g. the dialect quick-switch) that
  /// should simply not render outside a library-scoped tree.
  static DialectLibraryController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DialectLibraryScope>()
      ?.notifier;

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
