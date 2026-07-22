import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/formation_colors_scope.dart';
import '../data/decimal_turns_scope.dart';
import '../../l10n/app_localizations.dart';
import '../search/facet_labels.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/set_list_accents.dart';
import '../widgets/formation_color_badge.dart';
import '../widgets/import_gap_badge.dart';

/// Shared large-print rendering for Performance mode (`docs/design/ux.md` §5).
///
/// Extracted from [PerformDanceScreen] so both the single-dance Perform view
/// and the program-mode Perform view render *identically* and never diverge.
/// The dance card reuses the same correctness path as the detail card — core
/// [deriveSections] for phrase grouping and [FigureRenderer.render] for the
/// dialect-applied figure text.

/// Default in-view scale so the card reads from across a room on first open.
const double kPerformDefaultScale = 1.8;

/// A sensible lower bound (below the app's normal text size the "large-print"
/// intent is lost). There is deliberately no practical upper bound.
const double kPerformMinScale = 1.0;

/// Upper bound for the *auto-size* fit search only (ROADMAP G.1). Manual mode
/// keeps its "no practical upper bound" behaviour; auto-size is naturally
/// bounded by what fits the viewport, but the binary search needs a finite
/// ceiling. This is generous enough that short slots ("break", a title-only
/// card) grow to fill the screen.
const double kPerformMaxAutoScale = 12.0;

/// Step for the A-/A+ size control.
const double kPerformScaleStep = 0.2;

/// Composes the in-view large-print [scale] *on top of* the user's existing
/// system / accessibility text scaling rather than replacing it, so we never
/// shrink text below what the user's device preference asks for.
TextScaler _effectiveScaler(BuildContext context, double scale) {
  final systemScale = MediaQuery.of(context).textScaler.scale(1);
  return TextScaler.linear(systemScale * scale);
}

/// Large-print card body for a dance-backed slot: header (title / authors /
/// formation / level / status) + section-grouped figures + calling notes.
///
/// Applies the composed large-print [textScale] to its subtree so it renders
/// the same whether shown by the single-dance or program Perform view.
class PerformCard extends StatelessWidget {
  const PerformCard({
    super.key,
    required this.dance,
    required this.renderer,
    required this.dialect,
    required this.textScale,
    this.autoSize = false,
    this.authorNames = const [],
    this.fitScaleCache,
  });

  final Dance dance;
  final FigureRenderer renderer;
  final Dialect dialect;
  final double textScale;

  /// When `true`, ignore [textScale] and auto-scale so the full card fits the
  /// viewport without scrolling (ROADMAP G.1). When `false`, use [textScale]
  /// (the manual A-/A+ size, Phase 5.1).
  final bool autoSize;

  /// Resolved author display names, rendered under the title when non-empty.
  final List<String> authorNames;

  /// Parent-owned auto-fit scale cache (see [PerformFitScaleCache]). Passed by a
  /// view that navigates between slots of different card types so the fit does
  /// not flash on revisit; null for one-off uses.
  final PerformFitScaleCache? fitScaleCache;

  /// The padded card content at [scale], composed on top of the system text
  /// scaling. Produced without its own scroll view so [_FitToHeight] can
  /// measure its natural height; the manual path wraps it in a scroll view.
  Widget _body(BuildContext context, double scale) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: _effectiveScaler(context, scale)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(dance: dance, authorNames: authorNames),
            const SizedBox(height: AppSpacing.lg),
            _Figures(
              figures: dance.figures,
              phraseStructure: dance.phraseStructure,
              renderer: renderer,
              dialect: dialect,
            ),
            if (dance.callingNotes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _SectionTitle(AppLocalizations.of(context).performCallingNotes),
              const SizedBox(height: AppSpacing.xs),
              Text(
                renderer.renderFreeText(dance.callingNotes, dialect),
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.merge(AppTypography.performBody),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (autoSize) {
      return _FitToHeight(
        minScale: kPerformMinScale,
        maxScale: kPerformMaxAutoScale,
        resetToken: Object.hash(dance.id, dialect),
        builder: _body,
        scaleCache: fitScaleCache,
      );
    }
    return SingleChildScrollView(child: _body(context, textScale));
  }
}

/// Large-print card body for a free-text-only program slot (a break, waltz,
/// announcement…): the slot text rendered big, with no figures. Mirrors
/// [PerformCard]'s scaler composition so text size behaves identically.
class PerformTextCard extends StatelessWidget {
  const PerformTextCard({
    super.key,
    required this.text,
    required this.textScale,
    this.autoSize = false,
    this.fitScaleCache,
  });

