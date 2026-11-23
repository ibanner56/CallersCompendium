import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';
import '../search/facet_labels.dart';

/// The taxonomy the Glossary lists for [form]: the form's own figures, or
/// contra's for a form that has none of its own.
Taxonomy glossaryTaxonomy(DanceForm form) =>
    shippedTaxonomies.ownTaxonomy(form) ?? shippedTaxonomies.base;

/// The forms the Glossary can show: those with figures of their own, in
/// [DanceForm] order (ADR-006 W5).
List<DanceForm> get glossaryForms => [
  for (final form in DanceForm.values)
    if (glossaryTaxonomy(form).form == form) form,
];

/// The form the Glossary shows for [form]: itself, or contra's where it has
/// no figures of its own ([glossaryTaxonomy]).
DanceForm glossaryFormFor(DanceForm form) => glossaryTaxonomy(form).form;

/// The form whose dialect shows the walkthrough snippet stored under
/// [signature] (a figure signature, `moveId(...)`): its figure's form
/// (ADR-006 W5). Settings and a sync conflict on the snippets both use it.
DanceForm walkthroughSnippetForm(String signature) =>
    shippedTaxonomies.formOfMoveId(signature.split('(').first);

final Map<DanceForm, FigureRenderer> _renderers = {};

/// A renderer for the Glossary's figures of [form].
FigureRenderer glossaryRenderer(DanceForm form) => _renderers.putIfAbsent(
  form,
  () => FigureRenderer(shippedTaxonomies.forForm(form)),
);

/// The Glossary's built-in contra figures, derived from the taxonomy at
/// runtime and never stored.
final List<FigureGlossaryEntry> shippedFigureGlossaryEntries =
    figureGlossaryEntries(contraTaxonomy);

final Map<DanceForm, List<FigureGlossaryEntry>> _entriesByForm = {
  DanceForm.contra: shippedFigureGlossaryEntries,
};

/// The Glossary's built-in figures of [form] ([glossaryTaxonomy]). Only
/// contra's ship definitions so far.
List<FigureGlossaryEntry> shippedFigureGlossaryEntriesFor(DanceForm form) =>
    _entriesByForm.putIfAbsent(
      glossaryFormFor(form),
      () =>
          figureGlossaryEntries(glossaryTaxonomy(form), definitions: const {}),
    );

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
  Dialect dialect, {
  DanceForm form = DanceForm.contra,
}) {
  final renderer = glossaryRenderer(form);
  final taxonomy = glossaryTaxonomy(form);
  final name = renderer.displayMoveName(id, dialect);
  final alias = taxonomy.aliases[id];
  if (alias == null || alias.pinnedParams.isEmpty) return name;
  final collides = all.any(
    (other) =>
        other.id != id &&
        renderer.displayMoveName(other.id, dialect).toLowerCase() ==
            name.toLowerCase(),
  );
  if (!collides) return name;
  final target = taxonomy.moves[alias.targetMove]!;
  final detail = [
    for (final MapEntry(key: param, value: value) in alias.pinnedParams.entries)
      if (target.params[param] case final spec?)
        figureParamChoiceLabel(l10n, spec, dialect, '$value'),
  ].join(', ');
  return l10n.glossaryNameWithDetail(name, detail);
}
