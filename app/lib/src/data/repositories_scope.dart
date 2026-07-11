import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

/// Makes [CompendiumRepositories] available to descendants without pulling
/// in a state-management package — plain [InheritedWidget], matching this
/// screen's otherwise-vanilla `StatefulWidget` approach.
class RepositoriesScope extends InheritedWidget {
  const RepositoriesScope({
    super.key,
    required this.repositories,
    required super.child,
  });

  final CompendiumRepositories repositories;

  static CompendiumRepositories of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RepositoriesScope>();
    if (scope == null) {
      throw FlutterError(
        'RepositoriesScope.of() was called with a context that does not '
        'contain a RepositoriesScope.\n'
        'No RepositoriesScope ancestor could be found starting from the '
        'context that was passed to RepositoriesScope.of(). This can '
        'happen if the context you use comes from a widget above the '
        'RepositoriesScope.',
      );
    }
    return scope.repositories;
  }

  @override
  bool updateShouldNotify(RepositoriesScope oldWidget) =>
      oldWidget.repositories != repositories;
}
