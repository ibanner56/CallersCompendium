import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/colour_dance_theme.dart';
import '../widgets/dialect_quick_switch.dart';
import '../widgets/tap_tempo_metronome.dart';
import 'perform_a11y_prefs.dart';
import 'perform_card.dart';
import 'perform_wakelock.dart';
import 'perform_walkthrough_overlay.dart';
import 'settings_screen.dart' show kAutoSizePerformKey;

/// Full-screen, large-print performance view for a single [Dance]
/// (`docs/design/ux.md` §5; ROADMAP 5.1). Entered explicitly from the dance
/// detail screen and exits back to it.
///
/// The large-print card body is the shared [PerformCard], so this single-dance
/// view and the program-mode Perform view render identically. Text size is
/// controlled in-view via [PerformSizeControls] with a large default and no
/// practical upper bound (a sensible lower bound is enforced). The active
/// dialect is applied via [ActiveDialectScope], with the same canonical ⇄
/// dialect toggle as the detail screen (hidden when the active dialect is
/// already [Dialect.canonical]).
class PerformDanceScreen extends StatefulWidget {
  const PerformDanceScreen({
    super.key,
    required this.dance,
    required this.renderer,
    this.authorNames = const [],
  });

  final Dance dance;
  final FigureRenderer renderer;

  /// Resolved author display names (the detail screen already resolves these
  /// from choreographer ids). Rendered under the title when non-empty.
  final List<String> authorNames;

  @override
  State<PerformDanceScreen> createState() => _PerformDanceScreenState();
}

