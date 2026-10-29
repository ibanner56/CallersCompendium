import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/callersbox_online.dart';
import '../data/collection_filter_scope.dart';
import '../data/contradb_online.dart';
import '../data/import_io.dart';
import '../data/online_search.dart';
import '../data/repositories_scope.dart';
import '../data/show_glossary_scope.dart';
import '../install/install_location_banner.dart';
import 'dance_reimport_flow.dart';
import '../screens/dance_detail_screen.dart';
import '../screens/program_summary_screen.dart';
import '../theme/app_spacing.dart';
import '../update/retirement_banner.dart';
import '../update/update_banner.dart';
import '../widgets/brand_mark.dart';
import '../widgets/command_palette.dart';
import 'app_shell_search_scope.dart';
import 'collection_shell.dart';
import 'glossary/glossary_screen.dart';
import 'programs_shell.dart';
import 'settings_screen.dart';
import 'user_guide/user_guide_screen.dart';
import '../theme/app_shapes.dart';

/// Top-level navigation between Collection, Programs, the Glossary, Settings,
/// and the User Guide (`docs/design/ux.md` information architecture).
///
/// The Glossary destination (issue #695) appears only while the Experimental
/// "Show Glossary" setting is on ([ShowGlossaryScope]).
///
/// - **Narrow (< 900 px):** bottom [NavigationBar].
/// - **Wide (≥ 900 px):** left [NavigationRail].
///
/// All destinations are kept alive in an [IndexedStack] so switching preserves
/// each screen's state (selection, scroll, in-progress edits). Settings and the
/// User Guide are first-class destinations alongside Collection and Programs
/// rather than pushed routes, so the persistent shell chrome (rail search /
/// bottom bar) stays visible while they're open.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.callersBoxOnline,
    this.contraDbOnline,
    this.reimportPicker,
  });

  final OnlineSearchService? callersBoxOnline;
  final OnlineSearchService? contraDbOnline;
  final ImportPicker? reimportPicker;

  /// Breakpoint (logical pixels) at which the nav rail replaces the bottom bar.
  static const double railBreakpoint = 900;

  @override
  State<AppShell> createState() => AppShellState();
}

/// The shell's destinations, in [IndexedStack] page order.
///
/// Selection is tracked by destination rather than by position because the
/// visible set changes: the Glossary comes and goes with its setting, which
/// would otherwise shift Settings and the Guide to a different index.
enum _Destination { collection, programs, glossary, settings, guide }

class AppShellState extends State<AppShell> {
  _Destination _current = _Destination.collection;

  /// Whether the Glossary destination is shown ([ShowGlossaryScope]).
  bool _showGlossary = false;
  late DanceReimportCoordinator _reimport;
  CompendiumRepositories? _reimportRepos;

  /// The app-level tag-filter coordinator (issue #414). Subscribed so a tag tap
  /// anywhere switches to the Collection destination and reveals the (now
  /// filtered) list. Tracked so the listener is swapped/removed correctly.
  CollectionFilterController? _filterController;

