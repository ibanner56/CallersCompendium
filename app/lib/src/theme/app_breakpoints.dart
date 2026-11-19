import 'package:flutter/widgets.dart';

/// The app's layout breakpoints, in logical pixels of **window** width.
///
/// One set, in one place, so every screen changes layout at the same widths:
///
/// | Window width   | Layout                                            |
/// | -------------- | ------------------------------------------------- |
/// | below [rail]   | bottom navigation bar, one pane                   |
/// | [rail]–[split] | navigation rail, one pane (Settings included)     |
/// | from [split]   | navigation rail, list beside detail               |
///
/// An 11-inch iPad in portrait (820 pt) falls in the middle band: it gets the
/// rail, and each destination shows one pane.
///
/// [compact] is a separate, smaller cut: below it an app bar folds its
/// secondary actions into a "⋮" menu, and a few dense widgets (the program
/// matrix, the slot list's row actions) switch to their phone form. Each of
/// those measures what it measured before: some the space they are given,
/// some (the editors' app bars, the slot list, the sync conflict sheet) the
/// window. [shortHeight] is the one
/// height cut.
///
/// `docs/design/ux.md` ("Responsive breakpoints") states the same bands; keep
/// the two in step.
abstract final class AppBreakpoints {
  /// Window width at or above which the navigation rail replaces the bottom
  /// navigation bar.
  static const double rail = 720;

  /// Window width at or above which a destination shows its list beside its
  /// detail (Collection, Programs, Glossary), Settings shows its section
  /// sidebar beside the open section, and the program editor shows its dance
  /// picker beside the slots.
  static const double split = 900;

  /// Width below which app-bar actions fold into a "⋮" menu and dense
  /// widgets switch to their phone form. Material 3's compact
  /// window-size-class boundary.
  static const double compact = 600;

  /// Window *height* below which the window counts as short: a phone in
  /// landscape (about 390 to 430 px tall). There a screen's labelled
  /// floating button folds to its icon, so it does not cover the trailing
  /// buttons of the few list rows that fit. 480 sits above the tallest
  /// landscape phone and below the shortest portrait tablet; the same height
  /// already sends the autocomplete fields to their sheet form.
  static const double shortHeight = 480;

  /// Whether the window is short ([shortHeight]).
  static bool isShort(BuildContext context) =>
      MediaQuery.sizeOf(context).height < shortHeight;

  /// Whether a destination shows list beside detail.
  ///
  /// Measured on the window, not on the pane the destination is given, so
  /// the rail's own width does not move the cut: a destination beside the
  /// rail splits at the same window width as one shown on its own. Inside
  /// the app shell the window width comes from [AppWindowWidth]; a screen
  /// shown on its own (a pushed route, or a test) passes its [ownWidth],
  /// which is then the window's.
  static bool showsSplit(BuildContext context, double ownWidth) =>
      (AppWindowWidth.maybeOf(context) ?? ownWidth) >= split;
}

/// The window width, as the app shell measures it, for the destinations it
/// hosts beside the navigation rail ([AppBreakpoints.showsSplit]).
///
/// The shell's own layout constraints are used rather than [MediaQuery]'s
/// size, so the shell and its destinations agree on one number however the
/// window is sized.
class AppWindowWidth extends InheritedWidget {
  const AppWindowWidth({required this.width, required super.child, super.key});

  /// The window width in logical pixels.
  final double width;

  /// The nearest window width, or `null` outside the app shell.
  static double? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppWindowWidth>()?.width;

  @override
  bool updateShouldNotify(AppWindowWidth oldWidget) => width != oldWidget.width;
}
