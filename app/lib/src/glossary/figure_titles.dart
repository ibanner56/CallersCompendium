import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';
import '../search/facet_labels.dart';

final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

/// The Glossary's built-in figures, derived from the taxonomy at runtime and
/// never stored.
final List<FigureGlossaryEntry> shippedFigureGlossaryEntries =
    figureGlossaryEntries(contraTaxonomy);

/// The name the built-in figure [id] is listed and headed by in the Glossary
/// under [dialect].
///
/// Usually the figure's dialect name. When another entry in [all] shares that
/// name — the two `pull by` aliases share it with `pull by` itself — an alias
/// is qualified by the values it pins (`pull by (neighbors)`), so no two rows
/// read the same. Shared with anything else that names a figure the way the
/// Glossary does, such as a sync conflict on the user's notes on it (#709).
String glossaryFigureTitle(
  AppLocalizations l10n,
  String id,
  List<FigureGlossaryEntry> all,
  Dialect dialect,
) {
  final name = _renderer.displayMoveName(id, dialect);
  final alias = contraTaxonomy.aliases[id];
  if (alias == null || alias.pinnedParams.isEmpty) return name;
  final collides = all.any(
    (other) =>
        other.id != id &&
        _renderer.displayMoveName(other.id, dialect).toLowerCase() ==
            name.toLowerCase(),
  );
  if (!collides) return name;
  final target = contraTaxonomy.moves[alias.targetMove]!;
  final detail = [
    for (final MapEntry(key: param, value: value) in alias.pinnedParams.entries)
      if (target.params[param] case final spec?)
        figureParamChoiceLabel(l10n, spec, dialect, '$value'),
  ].join(', ');
  return l10n.glossaryNameWithDetail(name, detail);
}
