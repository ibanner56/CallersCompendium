import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';
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
    with PerformWakelockMixin {
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

  @override
  Widget build(BuildContext context) {
    final activeDialect = ActiveDialectScope.of(context);
    final isCanonicalDialect = activeDialect == Dialect.canonical;
    final dialect = _canonicalView ? Dialect.canonical : activeDialect;
    final canDecrease =
        _textScale - kPerformScaleStep >= kPerformMinScale - 1e-9;

    return PerformStageTheme(
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
          actions: [
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
                onChanged: (value) => setState(() => _canonicalView = value),
              ),
            PerformStageToggle(
              stageOn: _stageMode,
              onChanged: (value) => setState(() => _stageMode = value),
            ),
            const SizedBox(width: 8),
          ],
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
    );
  }
}
