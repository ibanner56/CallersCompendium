import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';
import '../widgets/colour_dance_theme.dart';
import '../widgets/dialect_quick_switch.dart';
import '../widgets/tap_tempo_metronome.dart';
import 'perform_card.dart';
import 'perform_wakelock.dart';
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
  double _textScale = kPerformDefaultScale;

  /// Auto-size the card to fit the viewport (ROADMAP G.1). Initialised from the
  /// General setting (on by default) in [didChangeDependencies]; mutable in-view
  /// via the auto-fit toggle and the A-/A+ controls without writing back to the
  /// global setting.
  bool _autoSize = true;
  bool _autoSizeLoaded = false;

  /// Set once the user changes auto-size in-view (toggle or A-/A+). Guards the
  /// async settings load from overwriting an in-session choice if the read
  /// completes after the user has already acted (a real race on slow first DB
  /// opens).
  bool _autoSizeUserSet = false;

  /// Dark-stage high-contrast theme, on by default (`docs/design/ux.md` §5). In
  /// view only; persistence to Settings is a documented later follow-up.
  bool _stageMode = true;

  /// When `true` figures render canonical role/move tokens; otherwise the
  /// user's active dialect. The toggle is hidden when the active dialect is
  /// already canonical (toggling would be a no-op).
  bool _canonicalView = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoSizeLoaded) return;
    _autoSizeLoaded = true;
    RepositoriesScope.of(context).settings
        .get(kAutoSizePerformKey)
        .then((v) {
          // Don't clobber an in-view choice the user made before the read resolved.
          if (!mounted || _autoSizeUserSet) return;
          final enabled = v is bool ? v : true;
          if (enabled != _autoSize) setState(() => _autoSize = enabled);
        })
        .catchError((_) {
          // Read failure: keep the on-by-default value; nothing to restore.
        });
  }

  void _decreaseTextSize() {
    setState(() {
      // Using A-/A+ hands control back to the manual size (ROADMAP G.1).
      _autoSizeUserSet = true;
      _autoSize = false;
      _textScale = (_textScale - kPerformScaleStep).clamp(
        kPerformMinScale,
        double.infinity,
      );
    });
  }

  void _increaseTextSize() {
    setState(() {
      _autoSizeUserSet = true;
      _autoSize = false;
      _textScale += kPerformScaleStep;
    });
  }

  Future<void> _openMetronomeSheet() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const SafeArea(child: TapTempoMetronome()),
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
    final activeDialect = ActiveDialectScope.of(context);
    final isCanonicalDialect = activeDialect == Dialect.canonical;
    final dialect = _canonicalView ? Dialect.canonical : activeDialect;
    final canDecrease =
        _textScale - kPerformScaleStep >= kPerformMinScale - 1e-9;

    return ColourDanceTheme(
      title: widget.dance.title,
      child: PerformStageTheme(
        enabled: _stageMode,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              key: const ValueKey('exit-perform'),
              tooltip: 'Exit performance view',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('Perform'),
            // Responsive AppBar actions (issue #433): full set inline on
            // tablets/large windows; secondary controls collapse into a "More
            // actions" overflow on narrow phones so the toolbar can't overflow.
            // The stage-mode toggle and per-gig dialect quick-switch stay inline.
            actions: buildPerformAppBarActions(
              wide: wide,
              leadingPrimary: const DialectQuickSwitch(),
              secondaryInline: [
                IconButton(
                  key: const ValueKey('perform-metronome'),
                  tooltip: 'Tap tempo',
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
                    onChanged: (value) =>
                        setState(() => _canonicalView = value),
                  ),
              ],
              overflowActions: [
                PerformMenuAction(
                  menuKey: const ValueKey('perform-metronome-menu'),
                  icon: Icons.av_timer,
                  label: 'Tap tempo',
                  onSelected: _openMetronomeSheet,
                ),
                PerformMenuAction(
                  menuKey: const ValueKey('decrease-text-size-menu'),
                  icon: Icons.text_decrease,
                  label: 'Decrease text size',
                  onSelected: _decreaseTextSize,
                  enabled: canDecrease,
                ),
                PerformMenuAction(
                  menuKey: const ValueKey('increase-text-size-menu'),
                  icon: Icons.text_increase,
                  label: 'Increase text size',
                  onSelected: _increaseTextSize,
                ),
                PerformMenuAction(
                  menuKey: const ValueKey('perform-autosize-toggle-menu'),
                  icon: Icons.fit_screen,
                  label: 'Auto-size text to screen',
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
                    label: 'Show canonical terms',
                    toggledOn: _canonicalView,
                    onSelected: () =>
                        setState(() => _canonicalView = !_canonicalView),
                  ),
              ],
              trailingPrimary: PerformStageToggle(
                stageOn: _stageMode,
                onChanged: (value) => setState(() => _stageMode = value),
              ),
            ),
          ),
          body: SafeArea(
            child: PerformCard(
              dance: widget.dance,
              renderer: widget.renderer,
              dialect: dialect,
              textScale: _textScale,
              autoSize: _autoSize,
              authorNames: widget.authorNames,
            ),
          ),
        ),
      ),
    );
  }
}
