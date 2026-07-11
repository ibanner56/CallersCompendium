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
    assert(scope != null, 'No RepositoriesScope found in context');
    return scope!.repositories;
  }

  @override
  bool updateShouldNotify(RepositoriesScope oldWidget) =>
      oldWidget.repositories != repositories;
}
