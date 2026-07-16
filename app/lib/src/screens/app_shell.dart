import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/dance_detail_screen.dart';
import '../screens/program_editor_screen.dart';
import '../widgets/command_palette.dart';
import 'app_shell_search_scope.dart';
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
                    child: _RailSearchButton(onPressed: _openSearch),
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

        // Narrow: the bottom-right FAB slot belongs to each screen's "New"
        // FAB.extended, so search moves into the app bar via
        // [AppShellSearchScope] (nested list screens surface a 1-tap search
        // action). This avoids the phone double-FAB collision while keeping a
        // labeled affordance consistent with the wide layout's rail search.
        return AppShellSearchScope(
          openSearch: _openSearch,
          child: Scaffold(
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
          ),
        );
      },
    );
  }
}

/// The desktop nav-rail global-search affordance. Unlike a bare icon button it
/// carries a visible "Search" label and a platform-appropriate keyboard hint
/// (⌘K on Apple platforms, Ctrl K elsewhere) so the feature — and its
/// Ctrl/Cmd-K shortcut — is discoverable rather than hidden behind a glyph
/// (`docs/design/ux-modernization.md` §6). Keeps the `global-search-button`
/// key and tooltip so existing wiring and tests are preserved.
class _RailSearchButton extends StatelessWidget {
  const _RailSearchButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isApple =
        theme.platform == TargetPlatform.macOS ||
        theme.platform == TargetPlatform.iOS;
    final hint = isApple ? '\u2318K' : 'Ctrl K';
    return Tooltip(
      message: 'Search ($hint)',
      child: InkWell(
        key: const ValueKey('global-search-button'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.search, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 4),
              Text('Search', style: theme.textTheme.labelMedium),
              const SizedBox(height: 2),
              _ShortcutHint(hint),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small keyboard-key style chip showing a shortcut hint (e.g. "⌘K").
class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('global-search-shortcut-hint'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
