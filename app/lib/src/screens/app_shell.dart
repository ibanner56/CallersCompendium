import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/dance_detail_screen.dart';
import '../screens/program_editor_screen.dart';
import '../widgets/command_palette.dart';
import 'collection_shell.dart';
import 'programs_shell.dart';
import 'settings_screen.dart';

/// Top-level navigation between Collection, Programs, and Settings
/// (`docs/design/ux.md` information architecture).
///
/// - **Narrow (< 900 px):** bottom [NavigationBar].
/// - **Wide (≥ 900 px):** left [NavigationRail].
///
/// All destinations are kept alive in an [IndexedStack] so switching preserves
/// each screen's state (selection, scroll, in-progress edits). Settings is a
/// first-class destination alongside Collection and Programs rather than a
/// pushed route.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// Breakpoint (logical pixels) at which the nav rail replaces the bottom bar.
  static const double railBreakpoint = 900;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations = [
    (
      icon: Icons.auto_stories_outlined,
      selectedIcon: Icons.auto_stories,
      label: 'Collection',
    ),
    (
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
      label: 'Programs',
    ),
    (
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  static const _pages = [CollectionShell(), ProgramsShell(), SettingsScreen()];

  void _onSelect(int index) => setState(() => _index = index);

  /// Opens the global search palette and, if the user picks a result, switches
  /// to the matching section and opens that item's route. Wired to Ctrl/Cmd-K
  /// and the persistent rail search affordance (`ux-modernization.md` §6).
  Future<void> _openSearch() async {
    final result = await showCommandPalette(context);
    if (result == null || !mounted) return;
    final (tabIndex, route) = switch (result.kind) {
      CommandResultKind.dance => (
        0,
        MaterialPageRoute<void>(
          builder: (_) => DanceDetailScreen(danceId: result.id),
        ),
      ),
      CommandResultKind.program => (
        1,
        MaterialPageRoute<void>(
          builder: (_) => ProgramEditorScreen(programId: result.id),
        ),
      ),
    };
    setState(() => _index = tabIndex);
    await Navigator.of(context).push(route);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openSearch,
      },
      child: Focus(autofocus: true, child: _buildScaffold(context)),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppShell.railBreakpoint;
        final body = IndexedStack(index: _index, children: _pages);

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _onSelect,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: IconButton.filledTonal(
                      key: const ValueKey('global-search-button'),
                      icon: const Icon(Icons.search),
                      tooltip: 'Search (Ctrl/Cmd-K)',
                      onPressed: _openSearch,
                    ),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          body: body,
          floatingActionButton: FloatingActionButton.small(
            key: const ValueKey('global-search-fab'),
            heroTag: 'global-search',
            tooltip: 'Search (Ctrl/Cmd-K)',
            onPressed: _openSearch,
            child: const Icon(Icons.search),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _onSelect,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        );
      },
    );
  }
}
