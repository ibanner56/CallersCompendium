import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../theme/app_spacing.dart';

/// One search tool a [SearchPanelBar] can open: its toggle and its content.
class SearchPanelSpec {
  const SearchPanelSpec({
    required this.key,
    required this.label,
    this.semanticsLabel,
    required this.builder,
  });

  /// Put on the toggle, so callers and tests find a panel by the same key the
  /// full-width panel header used to carry.
  final Key key;

  /// The toggle's text, including any active indicator ("Filters · 3",
  /// "Advanced (on)"), so a closed tool still shows that it is narrowing the
  /// results. Kept short so the row of toggles fits on one line.
  final String label;

  /// What a screen reader hears instead of [label], when the short form needs
  /// spelling out ("Filters (3 active)" for "Filters · 3").
  final String? semanticsLabel;

  /// The panel's content.
  final WidgetBuilder builder;
}

/// The search tools (Filters, By phrase, Advanced) as one compact, wrapping row
/// of toggles above the results, with the open tool's content below it.
///
/// Each tool used to be a full-width collapsible header, and the three stacked
/// headers took about 150dp before the first result — nearly a fifth of a
/// phone screen. The row takes one chip's height. One tool is open at a time:
/// a tool's choices stay in force while it is closed, and its toggle says so.
///
/// A tool, once opened, stays mounted while hidden, so what the user did inside
/// it — collapsing a facet section, say — is still there when they come back
/// to it, as it was when every tool could stay open at once.
///
/// Which tool is open is kept in [PageStorage] under [storageId], so scrolling
/// the bar out of view and back does not close it. An explicit identifier, not
/// a page-storage key on the bar: such a key would also become part of the
/// storage identity of every collapsible section inside the panels, and those
/// sections would then share one stored state.
class SearchPanelBar extends StatefulWidget {
  const SearchPanelBar({
    super.key,
    required this.storageId,
    required this.panels,
  });

  /// Unique among the bars under one [PageStorage] (one per route).
  final String storageId;
  final List<SearchPanelSpec> panels;

  @override
  State<SearchPanelBar> createState() => _SearchPanelBarState();
}

class _SearchPanelBarState extends State<SearchPanelBar> {
  Key? _open;

  /// Tools opened at least once while this bar is mounted; kept mounted.
  final Set<Key> _opened = {};
  Timer? _announcement;

  String get _identifier => 'SearchPanelBar.${widget.storageId}';

  @override
  void initState() {
    super.initState();
    final stored = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _identifier);
    _open = stored is Key ? stored : null;
    if (_open != null) _opened.add(_open!);
  }

  @override
  void dispose() {
    _announcement?.cancel();
    super.dispose();
  }

  void _toggle(Key key) {
    setState(() {
      _open = key == _open ? null : key;
      if (_open != null) _opened.add(_open!);
    });
    PageStorage.maybeOf(
      context,
    )?.writeState(context, _open, identifier: _identifier);
    _announce(expanded: _open == key);
  }

  /// Says the new state aloud, as a collapsible header does: the `expanded`
  /// semantics flag alone reaches only desktop and web screen readers. Android
  /// hears it through the toggle's live region instead; iOS waits a second so
  /// VoiceOver does not cut it off (flutter/flutter#122101).
  void _announce({required bool expanded}) {
    if (defaultTargetPlatform == TargetPlatform.android) return;
    final localizations = MaterialLocalizations.of(context);
    final message = expanded
        ? localizations.collapsedHint
        : localizations.expandedHint;
    final view = View.of(context);
    final direction = Directionality.of(context);
    void send() {
      SemanticsService.sendAnnouncement(view, message, direction).catchError((
        Object _,
      ) {
        // diagnostics: silent — a screen-reader announcement is best-effort;
        // the toggle's own semantics still carry the state.
      });
    }

    _announcement?.cancel();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _announcement = Timer(const Duration(seconds: 1), send);
    } else {
      send();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Wrap(
            spacing: AppSpacing.xxs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final panel in widget.panels)
                _PanelToggle(
                  panel: panel,
                  open: panel.key == _open,
                  onToggle: () => _toggle(panel.key),
                ),
            ],
          ),
        ),
        for (final panel in widget.panels)
          if (_opened.contains(panel.key))
            Visibility(
              key: ValueKey(panel.key),
              visible: panel.key == _open,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: panel.builder(context),
              ),
            ),
      ],
    );
  }
}

class _PanelToggle extends StatelessWidget {
  const _PanelToggle({
    required this.panel,
    required this.open,
    required this.onToggle,
  });

  final SearchPanelSpec panel;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // The same state and tap hints a collapsible header gives, so every
    // platform's screen reader hears whether the tool is open, not only those
    // that read the `expanded` flag. An action chip, not a filter chip, so an
    // open tool is not announced as a "selected" filter.
    final stateHint = open
        ? localizations.collapsedHint
        : localizations.expandedHint;
    // One complete node for the toggle: the chip's own semantics are replaced,
    // so its label, button role, open state, hints and tap action are read
    // together. Keyboard focus and activation still come from the chip.
    Widget toggle = Semantics(
      button: true,
      enabled: true,
      expanded: open,
      label: panel.semanticsLabel ?? panel.label,
      hint: stateHint,
      onTapHint: open
          ? localizations.expansionTileExpandedTapHint
          : localizations.expansionTileCollapsedTapHint,
      onTap: onToggle,
      excludeSemantics: true,
      child: ActionChip(
        key: panel.key,
        backgroundColor: open ? scheme.secondaryContainer : null,
        // No leading icon: the label and chevron say what the chip does, and
        // without one all three tools fit one row in a phone-width pane.
        // The chevron already adds space at the end of the label.
        labelPadding: const EdgeInsetsDirectional.only(start: 8, end: 2),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(panel.label)),
            const SizedBox(width: AppSpacing.xxs),
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 18),
          ],
        ),
        onPressed: onToggle,
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android's announcement path, as for a collapsible header: a live
      // region that is read when the state changes, kept out of focus order.
      toggle = Semantics(
        label: stateHint,
        liveRegion: true,
        accessibilityFocusBlockType: AccessibilityFocusBlockType.blockNode,
        child: toggle,
      );
    }
    return toggle;
  }
}
