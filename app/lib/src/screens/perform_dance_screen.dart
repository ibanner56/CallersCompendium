import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import 'perform_card.dart';

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

class _PerformDanceScreenState extends State<PerformDanceScreen> {
  double _textScale = kPerformDefaultScale;

  /// When `true` figures render canonical role/move tokens; otherwise the
  /// user's active dialect. The toggle is hidden when the active dialect is
  /// already canonical (toggling would be a no-op).
  bool _canonicalView = false;

  void _decreaseTextSize() {
    setState(() {
      _textScale = (_textScale - kPerformScaleStep).clamp(
        kPerformMinScale,
        double.infinity,
      );
    });
  }

  void _increaseTextSize() {
    setState(() => _textScale += kPerformScaleStep);
  }

  @override
  Widget build(BuildContext context) {
    final activeDialect = ActiveDialectScope.of(context);
    final isCanonicalDialect = activeDialect == Dialect.canonical;
    final dialect = _canonicalView ? Dialect.canonical : activeDialect;
    final canDecrease =
        _textScale - kPerformScaleStep >= kPerformMinScale - 1e-9;

    return Scaffold(
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
          if (!isCanonicalDialect)
            PerformDialectToggle(
              canonical: _canonicalView,
              onChanged: (value) => setState(() => _canonicalView = value),
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
          authorNames: widget.authorNames,
        ),
      ),
    );
  }
}
