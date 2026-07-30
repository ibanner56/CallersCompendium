import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The user's choice for a single seedable shorthand candidate: whether to
/// include it and, when the button has a distinct alternate call, which
/// expansion (primary or alt) to seed.
class _SeedChoice {
  _SeedChoice({required this.include, required this.useAlt});

  bool include;
  bool useAlt;
}

/// Opt-in, previewed step that seeds figure shorthands from a Caller's
/// Companion file's `InsertCall` call buttons (issue #562).
///
/// Presents each parseable candidate with its token and a live preview of the
/// figure(s) it expands to; where the button carries a *distinct* alternate
/// call, the user can toggle between the primary and alternate expansion for the
/// SAME token (only one mapping is ever seeded per token). Candidates whose
/// token already names an existing shorthand are surfaced in a read-only
/// "already defined — skipped" section — never overwritten.
///
/// Returns, via [Navigator.pop], the chosen [ShorthandMapping]s to add (empty /
/// `null` when the user skips — declining seeds nothing).
class ImportShorthandSeedScreen extends StatefulWidget {
  const ImportShorthandSeedScreen({
    super.key,
    required this.seedable,
    required this.conflicting,
    required this.dialect,
  });

  /// Candidates whose token is free to add.
  final List<ShorthandSeedCandidate> seedable;

  /// Candidates whose token already exists (surfaced, not seeded).
  final List<ShorthandSeedCandidate> conflicting;

  /// The active dialect used to render the figure previews.
  final Dialect dialect;

  @override
  State<ImportShorthandSeedScreen> createState() =>
      _ImportShorthandSeedScreenState();
}

class _ImportShorthandSeedScreenState extends State<ImportShorthandSeedScreen> {
  late final List<_SeedChoice> _choices;
  final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

  @override
  void initState() {
    super.initState();
    // Seedable candidates default to selected (the whole step is opt-in — the
    // user can still Skip wholesale — but pre-selecting the parseable buttons
    // saves a tap for the common "yes, seed them" case).
    _choices = [
      for (final _ in widget.seedable)
        _SeedChoice(include: true, useAlt: false),
    ];
  }

  int get _selectedCount => _choices.where((c) => c.include).length;

  /// Renders a candidate's expansion into a single-line preview via the active
  /// dialect, e.g. "neighbors swing → circle left ¾".
  String _preview(List<Figure> figures) =>
      figures.map((f) => _renderer.render(f, widget.dialect)).join(' → ');

  void _skip() => Navigator.of(context).pop(<ShorthandMapping>[]);

  void _confirm() {
    final chosen = <ShorthandMapping>[];
    for (var i = 0; i < widget.seedable.length; i++) {
      final choice = _choices[i];
      if (!choice.include) continue;
      final candidate = widget.seedable[i];
      chosen.add(
        choice.useAlt && candidate.hasAlt
            ? candidate.toAltMapping()
            : candidate.toPrimaryMapping(),
      );
    }
    Navigator.of(context).pop(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importShorthandSeedTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.importShorthandSeedIntro,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (widget.seedable.isNotEmpty) ...[
            _SectionHeader(l10n.importShorthandSeedAvailableHeader),
            for (var i = 0; i < widget.seedable.length; i++)
              _SeedableTile(
                key: ValueKey(
                  'seed-tile-${widget.seedable[i].normalizedToken}',
                ),
                candidate: widget.seedable[i],
                choice: _choices[i],
                preview: _preview,
                onChanged: () => setState(() {}),
              ),
          ],
          if (widget.conflicting.isNotEmpty) ...[
            _SectionHeader(l10n.importShorthandSeedConflictHeader),
            for (final candidate in widget.conflicting)
              ListTile(
                key: ValueKey('seed-conflict-${candidate.normalizedToken}'),
                enabled: false,
                leading: const Icon(Icons.block),
                title: Text(candidate.token),
                subtitle: Text(
                  l10n.importShorthandSeedConflictNote(candidate.token),
                ),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                key: const ValueKey('seed-skip'),
                onPressed: _skip,
                child: Text(l10n.importShorthandSeedSkip),
              ),
              FilledButton(
                key: const ValueKey('seed-confirm'),
                onPressed: _selectedCount == 0 ? null : _confirm,
                child: Text(l10n.importShorthandSeedConfirm(_selectedCount)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// One seedable candidate: an include checkbox, its token, a live figure
/// preview, and — when the button has a distinct alternate call — a
/// primary/alternate toggle that flips which expansion is previewed and seeded.
class _SeedableTile extends StatelessWidget {
  const _SeedableTile({
    super.key,
    required this.candidate,
    required this.choice,
    required this.preview,
    required this.onChanged,
  });

  final ShorthandSeedCandidate candidate;
  final _SeedChoice choice;
  final String Function(List<Figure>) preview;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final figures = choice.useAlt && candidate.hasAlt
        ? candidate.altFigures!
        : candidate.figures;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          key: ValueKey('seed-check-${candidate.normalizedToken}'),
          value: choice.include,
          onChanged: (value) {
            choice.include = value ?? false;
            onChanged();
          },
          title: Text(candidate.token),
          subtitle: Text(preview(figures)),
        ),
        if (candidate.hasAlt)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: SegmentedButton<bool>(
              key: ValueKey('seed-alt-toggle-${candidate.normalizedToken}'),
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l10n.importShorthandSeedUsePrimary),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(l10n.importShorthandSeedUseAlt),
                ),
              ],
              selected: {choice.useAlt},
              onSelectionChanged: (selection) {
                choice.useAlt = selection.first;
                onChanged();
              },
            ),
          ),
      ],
    );
  }
}
