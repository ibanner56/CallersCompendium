import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../models/dance_list_entry.dart';
import '../search/facet_labels.dart';
import '../theme/app_theme.dart';

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
    this.authorNames = const [],
  });

  final Dance dance;
  final FigureRenderer renderer;
  final Dialect dialect;
  final double textScale;

  /// Resolved author display names, rendered under the title when non-empty.
  final List<String> authorNames;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: _effectiveScaler(context, textScale),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(dance: dance, authorNames: authorNames),
            const SizedBox(height: 24),
            _Figures(
              figures: dance.figures,
              phraseStructure: dance.phraseStructure,
              renderer: renderer,
              dialect: dialect,
            ),
            if (dance.callingNotes.isNotEmpty) ...[
              const SizedBox(height: 28),
              _SectionTitle('Calling notes'),
              const SizedBox(height: 8),
              Text(
                renderer.renderFreeText(dance.callingNotes, dialect),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ],
        ),
      ),
    );
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
  });

  final String text;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: _effectiveScaler(context, textScale),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('decrease-text-size'),
          tooltip: 'Decrease text size',
          icon: const Icon(Icons.text_decrease),
          onPressed: canDecrease ? onDecrease : null,
        ),
        IconButton(
          key: const ValueKey('increase-text-size'),
          tooltip: 'Increase text size',
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
    // Exclude the decorative "Canonical" label from semantics and attach the
    // accessible name to the Switch itself (merged into one node) so assistive
    // tech announces a single "Show canonical terms" toggle rather than the
    // label text and the switch separately.
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ExcludeSemantics(child: Text('Canonical')),
          Semantics(
            label: 'Show canonical terms',
            child: Switch(
              key: const ValueKey('perform-dialect-toggle'),
              value: canonical,
              onChanged: onChanged,
            ),
          ),
        ],
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
    final tooltip = stageOn
        ? 'Stage theme on — tap to use app theme'
        : 'Stage theme off — tap for dark stage';
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
          verboseText: renderer.renderVerbose(sf.figure, dialect),
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
    required this.verboseText,
    required this.beats,
    required this.progression,
    required this.note,
  });

  /// Terse, dialect-applied text shown on screen.
  final String text;

  /// Verbose, spoken-friendly rendering announced to assistive tech in place of
  /// the terse [text] (figure-taxonomy.md §5.4 / accessibility baseline).
  final String verboseText;
  final int beats;
  final bool progression;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beatsLabel = '$beats ${beats == 1 ? 'beat' : 'beats'}';
    final semanticsLabel = [
      verboseText,
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
