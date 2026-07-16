import 'package:flutter/material.dart';

/// Exposes the app shell's global-search callback to nested screens so they can
/// surface a 1-tap search affordance in their app bars.
///
/// It is intentionally provided **only in the narrow (phone) layout**, where
/// the bottom-right FAB slot is reserved for each screen's "New" FAB.extended.
/// In the wide layout search lives in the [NavigationRail], so no scope is
/// inserted and [of] returns `null` — nested list screens then omit their
/// in-app-bar search action to avoid duplicating the rail affordance.
///
/// Kept in its own file (rather than in `app_shell.dart`) so the list screens
/// can depend on it without importing the shell, avoiding a circular import
/// chain (`app_shell.dart → collection_shell.dart → dance_list_screen.dart`).
class AppShellSearchScope extends InheritedWidget {
  const AppShellSearchScope({
    required this.openSearch,
    required super.child,
    super.key,
  });

  /// Opens the global command palette. Mirrors the Ctrl/Cmd-K shortcut and the
  /// wide layout's rail search button.
  final Future<void> Function() openSearch;

  /// Returns the nearest scope, or `null` when search is not surfaced in the
  /// app bar (i.e. the wide layout, where the rail owns search).
  static AppShellSearchScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellSearchScope>();

  @override
  bool updateShouldNotify(AppShellSearchScope oldWidget) =>
      openSearch != oldWidget.openSearch;
}