  final String text;
  final double textScale;

  /// See [PerformCard.autoSize].
  final bool autoSize;

  /// See [PerformCard.fitScaleCache].
  final PerformFitScaleCache? fitScaleCache;

  Widget _body(BuildContext context, double scale) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: _effectiveScaler(context, scale)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              key: const ValueKey('perform-text'),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (autoSize) {
      return _FitToHeight(
        minScale: kPerformMinScale,
        maxScale: kPerformMaxAutoScale,
        resetToken: text,
        builder: _body,
        scaleCache: fitScaleCache,
      );
    }
    return SingleChildScrollView(child: _body(context, textScale));
  }
}

/// A small, viewport-aware cache of converged auto-fit scales, keyed by a
/// slot's `resetToken`. Used by [_FitToHeight].
///
/// This is owned by the *parent* that drives slot navigation (e.g. the program
/// Perform screen) and threaded down through [PerformCard] / [PerformTextCard]
/// into [_FitToHeight]. Keeping it *above* the dance-vs-free-text card-type
/// switch is essential: navigating dance → free-text → dance replaces that
/// differently typed subtree and disposes the [_FitToHeight] state, so a cache
/// living inside that state would be lost and the fit would restart at
/// `minScale` (the "grow-in" flash) on the return visit. A parent-owned cache
/// survives the switch, so revisiting a slot reuses its remembered scale.
///
/// A converged scale depends on the available height, which in turn depends on
/// both the viewport size *and* the system/accessibility text scale (the
/// in-view fit is composed on top of `MediaQuery.textScaler` via
/// [_effectiveScaler]). The cache is therefore only valid for one
/// (viewport, systemTextScale) context: every entry is dropped when either the
/// viewport size (orientation / window resize) or the OS text size changes, so
/// a stale converged scale can never survive an enlargement and overflow.
class PerformFitScaleCache {
  final Map<Object?, double> _scales = <Object?, double>{};
  Size? _viewport;
  double? _systemTextScale;

  void _syncContext(Size viewport, double systemTextScale) {
    if (_viewport != viewport || _systemTextScale != systemTextScale) {
      _scales.clear();
      _viewport = viewport;
      _systemTextScale = systemTextScale;
    }
  }

  /// The remembered scale for [token] in the given
  /// ([viewport], [systemTextScale]) context, or null if none is cached. A
  /// context that differs from the cached one first clears the cache (a stale
  /// fit no longer holds), then returns null.
  double? scaleFor(Object? token, Size viewport, double systemTextScale) {
    _syncContext(viewport, systemTextScale);
    return _scales[token];
  }

  /// Records the converged [scale] for [token] in the given
  /// ([viewport], [systemTextScale]) context.
  void remember(
    Object? token,
    Size viewport,
    double systemTextScale,
    double scale,
  ) {
    _syncContext(viewport, systemTextScale);
    _scales[token] = scale;
  }
}

