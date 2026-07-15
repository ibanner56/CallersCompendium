import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import '../models/dance_list_entry.dart';
import '../search/facet_labels.dart';

/// Full-screen, large-print performance view for a single [Dance]
/// (`docs/design/ux.md` §5; ROADMAP 5.1). Entered explicitly from the dance
/// detail screen and exits back to it.
///
/// The view reuses the same correctness path as the detail card — core
/// [deriveSections] for phrase grouping and [FigureRenderer.render] for the
/// dialect-applied figure text — so the two stay consistent, while rendering
/// its own large-print layout.
///
/// Text size is controlled in-view via A-/A+ controls with a large default and
/// no practical upper bound (a sensible lower bound is enforced). This in-view
/// state is sufficient for 5.1; cross-session persistence to settings is a
/// later follow-up. The active dialect is applied via [ActiveDialectScope],
/// with the same canonical ⇄ dialect toggle as the detail screen (hidden when
/// the active dialect is already [Dialect.canonical]).
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
  /// Large default so the card reads from across a room on first open.
  static const double _defaultScale = 1.8;

  /// A sensible lower bound (below the app's normal text size the "large-print"
  /// intent is lost). There is deliberately no practical upper bound.
  static const double _minScale = 1.0;

  static const double _scaleStep = 0.2;

  double _textScale = _defaultScale;

  /// When `true` figures render canonical role/move tokens; otherwise the
  /// user's active dialect. The toggle is hidden when the active dialect is
  /// already canonical (toggling would be a no-op).
  bool _canonicalView = false;

  void _decreaseTextSize() {
    setState(() {
      _textScale = (_textScale - _scaleStep).clamp(_minScale, double.infinity);
    });
  }

  void _increaseTextSize() {
    setState(() => _textScale += _scaleStep);
  }

  @override
  Widget build(BuildContext context) {
    final dance = widget.dance;
    final activeDialect = ActiveDialectScope.of(context);
    final isCanonicalDialect = activeDialect == Dialect.canonical;
    final dialect = _canonicalView ? Dialect.canonical : activeDialect;

    final canDecrease = _textScale - _scaleStep >= _minScale - 1e-9;

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
          IconButton(
            key: const ValueKey('decrease-text-size'),
            tooltip: 'Decrease text size',
            icon: const Icon(Icons.text_decrease),
            onPressed: canDecrease ? _decreaseTextSize : null,
          ),
          IconButton(
            key: const ValueKey('increase-text-size'),
            tooltip: 'Increase text size',
            icon: const Icon(Icons.text_increase),
            onPressed: _increaseTextSize,
          ),
          if (!isCanonicalDialect)
            _DialectToggle(
              canonical: _canonicalView,
              onChanged: (value) => setState(() => _canonicalView = value),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_textScale)),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(dance: dance, authorNames: widget.authorNames),
                const SizedBox(height: 24),
                _Figures(
                  figures: dance.figures,
                  phraseStructure: dance.phraseStructure,
                  renderer: widget.renderer,
                  dialect: dialect,
                ),
                if (dance.callingNotes.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _SectionTitle('Calling notes'),
                  const SizedBox(height: 8),
                  Text(
                    widget.renderer.renderFreeText(dance.callingNotes, dialect),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.dance, required this.authorNames});

  final Dance dance;
  final List<String> authorNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          const SizedBox(height: 8),
          Text(authorNames.join(', '), style: theme.textTheme.headlineSmall),
        ],
        const SizedBox(height: 12),
        _MetaRow(icon: Icons.grid_view, text: formationLabel(dance.formation)),
        if (level != null) ...[
          const SizedBox(height: 8),
          _MetaRow(
            icon: Icons.signal_cellular_alt,
            text: danceLevelLabel(level),
          ),
        ],
        if (dance.status != DanceStatus.active) ...[
          const SizedBox(height: 16),
          _StatusBanner(status: dance.status),
        ],
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineSmall;
    final iconSize =
        (style?.fontSize ?? 24) * MediaQuery.textScalerOf(context).scale(1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: iconSize.clamp(24.0, 96.0)),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: style)),
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
        style: theme.textTheme.headlineMedium?.copyWith(
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
      return Text('No figures yet.', style: theme.textTheme.headlineSmall);
    }

    final sectioned = deriveSections(figures, phraseStructure);
    final children = <Widget>[];
    String? lastLabel;
    for (final sf in sectioned) {
      if (sf.label != lastLabel) {
        children.add(
          Padding(
            padding: EdgeInsets.only(
              top: lastLabel == null ? 0 : 20,
              bottom: 8,
            ),
            child: Semantics(
              header: true,
              child: Text(
                sf.label,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        );
        lastLabel = sf.label;
      }
      children.add(
        _FigureRow(
          text: renderer.render(sf.figure, dialect),
          beats: sf.figure.beats,
          progression: sf.figure.progression,
          note: sf.figure.note,
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
    required this.beats,
    required this.progression,
    required this.note,
  });

  final String text;
  final int beats;
  final bool progression;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beatsLabel = '$beats ${beats == 1 ? 'beat' : 'beats'}';
    final semanticsLabel = [
      text,
      if (progression) 'progression',
      beatsLabel,
      if (note != null && note!.trim().isNotEmpty) 'note: ${note!.trim()}',
    ].join(', ');
    final textStyle = theme.textTheme.headlineSmall;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: progression
                  ? Tooltip(
                      message: 'Progression',
                      child: Text(
                        '¶',
                        style: textStyle?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: textStyle),
                  if (note != null && note!.trim().isNotEmpty)
                    Text(
                      note!.trim(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
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
}

/// Mirrors the detail screen's canonical ⇄ dialect toggle so the Perform view
/// offers the same quick-switch behavior.
class _DialectToggle extends StatelessWidget {
  const _DialectToggle({required this.canonical, required this.onChanged});

  final bool canonical;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Show canonical terms',
      toggled: canonical,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Canonical'),
          Switch(
            key: const ValueKey('perform-dialect-toggle'),
            value: canonical,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final DanceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (status) {
      DanceStatus.broken => (Icons.error_outline, theme.colorScheme.error),
      DanceStatus.deprecated => (
        Icons.warning_amber,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: iconSize.clamp(22.0, 72.0), color: color),
          const SizedBox(width: 10),
          Text(danceStatusLabel(status), style: style),
        ],
      ),
    );
  }
}
