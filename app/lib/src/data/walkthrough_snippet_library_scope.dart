import 'package:flutter/widgets.dart';

import 'walkthrough_snippet_library_controller.dart';

/// Exposes the [WalkthroughSnippetLibraryController] to the widget tree (#411).
/// Descendants that call [WalkthroughSnippetLibraryScope.of] rebuild when the
/// controller notifies (a snippet is learned, edited, or removed); use
/// [WalkthroughSnippetLibraryScope.controllerOf] to *mutate* without a rebuild
/// dependency.
///
/// Mirrors `ShorthandMappingsScope`/`DialectLibraryScope` so the snippet library
/// slots into the same plain-InheritedWidget approach the rest of the app uses.
class WalkthroughSnippetLibraryScope
    extends InheritedNotifier<WalkthroughSnippetLibraryController> {
  const WalkthroughSnippetLibraryScope({
    super.key,
    required WalkthroughSnippetLibraryController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, registering a rebuild dependency.
  static WalkthroughSnippetLibraryController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<WalkthroughSnippetLibraryScope>();
    if (scope == null) {
      throw FlutterError(
        'WalkthroughSnippetLibraryScope.of() called with a context that has no '
        'WalkthroughSnippetLibraryScope ancestor.',
      );
    }
    return scope.notifier!;
  }

  /// Like [of], but returns `null` instead of throwing when there is no
  /// [WalkthroughSnippetLibraryScope] ancestor. Registers a rebuild dependency
  /// when one is present. Used by optional consumers (e.g. the figure editor)
  /// that should simply see "no snippets" outside a scoped tree.
  static WalkthroughSnippetLibraryController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WalkthroughSnippetLibraryScope>()
          ?.notifier;

  /// The controller for read-and-mutate use, without a rebuild dependency.
  static WalkthroughSnippetLibraryController controllerOf(
    BuildContext context,
  ) {
    final scope = context
        .getInheritedWidgetOfExactType<WalkthroughSnippetLibraryScope>();
    if (scope == null) {
      throw FlutterError(
        'WalkthroughSnippetLibraryScope.controllerOf() called with a context '
        'that has no WalkthroughSnippetLibraryScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