/// Auto-scales [builder]'s content to the largest text scale in
/// `[minScale, maxScale]` whose full natural height fits the available viewport
/// without scrolling (ROADMAP G.1).
///
/// Uses a [LayoutBuilder] for the viewport and a post-frame measurement of the
/// content's natural (unbounded) height via a [GlobalKey], binary-searching the
/// scale across frames until it converges on the largest fitting value. The
/// content stays wrapped in a [SingleChildScrollView] so that even when the
/// smallest scale still overflows (a very long dance on a tiny screen) the text
/// is scrollable rather than clipped — content is never hidden.
///
/// The first fit for a given [resetToken] must measure across a few frames, so
/// it grows in from [minScale]. To avoid that visible "grow-in" flash *every*
/// time the caller pages back to a slot they have already seen, the converged
/// scale is cached per [resetToken] (for the current viewport and system text
/// scale) in a [PerformFitScaleCache]. Revisiting a token starts at its
/// remembered scale and skips the search. The cache is invalidated when the
/// viewport size or the OS/accessibility text scale changes, so an enlargement
/// re-measures rather than reusing a now-too-large scale. Pass [scaleCache] from
/// a parent that outlives the dance-vs-free-text card-type switch so the cache
/// survives it; when omitted an internal cache is used (fine for callers that
/// never swap card types, such as the single-dance view).
class _FitToHeight extends StatefulWidget {
  const _FitToHeight({
    required this.minScale,
    required this.maxScale,
    required this.resetToken,
    required this.builder,
    this.scaleCache,
  });

  final double minScale;
  final double maxScale;
  final Object? resetToken;
  final Widget Function(BuildContext context, double scale) builder;

  /// Parent-owned cache of converged scales that survives the dance-vs-free-text
  /// card-type switch. When null, an internal per-state cache is used instead.
  final PerformFitScaleCache? scaleCache;

  @override
  State<_FitToHeight> createState() => _FitToHeightState();
}

class _FitToHeightState extends State<_FitToHeight> {
  static const double _scaleEpsilon = 0.02;
  static const double _heightEpsilon = 0.5;

  final GlobalKey _contentKey = GlobalKey();

  /// Fallback cache used only when no parent-owned [_FitToHeight.scaleCache] is
  /// supplied. It is disposed with this state — so it cannot survive a card-type
  /// switch (exactly why the program view passes a parent-owned cache instead).
  final PerformFitScaleCache _ownCache = PerformFitScaleCache();

  PerformFitScaleCache get _cache => widget.scaleCache ?? _ownCache;

  late double _lo = widget.minScale;
  late double _hi = widget.maxScale;
  late double _scale = widget.minScale;

  Size? _lastViewport;
  double? _lastSystemTextScale;
  Object? _lastToken;
  bool _converged = false;

  /// Prepares the search for [token] in the ([viewport], [systemTextScale])
  /// context: if a converged scale for it is cached (same context), reuse it
  /// directly and skip the search — no flash — else restart the binary search
  /// from [minScale].
  void _beginToken(Object? token, Size viewport, double systemTextScale) {
    final cached = _cache.scaleFor(token, viewport, systemTextScale);
    if (cached != null) {
      _lo = cached;
      _hi = widget.maxScale;
      _scale = cached;
      _converged = true;
    } else {
      _resetSearch();
    }
  }

  void _resetSearch() {
    _lo = widget.minScale;
    _hi = widget.maxScale;
    _scale = widget.minScale;
    _converged = false;
  }

  void _measureAndStep(Size viewport, double systemTextScale) {
    if (!mounted || _converged) return;
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final contentHeight = box.size.height;

    final fits = contentHeight <= viewport.height + _heightEpsilon;
    if (fits) {
      _lo = _scale;
    } else {
      _hi = _scale;
    }

    if (_hi - _lo <= _scaleEpsilon) {
      // Settle on the largest scale known to fit, and remember it so a return
      // visit to this slot skips the search.
      final settled = _lo.clamp(widget.minScale, widget.maxScale);
      _converged = true;
      _cache.remember(widget.resetToken, viewport, systemTextScale, settled);
      if ((settled - _scale).abs() > _scaleEpsilon / 2) {
        setState(() => _scale = settled);
      }
      return;
    }

    final next = (_lo + _hi) / 2;
    setState(() => _scale = next);
  }

