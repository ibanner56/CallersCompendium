import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

import '../diagnostics/error_log.dart';
import 'show_custom_figures_scope.dart';

/// The user's own figures (#1023), kept current from their glossary: what
/// renders a use of one live wherever a dance is shown.
///
/// Not gated on the Custom Figures setting: turning it off hides the figures
/// in the Glossary and the editor, but a dance that uses one still shows it
/// (maintainer decision 9).
class UserFiguresController extends ChangeNotifier {
  UserFiguresController(this._glossary);

  final UserGlossaryRepository _glossary;
  StreamSubscription<List<UserGlossaryEntry>>? _subscription;
  UserFigureCatalog _catalog = UserFigureCatalog.empty;

  /// The live figures; empty until [start] and the glossary's first read.
  UserFigureCatalog get catalog => _catalog;

  /// Starts watching the glossary; a second call does nothing. Not done in
  /// the constructor: watching opens the database, which the app's startup
  /// leaves to its data-safety preflight and migration, so it calls this
  /// after them. It does not wait for the first read, so startup never waits
  /// on it; until then a use shows its stored line. A failed read is logged
  /// and leaves the figures as they were.
  Future<void> start() async {
    _subscription ??= _glossary.watchAll().listen(
      (entries) {
        _catalog = UserFigureCatalog.fromEntries(entries);
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) =>
          logCaughtError(error, stackTrace, source: 'user_figures.watch'),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

/// Exposes the [UserFiguresController] to the widget tree (#1023).
class UserFiguresScope extends InheritedNotifier<UserFiguresController> {
  const UserFiguresScope({
    super.key,
    required UserFiguresController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The user's figures, registering a rebuild dependency; empty outside a
  /// scoped tree, where a use shows its stored line.
  static UserFigureCatalog catalogOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<UserFiguresScope>()
          ?.notifier
          ?.catalog ??
      UserFigureCatalog.empty;

  /// The user's figures while Custom Figures is shown ([customFiguresShown]),
  /// else none: for a surface that lists the figures themselves, such as the
  /// program matrix's columns, rather than rendering a dance's lines (which
  /// read the same with it off, maintainer decision 9 on #1023). Registers a
  /// rebuild dependency on the catalog and both toggles.
  static UserFigureCatalog shownCatalogOf(BuildContext context) =>
      customFiguresShown(context)
      ? catalogOf(context)
      : UserFigureCatalog.empty;

  /// A renderer that shows a use of one of the user's figures live, for every
  /// place that shows a dance's figures. Registers a rebuild dependency.
  static FigureRenderer rendererOf(BuildContext context) =>
      FigureRenderer(contraTaxonomy, userFigures: catalogOf(context));
}