  /// The seq of the last tag-filter request this shell reacted to, so a repeat
  /// request (even for the same tag) is handled exactly once.
  int _lastFilterSeq = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _showGlossary = ShowGlossaryScope.of(context);
    // Turning the setting off while the Glossary is open falls back to the
    // Collection rather than leaving nothing selected.
    if (!_showGlossary && _current == _Destination.glossary) {
      _current = _Destination.collection;
    }
    final repos = RepositoriesScope.of(context);
    if (!identical(repos, _reimportRepos)) {
      _reimportRepos = repos;
      _reimport = DanceReimportCoordinator(
        repos: repos,
        callersBox: widget.callersBoxOnline ?? CallersBoxOnline(),
        contraDb: widget.contraDbOnline ?? ContraDbOnline(),
        picker: widget.reimportPicker ?? pickImportFile,
      );
    }
    final controller = CollectionFilterScope.maybeOf(context);
    if (!identical(controller, _filterController)) {
      _filterController?.removeListener(_onTagFilterRequested);
      _filterController = controller;
      _filterController?.addListener(_onTagFilterRequested);
    }
  }

  @override
  void dispose() {
    _filterController?.removeListener(_onTagFilterRequested);
    super.dispose();
  }

  /// Reacts to a "filter the Collection to this tag" request: selects the
  /// Collection destination and pops any pushed route (e.g. a full-screen dance
  /// detail on narrow layouts) so the filtered list is visible. The live
  /// [DanceListScreen] applies the actual filter by listening to the same
  /// controller. A no-op pop on wide layouts, where detail is embedded.
  void _onTagFilterRequested() {
    final request = _filterController?.pending;
    if (request == null || request.seq == _lastFilterSeq) return;
    _lastFilterSeq = request.seq;
    if (!mounted) return;
    setState(() => _current = _Destination.collection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  /// The destinations the rail (wide) and the bottom bar (narrow) list, in
  /// order. The User Guide is deliberately *not* here: it is the
  /// bottom-of-rail Help affordance on wide layouts and a trailing bottom-bar
  /// destination on narrow ones.
  List<_Destination> get _navDestinations => [
    _Destination.collection,
    _Destination.programs,
    if (_showGlossary) _Destination.glossary,
    _Destination.settings,
  ];

  static ({IconData icon, IconData selectedIcon}) _icons(_Destination d) =>
      switch (d) {
        _Destination.collection => (
          icon: Icons.style_outlined,
          selectedIcon: Icons.style,
        ),
        _Destination.programs => (
          icon: Icons.event_note_outlined,
          selectedIcon: Icons.event_note,
        ),
        _Destination.glossary => (
          icon: Icons.menu_book_outlined,
          selectedIcon: Icons.menu_book,
        ),
        _Destination.settings => (
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
        ),
        _Destination.guide => (
          icon: Icons.help_outline,
          selectedIcon: Icons.help,
        ),
      };

  /// The navigation icon for [d]. Collection's card stack is flipped
  /// vertically so it reads differently from the Glossary's book at a glance.
  static Widget _navIcon(_Destination d, {bool selected = false}) {
    final icons = _icons(d);
    final icon = Icon(selected ? icons.selectedIcon : icons.icon);
    return d == _Destination.collection
        ? Transform.flip(flipY: true, child: icon)
        : icon;
  }

  /// The localized navigation label for [d], from [AppLocalizations].
  static String _destinationLabel(AppLocalizations l10n, _Destination d) =>
      switch (d) {
        _Destination.collection => l10n.navCollection,
        _Destination.programs => l10n.navPrograms,
        _Destination.glossary => l10n.navGlossary,
        _Destination.settings => l10n.navSettings,
        _Destination.guide => l10n.navGuide,
      };

  /// Whether the User Guide is the current destination.
  bool get _guideSelected => _current == _Destination.guide;

  /// Selects the destination at [index] in the visible list: [_navDestinations]
  /// on the rail, and the same list followed by the Guide on the bottom bar.
  void _onSelect(int index) {
    final visible = _navDestinations;
    setState(
      () => _current = index < visible.length
          ? visible[index]
          : _Destination.guide,
    );
  }

  /// Guards against a second palette while one is open (a held Ctrl-K repeats).
  bool _paletteOpen = false;

  /// Opens the global search palette and, if the user picks a result, switches
  /// to the matching section and opens that item's route. Called by the root
  /// `MaterialApp`'s Ctrl/Cmd-K action through the app's
  /// `GlobalKey<AppShellState>` (so it works from pushed routes too) and by the
  /// persistent rail search affordance (`ux-modernization.md` §6).
  ///
  /// Both kinds land on a **read view** — [DanceDetailScreen] and
  /// [ProgramSummaryScreen] — rather than an editor. Search is a way to reach
  /// something, not a request to change it, and the builder stays one tap away
  /// behind the summary's "Edit program".
  Future<void> openSearch() async {
    if (_paletteOpen) return;
    _paletteOpen = true;
    final result = await showCommandPalette(
      context,
    ).whenComplete(() => _paletteOpen = false);
    if (result == null || !mounted) return;
    final (destination, route) = switch (result.kind) {
      CommandResultKind.dance => (
        _Destination.collection,
        MaterialPageRoute<void>(
          builder: (_) => DanceDetailScreen(
            danceId: result.id,
            onReimport: (detail) => _reimport.open(context, detail),
          ),
        ),
      ),
      CommandResultKind.program => (
        _Destination.programs,
        MaterialPageRoute<void>(
          builder: (_) => ProgramSummaryScreen(
            programId: result.id,
            callersBoxOnline: widget.callersBoxOnline,
            contraDbOnline: widget.contraDbOnline,
            reimportPicker: widget.reimportPicker,
          ),
        ),
      ),
    };
    setState(() => _current = destination);
    await Navigator.of(context).push(route);
  }

  /// Selects the offline in-app User Guide destination. Wired to the
  /// bottom-of-rail Help affordance on wide layouts, the last bottom-bar
  /// destination on narrow layouts, and Settings ▸ About ▸ User guide.
  ///
  /// First pops back to the shell so the guide is revealed even when reached
  /// from a pushed route (e.g. the narrow Settings ▸ About detail page); a
  /// no-op when nothing is pushed (the wide inline layout).
  void _openGuide() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _current = _Destination.guide);
  }

  /// One page per [_Destination], in enum order.
  List<Widget> _buildPages() => [
    for (final d in _Destination.values)
      switch (d) {
        _Destination.collection => const CollectionShell(),
        _Destination.programs => const ProgramsShell(),
        // Built only while shown, so a hidden Glossary costs nothing.
        _Destination.glossary =>
          _showGlossary ? const GlossaryScreen() : const SizedBox.shrink(),
        _Destination.settings => SettingsScreen(onOpenGuide: _openGuide),
        // Kept alive alongside the other destinations;
        // [UserGuideScreen.isActive] lets the offscreen guide avoid
        // intercepting system back.
        _Destination.guide => UserGuideScreen(isActive: _guideSelected),
      },
  ];

  @override
  Widget build(BuildContext context) {
    return Focus(autofocus: true, child: _buildScaffold(context));
  }

  Widget _buildScaffold(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppShell.railBreakpoint;
        // The app-wide update banners sit above the active tab's content so a
        // newer version — or an announced end of support for this one —
        // surfaces on any destination (Collection, Programs, Glossary,
        // Settings, Guide).
        // The macOS not-installed notice (issue #1725) sits with them. Each
        // renders nothing unless it has something to say, so they add no
        // chrome in the common case.
        final nav = _navDestinations;
        final body = Column(
          children: [
            const InstallLocationBanner(),
            const RetirementBanner(),
            const UpdateBanner(),
            Expanded(
              child: IndexedStack(
                index: _current.index,
                children: _buildPages(),
              ),
            ),
          ],
        );

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  // The rail hosts [_navDestinations]; the guide is selected
                  // via the trailing Help button, so deselect the rail when
                  // the guide is showing.
                  selectedIndex: _guideSelected ? null : nav.indexOf(_current),
                  onDestinationSelected: _onSelect,
                  labelType: NavigationRailLabelType.all,
                  // On a short window (a landscape phone, or a desktop window
                  // near its minimum height) the rail's contents are taller
                  // than the screen. Scroll the brand, search and destinations
                  // together, and keep Guide pinned to the bottom, rather than
                  // overflowing and clipping it.
                  scrollable: true,
                  leadingAtTop: false,
                  trailingAtBottom: true,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Full-color app tile (petrol + amber) so the mark stays
                        // legible on every theme surface, including high-contrast
                        // ones where a bare glyph could fall below contrast.
                        // Decorative + labeled (Semantics image, not focusable),
                        // so keyboard focus order is unchanged.
                        BrandMark(
                          size: 32,
                          showTile: true,
                          semanticLabel: l10n.appTitle,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _RailSearchButton(onPressed: openSearch),
                      ],
                    ),
                  ),
                  destinations: [
                    for (final d in nav)
                      NavigationRailDestination(
                        icon: _navIcon(d),
                        selectedIcon: _navIcon(d, selected: true),
                        label: Text(_destinationLabel(l10n, d)),
                      ),
                  ],
                  // Bottom-aligned Help affordance: the natural home for the
                  // "User guide" destination on wide layouts. It reads as
                  // selected while the guide is showing.
                  trailing: Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.xs,
                      bottom: AppSpacing.sm,
                    ),
                    child: _RailHelpButton(
                      onPressed: _openGuide,
                      selected: _guideSelected,
                      label: _destinationLabel(l10n, _Destination.guide),
                      tooltip: l10n.navGuideTooltip,
                    ),
                  ),
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
          openSearch: openSearch,
          child: Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _guideSelected
                  ? nav.length
                  : nav.indexOf(_current),
              onDestinationSelected: _onSelect,
              destinations: [
                for (final d in nav)
                  NavigationDestination(
                    icon: _navIcon(d),
                    selectedIcon: _navIcon(d, selected: true),
                    label: _destinationLabel(l10n, d),
                  ),
                // The guide is a persistent last destination on narrow
                // layouts (parity with the wide rail's Help affordance), so
                // viewing it keeps the bottom bar visible.
                NavigationDestination(
                  key: const ValueKey('user-guide-destination'),
                  icon: _navIcon(_Destination.guide),
                  selectedIcon: _navIcon(_Destination.guide, selected: true),
                  label: _destinationLabel(l10n, _Destination.guide),
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isApple =
        theme.platform == TargetPlatform.macOS ||
        theme.platform == TargetPlatform.iOS;
    final hint = isApple ? '\u2318K' : 'Ctrl K';
    return Tooltip(
      message: l10n.navSearchTooltip(hint),
      child: InkWell(
        key: const ValueKey('global-search-button'),
        onTap: onPressed,
        borderRadius: AppShapes.borderRadiusLarge,
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
              Text(l10n.navSearch, style: theme.textTheme.labelMedium),
              const SizedBox(height: 2),
              _ShortcutHint(hint),
            ],
          ),
        ),
      ),
    );
  }
}

/// The desktop nav-rail Help affordance. Mirrors [_RailSearchButton]'s visual
/// pattern — a circular icon tile with a visible label — so the bottom-of-rail
/// "User guide" entry reads as a peer of the search affordance rather than a
/// bare glyph. Selects the offline in-app User Guide destination.
///
/// The tile is always filled with the guide's tertiary accent — a persistent
/// colored affordance that mirrors the always-on search tile above it. The
/// help/help_outline glyph still swaps to signal when the guide is the active
/// destination.
class _RailHelpButton extends StatelessWidget {
  const _RailHelpButton({
    required this.onPressed,
    required this.label,
    required this.tooltip,
    this.selected = false,
  });

  final VoidCallback onPressed;

  /// Localized navigation label (mirrors the narrow layout's guide label).
  final String label;

  /// Localized tooltip shown on hover/long-press.
  final String tooltip;

  /// Whether the guide is the current destination.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: const ValueKey('user-guide-button'),
        onTap: onPressed,
        borderRadius: AppShapes.borderRadiusLarge,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  selected ? Icons.help : Icons.help_outline,
                  color: scheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: theme.textTheme.labelMedium),
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