  @override
  Widget build(BuildContext context) {
    // Reading the system text scale here registers this element as a
    // MediaQuery dependent, so an OS/accessibility text-size change rebuilds
    // us. Because the in-view fit is composed on top of this scale, a change
    // must invalidate the cached converged scale and re-measure — otherwise an
    // enlargement would keep a stale (too-large) scale and overflow.
    final systemTextScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastViewport != viewport ||
            _lastSystemTextScale != systemTextScale) {
          _lastViewport = viewport;
          _lastSystemTextScale = systemTextScale;
          _lastToken = widget.resetToken;
          _beginToken(widget.resetToken, viewport, systemTextScale);
        } else if (_lastToken != widget.resetToken) {
          _lastToken = widget.resetToken;
          _beginToken(widget.resetToken, viewport, systemTextScale);
        }
        if (viewport.height.isFinite) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _measureAndStep(viewport, systemTextScale);
          });
        }
        return SingleChildScrollView(
          child: KeyedSubtree(
            key: _contentKey,
            child: widget.builder(context, _scale),
          ),
        );
      },
    );
  }
}

/// The A-/A+ large-print size control, shared by both Perform views as AppBar
/// actions. Keeps identical keys/tooltips so behaviour and tests match.
class PerformSizeControls extends StatelessWidget {
  const PerformSizeControls({
    super.key,
    required this.canDecrease,
    required this.onDecrease,
    required this.onIncrease,
  });

  final bool canDecrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('decrease-text-size'),
          tooltip: l10n.performDecreaseTextSize,
          icon: const Icon(Icons.text_decrease),
          onPressed: canDecrease ? onDecrease : null,
        ),
        IconButton(
          key: const ValueKey('increase-text-size'),
          tooltip: l10n.performIncreaseTextSize,
          icon: const Icon(Icons.text_increase),
          onPressed: onIncrease,
        ),
      ],
    );
  }
}

/// The canonical ⇄ dialect quick-toggle, shared by both Perform views. Hidden
/// by callers when the active dialect is already [Dialect.canonical].
class PerformDialectToggle extends StatelessWidget {
  const PerformDialectToggle({
    super.key,
    required this.canonical,
    required this.onChanged,
  });

  final bool canonical;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // Icon-only toggle (consistent with PerformAutoSizeToggle and
    // PerformStageToggle) so the Perform AppBar's action row fits narrow phones
    // without overflowing — the earlier label+Switch layout was ~2.5x wider than
    // its sibling actions and pushed the trailing toolbar past the screen edge.
    // The accessible name stays 'Show canonical terms' and the on/off STATE is
    // folded into the button's own node via Semantics.toggled, so assistive tech
    // announces one control carrying role, name, tap action, and toggle state.
    //
    // Uses the app's Dialect glyph family (`Icons.groups`), NOT `Icons.translate`
    // (which is reserved for Settings › Language & region / app locale). Canonical
    // vs dialect terminology is a dialect-domain concern, so it shares the
    // Dialect glyph and follows the outlined-idle/filled-active convention:
    // outlined when showing dialect terms, filled when canonical terms are shown.
    return MergeSemantics(
      child: Semantics(
        toggled: canonical,
        child: IconButton(
          key: const ValueKey('perform-dialect-toggle'),
          tooltip: AppLocalizations.of(context).performShowCanonicalTerms,
          isSelected: canonical,
          icon: const Icon(Icons.groups_outlined),
          selectedIcon: const Icon(Icons.groups),
          onPressed: () => onChanged(!canonical),
        ),
      ),
    );
  }
}

