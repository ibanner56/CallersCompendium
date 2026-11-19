import 'package:flutter/widgets.dart';

import 'dialect_library_controller.dart';

/// Exposes every dance form's dialect library ([DialectLibraries]) to the
/// widget tree. Descendants that call [DialectLibraryScope.of] rebuild when
/// any library notifies (a dialect is added, edited, renamed, deleted, or a
/// form's active one changes); use [DialectLibraryScope.controllerOf] to
/// *mutate* without a rebuild dependency. Pick a form's library with
/// [DialectLibraries.forForm].
///
/// Mirrors [CustomThemesScope]/`ActiveDialectScope` so the dialect library
/// slots into the same plain-InheritedWidget approach the rest of the app uses.
class DialectLibraryScope extends InheritedNotifier<DialectLibraries> {
  const DialectLibraryScope({
    super.key,
    required DialectLibraries libraries,
    required super.child,
  }) : super(notifier: libraries);

  /// The libraries, registering a rebuild dependency.
  static DialectLibraries of(BuildContext context) {
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
  static DialectLibraries? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DialectLibraryScope>()
      ?.notifier;

  /// The libraries for read-and-mutate use, without a rebuild dependency.
  static DialectLibraries controllerOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<DialectLibraryScope>();
    if (scope == null) {
      throw FlutterError(
        'DialectLibraryScope.controllerOf() called with a context that has no '
        'DialectLibraryScope ancestor.',
      );
    }
    return scope.notifier!;
  }

  /// Like [controllerOf], but returns `null` instead of throwing when there is
  /// no [DialectLibraryScope] ancestor, and — unlike [maybeOf] — does **not**
  /// register a rebuild dependency. Use when only a one-off snapshot of the
  /// library is needed (e.g. computing a value inside an event handler).
  static DialectLibraries? maybeControllerOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DialectLibraryScope>()?.notifier;
}
