import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_spacing.dart';

/// One search tool a [SearchPanelBar] can open: its toggle and its content.
class SearchPanelSpec {
  const SearchPanelSpec({
    required this.key,
    required this.label,
    this.semanticsLabel,
    this.enabled = true,
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

  /// Whether the tool applies right now. A tool that does not (Filters while an
  /// online archive is searched) stays in the row greyed out, rather than
  /// disappearing and moving the others; it cannot be opened, and one that was
  /// open closes.
  final bool enabled;

  /// The panel's content.
  final WidgetBuilder builder;
}

/// The search tools (Filters, By phrase, Advanced) as one compact, wrapping row
/// of toggles, stretched to the full width, above the results, with the open tool's content below it.
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
    this.trailing,
  });

  /// Unique among the bars under one [PageStorage] (one per route).
  final String storageId;
  final List<SearchPanelSpec> panels;

  /// A compact control that sits in the toggles' row after the last one — a
  /// mode switch rather than a tool, so it opens no panel of its own.
  final Widget? trailing;

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
    _open =
        stored is Key &&
            widget.panels.any((panel) => panel.key == stored && panel.enabled)
        ? stored
        : null;
    if (_open != null) _opened.add(_open!);
  }

  @override
  void didUpdateWidget(SearchPanelBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A tool that is no longer offered or enabled (Filters while online) cannot
    // stay the open one, or it would reappear open the moment it applies again.
    if (_open != null &&
        !widget.panels.any((panel) => panel.key == _open && panel.enabled)) {
      _open = null;
      PageStorage.maybeOf(
        context,
      )?.writeState(context, null, identifier: _identifier);
    }
  }

  @override
  void dispose() {
    _announcement?.cancel();
    super.dispose();
  }

  void _toggle(Key key) {
    if (!widget.panels.any((panel) => panel.key == key && panel.enabled)) {
      return;
    }
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
          child: StretchWrap(
            spacing: AppSpacing.xxs,
            runSpacing: AppSpacing.xxs,
            stretchCount: widget.panels.length,
            children: [
              for (final panel in widget.panels)
                _PanelToggle(
                  panel: panel,
                  open: panel.key == _open,
                  onToggle: () => _toggle(panel.key),
                ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
        for (final panel in widget.panels)
          if (_opened.contains(panel.key))
            Visibility(
              key: ValueKey(panel.key),
              visible: panel.key == _open && panel.enabled,
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
    final enabled = panel.enabled;
    Widget toggle = Semantics(
      button: true,
      enabled: enabled,
      expanded: open,
      label: panel.semanticsLabel ?? panel.label,
      hint: stateHint,
      onTapHint: open
          ? localizations.expansionTileExpandedTapHint
          : localizations.expansionTileCollapsedTapHint,
      onTap: enabled ? onToggle : null,
      excludeSemantics: true,
      child: ActionChip(
        key: panel.key,
        backgroundColor: open && enabled ? scheme.secondaryContainer : null,
        // No leading icon, and padding trimmed all round: the label and chevron
        // say what the chip does, and the three tools plus a [trailing] control
        // must share one row on a 390dp phone even with "Filters · 3" showing.
        // The chevron already adds space at the end of the label.
        padding: const EdgeInsets.symmetric(horizontal: 4),
        labelPadding: const EdgeInsetsDirectional.only(start: 4, end: 0),
        // Fills the label slot (no widthFactor), so the chip's visible body grows
        // to the width the row gives it: the spare width becomes padding either
        // side of the centred label, not gaps between natural-width chips. A
        // widthFactor of 1 would make the chip shrink back to its natural width
        // and sit centred in the stretched tap target.
        label: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(panel.label)),
              const SizedBox(width: 2),
              Icon(open ? Icons.expand_less : Icons.expand_more, size: 16),
            ],
          ),
        ),
        onPressed: enabled ? onToggle : null,
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

/// A [Wrap]-like row that fills its width: children flow onto runs as in
/// [Wrap], then each run's spare width is shared out among the first
/// [stretchCount] children in it, so the tiles end flush with the right edge at
/// any screen width or text scale, as the Caller's Box / ContraDB switch does.
/// The rest (a trailing icon control) keep their natural width.
///
/// Stretched tiles in a run end up equal in width where they can; one whose
/// natural width exceeds the equal share keeps it, and the others share what
/// is left. A run with no stretched child is left-aligned.
class StretchWrap extends MultiChildRenderObjectWidget {
  const StretchWrap({
    super.key,
    super.children,
    required this.stretchCount,
    this.spacing = 0,
    this.runSpacing = 0,
  });

  /// How many of the leading children stretch to fill their run.
  final int stretchCount;
  final double spacing;
  final double runSpacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderStretchWrap(stretchCount, spacing, runSpacing);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderStretchWrap renderObject,
  ) {
    renderObject
      ..stretchCount = stretchCount
      ..spacing = spacing
      ..runSpacing = runSpacing;
  }
}

class _StretchWrapParentData extends ContainerBoxParentData<RenderBox> {}

class RenderStretchWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _StretchWrapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _StretchWrapParentData> {
  RenderStretchWrap(this._stretchCount, this._spacing, this._runSpacing);

  int _stretchCount;
  int get stretchCount => _stretchCount;
  set stretchCount(int value) {
    if (value == _stretchCount) return;
    _stretchCount = value;
    markNeedsLayout();
  }

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _runSpacing;
  double get runSpacing => _runSpacing;
  set runSpacing(double value) {
    if (value == _runSpacing) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StretchWrapParentData) {
      child.parentData = _StretchWrapParentData();
    }
  }

  Iterable<RenderBox> get _children sync* {
    for (var c = firstChild; c != null; c = childAfter(c)) {
      yield c;
    }
  }

  /// Widths for one run's children: natural, then the stretched ones levelled
  /// up so the run spans [available].
  List<double> _runWidths(
    List<double> natural,
    int firstIndex,
    double available,
  ) {
    final widths = List<double>.of(natural);
    final stretch = <int>[
      for (var i = 0; i < natural.length; i++)
        if (firstIndex + i < _stretchCount) i,
    ];
    if (stretch.isEmpty) return widths;
    final fixed =
        natural.fold<double>(0, (a, b) => a + b) -
        stretch.fold<double>(0, (a, i) => a + natural[i]);
    var space = available - fixed - _spacing * (natural.length - 1);
    var open = [...stretch];
    // Water-filling: a tile wider than the equal share keeps its natural width
    // and leaves the rest to the others.
    var changed = true;
    while (changed && open.isNotEmpty) {
      changed = false;
      final share = space / open.length;
      for (final i in [...open]) {
        if (natural[i] >= share) {
          space -= natural[i];
          open.remove(i);
          changed = true;
        }
      }
    }
    if (open.isNotEmpty) {
      final share = space / open.length;
      for (final i in open) {
        widths[i] = share;
      }
    }
    return widths;
  }

  /// Lays the children out (or measures them, when [layoutChild] only sizes)
  /// and returns the overall size. [place] receives each child's offset.
  Size _arrange(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints c) layoutChild,
    void Function(RenderBox child, Offset offset)? place,
  ) {
    final maxWidth = constraints.maxWidth;
    final children = _children.toList();
    // Natural widths, to decide where runs break.
    final natural = [
      for (final c in children)
        math.min(c.getMaxIntrinsicWidth(double.infinity), maxWidth),
    ];
    var dy = 0.0;
    var width = 0.0;
    var start = 0;
    while (start < children.length) {
      var end = start + 1;
      var used = natural[start];
      while (end < children.length &&
          used + _spacing + natural[end] <= maxWidth + 0.001) {
        used += _spacing + natural[end];
        end++;
      }
      final widths = _runWidths(natural.sublist(start, end), start, maxWidth);
      final sizes = <Size>[
        for (var i = start; i < end; i++)
          layoutChild(
            children[i],
            BoxConstraints(
              minWidth: widths[i - start],
              maxWidth: widths[i - start],
            ),
          ),
      ];
      final runHeight = sizes.fold<double>(0, (h, s) => math.max(h, s.height));
      var dx = 0.0;
      for (var i = start; i < end; i++) {
        final size = sizes[i - start];
        place?.call(
          children[i],
          Offset(dx, dy + (runHeight - size.height) / 2),
        );
        dx += size.width + _spacing;
      }
      width = math.max(width, dx - _spacing);
      dy += runHeight + _runSpacing;
      start = end;
    }
    final height = children.isEmpty ? 0.0 : dy - _runSpacing;
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() {
    size = _arrange(
      constraints,
      (child, c) {
        child.layout(c, parentUsesSize: true);
        return child.size;
      },
      (child, offset) =>
          (child.parentData! as _StretchWrapParentData).offset = offset,
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _arrange(constraints, (child, c) => child.getDryLayout(c), null);

  @override
  double computeMinIntrinsicWidth(double height) => _children.fold<double>(
    0,
    (w, c) => math.max(w, c.getMinIntrinsicWidth(height)),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _children.fold<double>(0, (w, c) => w + c.getMaxIntrinsicWidth(height)) +
      _spacing * math.max(0, childCount - 1);

  @override
  double computeMinIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
