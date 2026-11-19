import 'dart:async';

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
import '../widgets/hardware_keyboard_presence.dart';
import 'app_shell_search_scope.dart';
import 'collection_shell.dart';
import 'glossary/glossary_screen.dart';
import 'programs_shell.dart';
import 'settings_screen.dart';
import 'user_guide/user_guide_screen.dart';
import '../theme/app_shapes.dart';
import '../theme/app_breakpoints.dart';

/// Top-level navigation between Collection, Programs, the Glossary, Settings,
/// and the User Guide (`docs/design/ux.md` information architecture).
///
/// The Glossary destination (issue #695) appears only while the Experimental
/// "Show glossary" setting is on ([ShowGlossaryScope]).
///
/// - **Narrow (below [AppBreakpoints.rail], 720 px):** bottom [NavigationBar].
/// - **Wide (from 720 px):** left [NavigationRail]. Each destination decides
///   for itself, at [AppBreakpoints.split], whether to show one pane or two.
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
  /// anywhere switches to the Collection destination and reveals the list,
  /// with the tag added to its filter. Tracked so the listener is swapped/removed correctly.
  CollectionFilterController? _filterController;

  /// The seq of the last tag-filter request this shell reacted to, so a repeat
  /// request (even for the same tag) is handled exactly once.
  int _lastFilterSeq = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboardPresence.ensureListening();
  }

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

  /// Reacts to an "add this tag to the Collection's filter" request: selects the
  /// Collection destination and pops any pushed route (a full-screen dance
  /// detail on narrow layouts, or the Tags manager pushed from Settings on any
  /// layout) so the filtered list is visible. The live [DanceListScreen] adds
  /// the tag to its filter by listening to the same controller. On wide
  /// layouts the pop is a no-op unless such a route is pushed, because detail
  /// is embedded.
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

  /// Reaches the Collection's own commands (New dance, Import, search).
  final _collectionCommands = CollectionCommands();

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
  ///
  /// With [programsOnly] the palette lists programs alone: the narrow Programs
  /// list's app-bar search ([_searchPrograms]).
  Future<void> openSearch({bool programsOnly = false}) async {
    if (_paletteOpen) return;
    _paletteOpen = true;
    final result = await showCommandPalette(
      context,
      programsOnly: programsOnly,
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

  /// The narrow Programs list's app-bar search: programs only. A method, not
  /// a closure, so [AppShellSearchScope] sees the same callback every build.
  Future<void> _searchPrograms() => openSearch(programsOnly: true);

  /// Runs Ctrl/Cmd-N and the menu bar's New Dance: the new-dance editor opens
  /// over the Collection (PLAT-7, PLAT-8).
  void newDance() => _returnToShellThen(() {
    setState(() => _current = _Destination.collection);
    _collectionCommands.newDance();
  });

  /// Runs the menu bar's Import Dances…: the Collection's import view opens.
  void importDances() => _returnToShellThen(() {
    setState(() => _current = _Destination.collection);
    _collectionCommands.importDances();
  });

  /// Runs Ctrl/Cmd-, and the menu bar's Settings…
  void showSettings() => _returnToShellThen(
    () => setState(() => _current = _Destination.settings),
  );

  /// Runs the menu bar's User Guide.
  void showGuide() =>
      _returnToShellThen(() => setState(() => _current = _Destination.guide));

  /// Runs Ctrl/Cmd-F: focuses the Collection's search box when the Collection
  /// is showing with nothing over it, and opens global search (dances and
  /// programs) everywhere else: the Programs list, Settings, a pushed page.
  /// On the narrow Programs list that is wider than its app-bar search, which
  /// lists programs only.
  void focusSearch() {
    final onTop = ModalRoute.of(context)?.isCurrent ?? false;
    if (onTop &&
        _current == _Destination.collection &&
        _collectionCommands.focusSearch()) {
      return;
    }
    openSearch();
  }

  /// Leaves every page pushed over the shell, then runs [then], for a command
  /// that names a place in the shell (New dance, Import, Settings, Guide).
  ///
  /// It never skips a page's own guard, and never closes something mid-task:
  /// - With a dialog, sheet or menu open, it does nothing. The dialog may be
  ///   asking a question or showing progress, and closing it would answer for
  ///   the caller.
  /// - It stops at a page that would ask before it closes (an editor with
  ///   unsaved changes, or Perform), and asks it, as the back button does. A
  ///   page that closes without asking on back closes here too: an import
  ///   being reviewed, before it is committed, is left as back leaves it.
  ///   [then] does not run, so the caller repeats the command once they have
  ///   answered.
  ///
  /// [Navigator.popUntil] alone would skip that question: it closes a page
  /// without consulting its `PopScope`.
  void _returnToShellThen(VoidCallback then) {
    final navigator = Navigator.of(context);
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    if (top is! PageRoute) return;
    var guarded = false;
    navigator.popUntil((route) {
      if (route.isFirst) return true;
      guarded = route.popDisposition == RoutePopDisposition.doNotPop;
      return guarded;
    });
    if (guarded) {
      unawaited(navigator.maybePop());
      return;
    }
    then();
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

  /// Keeps every destination's State when this shell swaps the rail for the
  /// bottom bar: the two layouts put the pages at different tree positions,
  /// so without it a rotation across [AppBreakpoints.rail] (most phones turned
  /// to landscape) rebuilds each page from scratch, losing the
  /// Collection's search, filters and scroll, the open Settings section, and
  /// the Perform place the Programs shell holds for each open program
  /// (GIG-14).
  final _bodyKey = GlobalKey();

  /// One page per [_Destination], in enum order.
  List<Widget> _buildPages() => [
    for (final d in _Destination.values)
      switch (d) {
        _Destination.collection => CollectionShell(
          commands: _collectionCommands,
          isActive: _current == _Destination.collection,
        ),
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
        // The shell fills the window, so its constraints are the window's.
        final wide = constraints.maxWidth >= AppBreakpoints.rail;
        // [AppWindowWidth] hands the destinations this width, the window's,
        // so they split at [AppBreakpoints.split] of window width whatever the
        // rail beside them takes.
        //
        // The app-wide update banners sit above the active tab's content so a
        // newer version — or an announced end of support for this one —
        // surfaces on any destination (Collection, Programs, Glossary,
        // Settings, Guide).
        // The macOS not-installed notice (issue #1725) sits with them. Each
        // renders nothing unless it has something to say, so they add no
        // chrome in the common case.
        final nav = _navDestinations;
        final body = AppWindowWidth(
          key: _bodyKey,
          width: constraints.maxWidth,
          child: Column(
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
          ),
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

        // Narrow: there is no rail search. The Collection's own search field
        // is its search, and the Programs list gets a programs-only search in
        // its app bar through [AppShellSearchScope]. Nothing on a phone
        // searches dances and programs together; Ctrl/Cmd-K still does, with
        // a keyboard.
        return AppShellSearchScope(
          searchPrograms: _searchPrograms,
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

/// The nav-rail global-search affordance. Unlike a bare icon button it carries
/// a visible "Search" label and, when a hardware keyboard is likely present
/// ([HardwareKeyboardPresence]), the platform's keyboard hint (⌘K on Apple
/// platforms, Ctrl K elsewhere), so the feature and its Ctrl/Cmd-K shortcut
/// are discoverable rather than hidden behind a glyph
/// (`docs/design/ux-modernization.md` §6). An iPad with no keyboard gets no
/// hint, since there is no key to press.
///
/// Drawn as a [_RailActionButton], the same pill as the rail's destinations.
/// Search is an action, not a place, so it is never shown selected.
class _RailSearchButton extends StatelessWidget {
  const _RailSearchButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final platform = Theme.of(context).platform;
    final isApple =
        platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
    final hint = isApple ? '⌘K' : 'Ctrl K';
    return HardwareKeyboardPresence.builder(
      builder: (context, keyboard) => _RailActionButton(
        key: const ValueKey('global-search-button'),
        onPressed: onPressed,
        icon: const Icon(Icons.search),
        label: l10n.navSearch,
        tooltip: keyboard ? l10n.navSearchTooltip(hint) : l10n.navSearch,
        // The hint's room is kept while it is hidden, so the rail below
        // does not jump down when the first key arrives.
        footer: Visibility(
          visible: keyboard,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: _ShortcutHint(hint),
        ),
      ),
    );
  }
}

/// The nav-rail Help affordance: the bottom-of-rail "User guide" entry, which
/// selects the offline in-app User Guide destination.
///
/// Drawn as a [_RailActionButton], the same pill as the rail's destinations,
/// filled while the guide is the current destination; the help/help_outline
/// glyph swaps with it, so selection is never shown by colour alone.
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
  Widget build(BuildContext context) => _RailActionButton(
    key: const ValueKey('user-guide-button'),
    onPressed: onPressed,
    icon: Icon(selected ? Icons.help : Icons.help_outline),
    label: label,
    tooltip: tooltip,
    selected: selected,
    selectable: true,
  );
}

/// A nav-rail button outside the rail's destination list (Search, Guide),
/// drawn as a destination is: the icon in a [NavigationRail] indicator pill
/// (the rail theme's shape and colour) with the label under it. The pill is
/// filled only while [selected], and hover, focus and press tint the pill, not
/// the whole tile. Icon and label colours follow Material 3's rail: the
/// selected icon on the indicator colour's foreground, otherwise
/// `onSurfaceVariant`, unless the rail theme sets its icon colours.
///
/// The pill is the focusable control, so keyboard focus is drawn on it as on a
/// destination; the whole tile, label included, answers a tap. One merged semantics
/// node announces the label as a button, selected or not.
class _RailActionButton extends StatelessWidget {
  const _RailActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.selected = false,
    this.selectable = false,
    this.footer,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final String label;
  final String tooltip;
  final bool selected;

  /// Whether the button is a place that can be selected (Guide), so screen
  /// readers announce its selected state. Search is an action and has none.
  final bool selectable;

  /// Shown under the label (the search shortcut hint), if any.
  final Widget? footer;

  /// The Material 3 rail indicator's size.
  static const Size _indicatorSize = Size(56, 32);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final railTheme = NavigationRailTheme.of(context);
    final indicatorShape = railTheme.indicatorShape ?? const StadiumBorder();
    final indicatorColor =
        railTheme.indicatorColor ?? scheme.secondaryContainer;
    final selectedIcon = railTheme.selectedIconTheme?.color;
    final unselectedIcon = railTheme.unselectedIconTheme?.color;
    return MergeSemantics(
      child: Tooltip(
        message: tooltip,
        // A tooltip that only repeats the label would be read twice.
        excludeFromSemantics: tooltip == label,
        child: Semantics(
          button: true,
          selected: selectable ? selected : null,
          // The whole tile answers a tap, as a destination does; the pill's
          // own InkWell wins on the pill and draws the ink and focus there.
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onPressed,
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      key: const ValueKey('rail-action-indicator'),
                      color: selected ? indicatorColor : Colors.transparent,
                      shape: indicatorShape,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onPressed,
                        customBorder: indicatorShape,
                        child: SizedBox.fromSize(
                          size: _indicatorSize,
                          child: Center(
                            child: IconTheme.merge(
                              data: IconThemeData(
                                size: 24,
                                color: selected
                                    ? selectedIcon ??
                                          scheme.onSecondaryContainer
                                    : unselectedIcon ?? scheme.onSurfaceVariant,
                              ),
                              child: icon,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (footer case final footer?) ...[
                      const SizedBox(height: 2),
                      footer,
                    ],
                  ],
                ),
              ),
            ),
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
        borderRadius: AppShapes.borderRadiusSmall,
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