/// Wraps a Perform screen's [Scaffold] in the high-contrast dark-stage
/// [Theme] when [enabled], and renders under the app's ambient/inherited theme
/// otherwise. Shared by both Perform views so the single-dance and program
/// views theme identically (`docs/design/ux.md` §5: "7:1 contrast themes,
/// dark-stage default"). Reuses the existing [AppTheme.highContrast] — the
/// outline-driven, 7:1-targeted dark scheme co-owned with Perform mode — rather
/// than inventing a palette. Wrapping the whole Scaffold means the AppBar is
/// themed too.
class PerformStageTheme extends StatelessWidget {
  const PerformStageTheme({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Theme(data: AppTheme.highContrast, child: child);
  }
}

/// In-view toggle for auto-sizing the Perform card to fit the viewport
/// (ROADMAP G.1), shared by both Perform views as an AppBar action. Initialised
/// from the General setting (on by default). When on, the card auto-scales; the
/// A-/A+ controls remain available and, when used, hand control back to the
/// manual size. This toggle lets a caller flip auto-fit back on within a
/// session. Pairs an icon with a state-dependent tooltip (never color-only) and
/// exposes its on/off STATE to assistive tech via [Semantics.toggled], matching
/// [PerformStageToggle].
class PerformAutoSizeToggle extends StatelessWidget {
  const PerformAutoSizeToggle({
    super.key,
    required this.autoSizeOn,
    required this.onChanged,
  });

  final bool autoSizeOn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tooltip = autoSizeOn
        ? l10n.performAutoSizeOnTooltip
        : l10n.performAutoSizeOffTooltip;
    return MergeSemantics(
      child: Semantics(
        toggled: autoSizeOn,
        child: IconButton(
          key: const ValueKey('perform-autosize-toggle'),
          tooltip: tooltip,
          isSelected: autoSizeOn,
          icon: const Icon(Icons.fit_screen_outlined),
          selectedIcon: const Icon(Icons.fit_screen),
          onPressed: () => onChanged(!autoSizeOn),
        ),
      ),
    );
  }
}

/// In-view toggle for the dark-stage high-contrast theme, shared by both
/// Perform views as an AppBar action. Defaults on (see the screens' initial
/// state). The control pairs an icon with a state-dependent tooltip (never
/// color-only) and exposes its on/off STATE to assistive tech via
/// [Semantics.toggled], so a caller always knows whether stage mode is active.
class PerformStageToggle extends StatelessWidget {
  const PerformStageToggle({
    super.key,
    required this.stageOn,
    required this.onChanged,
  });

  final bool stageOn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tooltip = stageOn
        ? l10n.performStageThemeOnTooltip
        : l10n.performStageThemeOffTooltip;
    // MergeSemantics + Semantics(toggled:) fold the on/off STATE into the
    // IconButton's own node, so AT announces one control that carries the
    // button role, name (tooltip), tap action, and current toggle state —
    // rather than a static label with no sense of whether stage mode is on.
    return MergeSemantics(
      child: Semantics(
        toggled: stageOn,
        child: IconButton(
          key: const ValueKey('perform-stage-toggle'),
          tooltip: tooltip,
          isSelected: stageOn,
          icon: const Icon(Icons.dark_mode_outlined),
          selectedIcon: const Icon(Icons.dark_mode),
          onPressed: () => onChanged(!stageOn),
        ),
      ),
    );
  }
}

/// Width (logical px) at or above which a Perform AppBar shows its full action
/// set inline; below it, secondary actions collapse into an overflow menu
/// (issue #433). 600 is Material's compact/medium window boundary: phones in
/// portrait sit below it (so the ~10-button row can't RenderFlex-overflow a
/// 360–430px screen), while tablets/large windows show everything inline. The
/// full inline set needs ~544px (leading + 10 icon buttons), so it always fits
/// once the layout is >= 600px wide.
const double kPerformActionsCollapseWidth = 600;

/// One secondary Perform AppBar action, rendered as an item inside
/// [PerformOverflowMenu] when the AppBar collapses on narrow widths (issue
/// #433). [toggledOn] being non-null marks a toggle, rendered as a
/// [CheckedPopupMenuItem] so assistive tech announces its on/off state; the
/// [icon] is used as the leading glyph for plain (non-toggle) actions.
@immutable
class PerformMenuAction {
  const PerformMenuAction({
    required this.menuKey,
    required this.icon,
    required this.label,
    required this.onSelected,
    this.enabled = true,
    this.toggledOn,
  });

  final Key menuKey;
  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final bool enabled;
  final bool? toggledOn;
}