class _PerformDanceScreenState extends State<PerformDanceScreen>
    with WidgetsBindingObserver, PerformWakelockMixin {
  /// Manual large-print text scale, applied when auto-size is off. Persisted
  /// across sessions (issue #449) and restored on entry so a caller's chosen
  /// size survives app relaunch instead of resetting to the default.
  double _textScale = kPerformDefaultScale;

  /// Auto-size the card to fit the viewport (ROADMAP G.1). Initialised from the
  /// General setting (on by default) in [didChangeDependencies]; mutable in-view
  /// via the auto-fit toggle and the A-/A+ controls without writing back to the
  /// global setting.
  bool _autoSize = true;

  /// Guards the one-shot settings load in [didChangeDependencies] (auto-size
  /// plus the persisted Perform a11y prefs) so it runs exactly once.
  bool _prefsLoaded = false;

  /// Persisted Perform a11y prefs store (issue #449), created once the
  /// [RepositoriesScope] is available in [didChangeDependencies].
  PerformA11yPrefsStore? _a11yPrefs;

  /// Set once the user changes auto-size in-view (toggle or A-/A+). Guards the
  /// async settings load from overwriting an in-session choice if the read
  /// completes after the user has already acted (a real race on slow first DB
  /// opens).
  bool _autoSizeUserSet = false;

  /// Per-pref equivalents of [_autoSizeUserSet]: once the caller changes a pref
  /// in-view, the async restore must not clobber that fresh choice.
  bool _textScaleUserSet = false;
  bool _stageModeUserSet = false;
  bool _canonicalUserSet = false;

  /// Dark-stage high-contrast theme, on by default (`docs/design/ux.md` §5).
  /// Persisted across sessions (issue #449) and restored on entry.
  bool _stageMode = true;

  /// When `true` figures render canonical role/move tokens; otherwise the
  /// user's active dialect. The toggle is hidden when the active dialect is
  /// already canonical (toggling would be a no-op). Persisted across sessions
  /// (issue #449) and restored on entry.
  bool _canonicalView = false;

  /// Whether the on-demand walkthrough overlay is currently shown (issue #370).
  /// Session-scoped and default OFF — the walkthrough must never cover the
  /// notation unless the caller asks for it — and deliberately NOT persisted
  /// across app restarts (consistent with the #373 toggle decision).
  bool _showWalkthrough = false;

  void _toggleWalkthrough() {
    setState(() => _showWalkthrough = !_showWalkthrough);
  }

  /// Whether the current dance has a non-empty walkthrough to show. The toggle
  /// and overlay are suppressed entirely when it is empty, so the caller never
  /// sees a dead control.
  bool get _hasWalkthrough => widget.dance.walkthrough.trim().isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    final settings = RepositoriesScope.of(context).settings;
    settings
        .get(kAutoSizePerformKey)
        .then((v) {
          // Don't clobber an in-view choice the user made before the read resolved.
          if (!mounted || _autoSizeUserSet) return;
          final enabled = v is bool ? v : true;
          if (enabled != _autoSize) setState(() => _autoSize = enabled);
        })
        .catchError((_) {
          // diagnostics: silent — auto-size pref read failed; keeps on-by-default value.
        });
    _a11yPrefs = PerformA11yPrefsStore(settings);
    _a11yPrefs!
        .load()
        .then((prefs) {
          if (!mounted) return;
          // Apply each restored pref unless the caller already changed it
          // in-view before the async read resolved.
          setState(() {
            if (!_textScaleUserSet) _textScale = prefs.textScale;
            if (!_stageModeUserSet) _stageMode = prefs.stageMode;
            if (!_canonicalUserSet) _canonicalView = prefs.canonicalView;
          });
        })
        .catchError((_) {
          // diagnostics: silent — a11y prefs load/parse failed; keeps defaults.
        });
  }

  void _persistTextScale() {
    _a11yPrefs
        ?.saveTextScale(_textScale)
        .catchError(
          (_) {},
        ); // diagnostics: silent — text-scale persist failed; best-effort.
  }

  void _persistStageMode() {
    _a11yPrefs
        ?.saveStageMode(_stageMode)
        .catchError(
          (_) {},
        ); // diagnostics: silent — stage-mode persist failed; best-effort.
  }

  void _persistCanonicalView() {
    _a11yPrefs
        ?.saveCanonicalView(_canonicalView)
        .catchError(
          (_) {},
        ); // diagnostics: silent — canonical-view persist failed; best-effort.
  }

  void _decreaseTextSize() {
    setState(() {
      // Using A-/A+ hands control back to the manual size (ROADMAP G.1).
      _autoSizeUserSet = true;
      _textScaleUserSet = true;
      _autoSize = false;
      _textScale = (_textScale - kPerformScaleStep).clamp(
        kPerformMinScale,
        double.infinity,
      );
    });
    _persistTextScale();
  }

  void _increaseTextSize() {
    setState(() {
      _autoSizeUserSet = true;
      _textScaleUserSet = true;
      _autoSize = false;
      _textScale += kPerformScaleStep;
    });
    _persistTextScale();
  }

  Future<void> _openMetronomeSheet() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const SafeArea(child: TapTempoMetronome()),
    );
  }

  /// Guards leaving Perform (issue #612, sibling of #434). A single stray tap
  /// on the close control — or a system back / predictive-back gesture — must
  /// not drop the caller out mid-dance, so we require a deliberate
  /// confirmation first. Mirrors [PerformProgramScreen]'s guard exactly,
  /// reusing the same dialog keys and l10n strings so the two Perform
  /// surfaces stay consistent.
  ///
  /// [_exitDialogShowing] prevents re-entrancy: without it, rapid taps on the
  /// close button (or repeated back gestures while the dialog is up) could
  /// stack multiple confirmation dialogs, letting a second confirm pop an
  /// extra screen. Only one dialog may be in flight at a time, and the flag
  /// is always cleared in `finally` so a later exit attempt isn't
  /// permanently blocked even if the dialog throws.
  bool _exitDialogShowing = false;

  Future<void> _confirmAndExit() async {
    if (_exitDialogShowing) return;
    _exitDialogShowing = true;
    try {
      final l10n = AppLocalizations.of(context);
      final navigator = Navigator.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('perform-exit-dialog'),
          title: Text(l10n.performExitTitle),
          content: Text(l10n.performExitBody),
          actions: [
            TextButton(
              key: const ValueKey('perform-exit-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.performExitCancel),
            ),
            FilledButton(
              key: const ValueKey('perform-exit-confirm'),
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.performExitConfirm),
            ),
          ],
        ),
      );
      // A direct pop (not `maybePop`) so it bypasses the PopScope in
      // [_guardExit] rather than re-triggering the confirmation.
      if (confirmed == true) navigator.pop();
    } finally {
      _exitDialogShowing = false;
    }
  }

  /// Wraps the Perform scaffold so an implicit pop (system back /
  /// predictive-back gesture) is intercepted and routed through the same
  /// [_confirmAndExit] confirmation as the close control (issue #612).
  Widget _guardExit({required Widget child}) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmAndExit();
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _buildContent(
        context,
        // Collapse the AppBar's secondary actions into an overflow menu on
        // narrow widths (issue #433). LayoutBuilder reflects the actual
        // laid-out width even where MediaQuery does not (e.g. setSurfaceSize
        // in widget tests).
        wide: constraints.maxWidth >= kPerformActionsCollapseWidth,
      ),
    );
  }

  Widget _buildContent(BuildContext context, {required bool wide}) {
    final l10n = AppLocalizations.of(context);
    final activeDialect = ActiveDialectScope.of(context);
    final isCanonicalDialect = activeDialect == Dialect.canonical;
    final dialect = _canonicalView ? Dialect.canonical : activeDialect;
    final canDecrease =
        _textScale - kPerformScaleStep >= kPerformMinScale - 1e-9;

    return ColourDanceTheme(
      title: widget.dance.title,
      child: PerformStageTheme(
        enabled: _stageMode,
        child: _guardExit(
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                key: const ValueKey('exit-perform'),
                tooltip: l10n.performExitTooltip,
                icon: const Icon(Icons.close),
                onPressed: _confirmAndExit,
              ),
              title: Text(l10n.performTitle),
              // Responsive AppBar actions (issue #433): full set inline on
              // tablets/large windows; secondary controls collapse into a "More
              // actions" overflow on narrow phones so the toolbar can't overflow.
              // The stage-mode toggle and per-gig dialect quick-switch stay inline.
              actions: buildPerformAppBarActions(
                wide: wide,
                leadingPrimary: const DialectQuickSwitch(),
                secondaryInline: [
                  if (_hasWalkthrough)
                    IconButton(
                      key: const ValueKey('perform-walkthrough-toggle'),
                      tooltip: l10n.performShowWalkthrough,
                      isSelected: _showWalkthrough,
                      icon: const Icon(Icons.menu_book_outlined),
                      selectedIcon: const Icon(Icons.menu_book),
                      onPressed: _toggleWalkthrough,
                    ),
                  IconButton(
                    key: const ValueKey('perform-metronome'),
                    tooltip: l10n.performTapTempo,
                    icon: const Icon(Icons.av_timer),
                    onPressed: _openMetronomeSheet,
                  ),
                  PerformSizeControls(
                    canDecrease: canDecrease,
                    onDecrease: _decreaseTextSize,
                    onIncrease: _increaseTextSize,
                  ),
                  PerformAutoSizeToggle(
                    autoSizeOn: _autoSize,
                    onChanged: (value) => setState(() {
                      _autoSizeUserSet = true;
                      _autoSize = value;
                    }),
                  ),
                  if (!isCanonicalDialect)
                    PerformDialectToggle(
                      canonical: _canonicalView,
                      onChanged: (value) {
                        setState(() {
                          _canonicalUserSet = true;
                          _canonicalView = value;
                        });
                        _persistCanonicalView();
                      },
                    ),
                ],
                overflowActions: [
                  if (_hasWalkthrough)
                    PerformMenuAction(
                      menuKey: const ValueKey(
                        'perform-walkthrough-toggle-menu',
                      ),
                      icon: Icons.menu_book,
                      label: l10n.performShowWalkthrough,
                      toggledOn: _showWalkthrough,
                      onSelected: _toggleWalkthrough,
                    ),
                  PerformMenuAction(
                    menuKey: const ValueKey('perform-metronome-menu'),
                    icon: Icons.av_timer,
                    label: l10n.performTapTempo,
                    onSelected: _openMetronomeSheet,
                  ),
                  PerformMenuAction(
                    menuKey: const ValueKey('decrease-text-size-menu'),
                    icon: Icons.text_decrease,
                    label: l10n.performDecreaseTextSize,
                    onSelected: _decreaseTextSize,
                    enabled: canDecrease,
                  ),
                  PerformMenuAction(
                    menuKey: const ValueKey('increase-text-size-menu'),
                    icon: Icons.text_increase,
                    label: l10n.performIncreaseTextSize,
                    onSelected: _increaseTextSize,
                  ),
                  PerformMenuAction(
                    menuKey: const ValueKey('perform-autosize-toggle-menu'),
                    icon: Icons.fit_screen,
                    label: l10n.performAutoSizeMenuLabel,
                    toggledOn: _autoSize,
                    onSelected: () => setState(() {
                      _autoSizeUserSet = true;
                      _autoSize = !_autoSize;
                    }),
                  ),
                  if (!isCanonicalDialect)
                    PerformMenuAction(
                      menuKey: const ValueKey('perform-dialect-toggle-menu'),
                      icon: Icons.groups,
                      label: l10n.performShowCanonicalTerms,
                      toggledOn: _canonicalView,
                      onSelected: () {
                        setState(() {
                          _canonicalUserSet = true;
                          _canonicalView = !_canonicalView;
                        });
                        _persistCanonicalView();
                      },
                    ),
                ],
                trailingPrimary: PerformStageToggle(
                  stageOn: _stageMode,
                  onChanged: (value) {
                    setState(() {
                      _stageModeUserSet = true;
                      _stageMode = value;
                    });
                    _persistStageMode();
                  },
                ),
              ),
            ),
            body: SafeArea(
              child: Stack(
                children: [
                  PerformCard(
                    dance: widget.dance,
                    renderer: widget.renderer,
                    dialect: dialect,
                    textScale: _textScale,
                    autoSize: _autoSize,
                    authorNames: widget.authorNames,
                  ),
                  // The walkthrough overlay is a sibling of the card — never a
                  // child routed through its `_FitToHeight` measurement — so
                  // showing it can't shrink or compete with the notation (#370).
                  if (_showWalkthrough && _hasWalkthrough)
                    Positioned.fill(
                      child: PerformWalkthroughOverlay(
                        walkthrough: widget.dance.walkthrough,
                        renderer: widget.renderer,
                        dialect: dialect,
                        onClose: _toggleWalkthrough,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
