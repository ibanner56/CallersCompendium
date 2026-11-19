import 'package:flutter/material.dart';

/// Exposes the app shell's programs-only search to the Programs list so it can
/// show a one-tap search action in its app bar.
///
/// It is provided **only in the narrow (phone) layout**, below the width at
/// which the navigation rail appears. In the wide layout search lives in the
/// rail, so no scope is inserted and [of] returns `null`, and the Programs list
/// omits its app-bar search rather than duplicate the rail's.
///
/// The Collection takes nothing from this scope: its own search field is its
/// search on every width.
///
/// Kept in its own file (rather than in `app_shell.dart`) so the list screens
/// can depend on it without importing the shell, avoiding a circular import
/// chain (`app_shell.dart → programs_shell.dart → programs_list_screen.dart`).
class AppShellSearchScope extends InheritedWidget {
  const AppShellSearchScope({
    required this.searchPrograms,
    required super.child,
    super.key,
  });

  /// Opens the search palette listing programs only.
  final Future<void> Function() searchPrograms;

  /// Returns the nearest scope, or `null` when search is not surfaced in the
  /// app bar (i.e. the wide layout, where the rail owns search).
  static AppShellSearchScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellSearchScope>();

  @override
  bool updateShouldNotify(AppShellSearchScope oldWidget) =>
      searchPrograms != oldWidget.searchPrograms;
}