/// The "More actions" overflow control for the Perform AppBar (issue #433).
/// Collapses [actions] (the secondary controls) into a single
/// [PopupMenuButton] on narrow phone widths so the toolbar can't overflow,
/// while the primary stage-mode toggle stays inline. Carries a 'More actions'
/// tooltip/semantics label, and each item keeps a clear text label.
class PerformOverflowMenu extends StatelessWidget {
  const PerformOverflowMenu({super.key, required this.actions});

  final List<PerformMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('perform-overflow-menu'),
      icon: const Icon(Icons.more_vert),
      tooltip: AppLocalizations.of(context).performMoreActions,
      // onSelected fires after the menu has closed, so actions that open a
      // sheet (e.g. adjust/jump/tap-tempo) don't fight the menu's own pop.
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        for (final action in actions)
          if (action.toggledOn != null)
            CheckedPopupMenuItem<VoidCallback>(
              key: action.menuKey,
              value: action.onSelected,
              checked: action.toggledOn!,
              enabled: action.enabled,
              child: Text(action.label),
            )
          else
            PopupMenuItem<VoidCallback>(
              key: action.menuKey,
              value: action.onSelected,
              enabled: action.enabled,
              child: Row(
                children: [
                  Icon(action.icon),
                  const SizedBox(width: 12),
                  // Flexible so a long label wraps within the popup's width
                  // instead of RenderFlex-overflowing the menu item.
                  Flexible(child: Text(action.label)),
                ],
              ),
            ),
      ],
    );
  }
}

/// Builds a Perform AppBar's trailing [AppBar.actions] with responsive overflow
/// (issue #433). When [wide] (the caller measures the available width against
/// [kPerformActionsCollapseWidth] with a [LayoutBuilder]) every action renders
/// inline in its original order ([leadingPrimary], then [secondaryInline], then
/// [trailingPrimary]) — the full tablet/large-window toolbar. Otherwise only
/// [leadingPrimary] and [trailingPrimary] (the stage-mode toggle, which must
/// stay reachable mid-gig) stay inline and the [secondaryInline] controls
/// collapse into a single [PerformOverflowMenu] built from [overflowActions],
/// so a 360–430px phone can't overflow.
List<Widget> buildPerformAppBarActions({
  required bool wide,
  required Widget leadingPrimary,
  required List<Widget> secondaryInline,
  required List<PerformMenuAction> overflowActions,
  required Widget trailingPrimary,
}) {
  return [
    leadingPrimary,
    if (wide) ...secondaryInline else trailingPrimary,
    if (wide)
      trailingPrimary
    else
      PerformOverflowMenu(actions: overflowActions),
    const SizedBox(width: 8),
  ];
}

class _Header extends StatelessWidget {
  const _Header({required this.dance, required this.authorNames});

  final Dance dance;
  final List<String> authorNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final level = dance.level;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dance.title,
          key: const ValueKey('perform-title'),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (authorNames.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            authorNames.join(', '),
            style: theme.textTheme.headlineSmall?.merge(
              AppTypography.performBody,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        _MetaRow(
          icon: formationIcon,
          text: formationLabel(l10n, dance.formation),
          // Per-formation label colour (issue #367): highlight only when the
          // user overrode this shape (override-only).
          highlightColor: FormationColorsScope.of(
            context,
          )?.overrideFor(dance.formation.shape),
        ),
        if (level != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _MetaRow(
            icon: Icons.signal_cellular_alt_outlined,
            text: danceLevelLabel(l10n, level),
          ),
        ],
        if (dance.status != DanceStatus.active) ...[
          const SizedBox(height: AppSpacing.md),
          _StatusBanner(status: dance.status),
        ],
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text, this.highlightColor});

  final IconData icon;
  final String text;

