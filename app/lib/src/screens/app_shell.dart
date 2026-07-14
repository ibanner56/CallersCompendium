import 'package:flutter/material.dart';

import 'collection_shell.dart';
import 'programs_shell.dart';

/// Top-level navigation between Collection and Programs (`docs/design/ux.md`
/// information architecture).
///
/// - **Narrow (< 900 px):** bottom [NavigationBar].
/// - **Wide (≥ 900 px):** left [NavigationRail].
///
/// Both tabs are kept alive in an [IndexedStack] so switching preserves each
/// screen's state (selection, scroll, in-progress edits). Settings remains
/// reachable from each screen's app bar.
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
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music,
      label: 'Collection',
    ),
    (
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
      label: 'Programs',
    ),
  ];

  static const _pages = [CollectionShell(), ProgramsShell()];

  void _onSelect(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
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