  /// When non-null, the [text] is wrapped in a [FormationColorBadge] of this
  /// colour (issue #367) with an auto-contrast foreground; otherwise it renders
  /// as plain meta text.
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineSmall?.merge(
      AppTypography.performBody,
    );
    final iconSize =
        (style?.fontSize ?? 24) * MediaQuery.textScalerOf(context).scale(1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: iconSize.clamp(24.0, 96.0)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: highlightColor == null
              ? Text(text, style: style)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: FormationColorBadge(
                    color: highlightColor!,
                    // Force the label onto the badge's contrast-safe
                    // foreground: the themed `style` carries a colour that
                    // would otherwise merge OVER the badge's DefaultTextStyle
                    // and defeat the auto-contrast (issue #367, ruling 1).
                    child: Text(
                      text,
                      style: (style ?? const TextStyle()).copyWith(
                        color: readableForegroundOn(highlightColor!),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Text(
        text,
        style: theme.textTheme.headlineMedium
            ?.merge(AppTypography.performSectionHeader)
            .copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
      ),
    );
  }
}

/// Large-print, section-grouped figure list. Section derivation, beats and the
/// progression marker come from the core [deriveSections]; each figure's text
/// comes from [FigureRenderer.render] under the active [dialect], mirroring the
/// correctness path of the read-only detail table.
class _Figures extends StatelessWidget {
  const _Figures({
    required this.figures,
    required this.phraseStructure,
    required this.renderer,
    required this.dialect,
  });

  final List<Figure> figures;
  final PhraseStructure phraseStructure;
  final FigureRenderer renderer;
  final Dialect dialect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (figures.isEmpty) {
      return Text(
        AppLocalizations.of(context).performNoFigures,
        style: theme.textTheme.headlineSmall?.merge(AppTypography.performBody),
      );
    }

    final sectioned = deriveSections(figures, phraseStructure);
    final decimals = DecimalTurnsScope.of(context);
    final children = <Widget>[];
    String? lastLabel;
    for (final sf in sectioned) {
      if (sf.label != lastLabel) {
        children.add(
          Padding(
            padding: EdgeInsets.only(
              top: lastLabel == null ? 0 : AppSpacing.lg,
              bottom: AppSpacing.xs,
            ),
            child: Semantics(
              header: true,
              child: Text(
                sf.label,
                style: theme.textTheme.headlineMedium
                    ?.merge(AppTypography.performSectionHeader)
                    .copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
              ),
            ),
          ),
        );
        lastLabel = sf.label;
      }
      // Custom-figure text is user-authored, so it may carry inline emphasis
      // markup. Parse the RAW text into styled spans and dialect-substitute
      // each span individually — stripping the delimiters BEFORE substitution
      // so markup can never interfere with role-term word boundaries (the
      // substitutor treats `_` as a word character). Non-custom lines are
      // canonical/derived and are rendered verbatim, never emphasis-parsed.
      List<EmphasisSpan>? mainSpans;
      if (sf.figure.isCustom) {
        final raw = (sf.figure.params['text'] as String?) ?? '';
        if (raw.isNotEmpty) {
          mainSpans = [
            for (final span in parseInlineEmphasis(raw))
              EmphasisSpan(
                text: renderer.renderFreeText(span.text, dialect),
                bold: span.bold,
                underline: span.underline,
              ),
          ];
        }
      }
      children.add(
        _FigureRow(
          text: renderer.renderSummary(sf.figure, dialect, decimals: decimals),
          mainSpans: mainSpans,
          verboseText: renderer.renderSummary(
            sf.figure,
            dialect,
            verbose: true,
          ),
          beats: sf.figure.beats,
          progression: sf.figure.progression,
          note: sf.figure.note,
          isImportGap:
              sf.figure.isCustom &&
              sf.figure.customOrigin == CustomOrigin.importGap,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _FigureRow extends StatelessWidget {
  const _FigureRow({
    required this.text,
    required this.mainSpans,
    required this.verboseText,
    required this.beats,
    required this.progression,
    required this.note,
    required this.isImportGap,
  });

  /// Terse, dialect-applied text shown on screen (non-custom figures).
  final String text;

  /// Pre-parsed, dialect-substituted emphasis spans for the main line of a
  /// user-authored custom figure, or null for canonical (non-custom) lines.
  final List<EmphasisSpan>? mainSpans;

  /// Verbose, spoken-friendly rendering announced to assistive tech in place of
  /// the terse [text] (figure-taxonomy.md §5.4 / accessibility baseline).
  final String verboseText;
  final int beats;
  final bool progression;
  final String? note;

  /// Whether this is a parser-gap custom figure ([CustomOrigin.importGap]),
  /// which gets a badge + subtle row shading.
  final bool isImportGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final beatsLabel = l10n.danceFigureBeats(beats);
    // Emphasis is a purely visual cue: announce the underlying words with the
    // markup delimiters stripped so a screen reader never voices stray `*`/`_`.
    // For a custom line, use the already delimiter-stripped + dialect-
    // substituted [mainSpans] so the label matches the on-screen words (the
    // verbose rendering can leave role tokens unsubstituted when an underscore
    // sits against them); otherwise strip the canonical verbose text.
    final noteText = note?.trim() ?? '';
    final mainSemantics = mainSpans != null
        ? mainSpans!.map((s) => s.text).join()
        : stripInlineEmphasis(verboseText);
    // Modelled as ONE ICU message (never fragment concatenation) so translators
    // control ordering. The localized import-gap explanation flows through a
    // placeholder so the whole semantics phrase stays a single ICU message.
    final semanticsLabel = l10n.performFigureSemantic(
      mainSemantics,
      isImportGap ? 'yes' : 'no',
      isImportGap ? l10n.importGapMessage : '',
      progression ? 'yes' : 'no',
      beats,
      noteText.isNotEmpty ? 'yes' : 'no',
      noteText.isNotEmpty ? stripInlineEmphasis(noteText) : '',
    );
    final textStyle = theme.textTheme.headlineSmall?.merge(
      AppTypography.performBody,
    );
    final noteStyle = theme.textTheme.titleMedium?.copyWith(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        color: isImportGap
            ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.35)
            : null,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: progression
                  ? Tooltip(
                      message: l10n.performProgression,
                      child: Icon(
                        progressionIcon,
                        size: MediaQuery.textScalerOf(
                          context,
                        ).scale(textStyle?.fontSize ?? 24).clamp(20.0, 32.0),
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (mainSpans != null)
                    Text.rich(_emphasisSpan(mainSpans!), style: textStyle)
                  else
                    Text(text, style: textStyle),
                  if (noteText.isNotEmpty)
                    Text.rich(
                      _emphasisSpan(parseInlineEmphasis(noteText)),
                      style: noteStyle,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            if (isImportGap) ...[
              const ImportGapBadge(),
              const SizedBox(width: AppSpacing.md),
            ],
            Text(
              beatsLabel,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a `TextSpan` tree from parsed [EmphasisSpan]s, applying bold and/or
  /// underline per span. Base styling is supplied by the enclosing
  /// `Text.rich(style: ...)`. Purely visual — the text itself is unchanged.
  static TextSpan _emphasisSpan(List<EmphasisSpan> spans) {
    return TextSpan(
      children: [
        for (final span in spans)
          TextSpan(
            text: span.text,
            style: TextStyle(
              fontWeight: span.bold ? FontWeight.bold : null,
              decoration: span.underline ? TextDecoration.underline : null,
            ),
          ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final DanceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final (icon, color) = switch (status) {
      DanceStatus.broken => (Icons.error_outline, theme.colorScheme.error),
      DanceStatus.deprecated => (
        Icons.warning_amber_outlined,
        theme.colorScheme.tertiary,
      ),
      DanceStatus.active => (
        Icons.check_circle_outline,
        theme.colorScheme.primary,
      ),
    };
    final style = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final iconSize =
        (style?.fontSize ?? 22) * MediaQuery.textScalerOf(context).scale(1);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: iconSize.clamp(22.0, 72.0), color: color),
          const SizedBox(width: AppSpacing.sm),
          Text(danceStatusLabel(l10n, status), style: style),
        ],
      ),
    );
  }
}
