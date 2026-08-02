import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Icons;

import '../../l10n/app_localizations.dart';

/// Localized labels for the facet enums, for chips and dropdowns.
///
/// The facet enums live in the Flutter-free `compendium_core` package
/// (ADR-001), so they cannot carry `AppLocalizations`-aware labels themselves;
/// UI routes through these app-side helpers (mirroring
/// `collection_query_labels.dart`). The deferred export path keeps English
/// wording via the `.label` extensions in `models/dance_list_entry.dart`.
String danceFormLabel(AppLocalizations l10n, DanceForm form) => switch (form) {
  DanceForm.contra => l10n.commonDanceFormContra,
  DanceForm.ecd => l10n.commonDanceFormEcd,
  DanceForm.square => l10n.commonDanceFormSquare,
};

/// A representative icon for a dance form, used for the Collection tile's
/// leading avatar. Always paired with a text label (form name) so meaning is
/// never carried by the glyph alone.
IconData danceFormIcon(DanceForm form) => switch (form) {
  DanceForm.contra => Icons.view_stream_outlined,
  DanceForm.ecd => Icons.groups_outlined,
  DanceForm.square => Icons.crop_square,
};

/// The one canonical glyph for the "formation" facet (the shape of the set:
/// duple, becket, triple, square, …). Deliberately **distinct** from the Matrix
/// feature's grid glyph (`Icons.grid_on_outlined`) so the two concepts never
/// read as the same thing. Always paired with a formation text label — meaning
/// is never carried by the glyph alone (`docs/research/accessibility-baseline.md`).
const IconData formationIcon = Icons.table_rows_outlined;

/// The one canonical glyph for "progression" (a figure/dance that advances
/// dancers to new neighbours). Replaces the earlier inconsistent mix of
/// `Icons.repeat` and a `¶` pilcrow across the UI. Always paired with a
/// "Progression" label/tooltip. (The plain-text and PDF exports keep the
/// typographic `¶` marker, which is a text artifact rather than a UI glyph.)
const IconData progressionIcon = Icons.repeat;

String progressionLabel(AppLocalizations l10n, Progression p) => switch (p) {
  Progression.none => l10n.commonProgressionNone,
  Progression.single => l10n.commonProgressionSingle,
  Progression.double => l10n.commonProgressionDouble,
  Progression.triple => l10n.commonProgressionTriple,
  Progression.quadruple => l10n.commonProgressionQuadruple,
  Progression.other => l10n.commonProgressionOther,
};

String danceStatusLabel(AppLocalizations l10n, DanceStatus s) => switch (s) {
  DanceStatus.active => l10n.commonDanceStatusActive,
  DanceStatus.deprecated => l10n.commonDanceStatusDeprecated,
  DanceStatus.broken => l10n.commonDanceStatusBroken,
};

/// Human-readable label for a difficulty [DanceLevel] (app UI string, not a
/// dialect term).
String danceLevelLabel(AppLocalizations l10n, DanceLevel level) =>
    switch (level) {
      DanceLevel.beginner => l10n.commonDanceLevelBeginner,
      DanceLevel.intermediate => l10n.commonDanceLevelIntermediate,
      DanceLevel.advanced => l10n.commonDanceLevelAdvanced,
    };

/// Localized label for a [FormationShape], for chips and filters.
String formationShapeLabel(AppLocalizations l10n, FormationShape shape) =>
    switch (shape) {
      FormationShape.dupleImproper => l10n.commonFormationDupleImproper,
      FormationShape.becketCw => l10n.commonFormationBecketCw,
      FormationShape.becketCcw => l10n.commonFormationBecketCcw,
      FormationShape.dupleProper => l10n.commonFormationDupleProper,
      FormationShape.dupleIndecent => l10n.commonFormationDupleIndecent,
      FormationShape.tripleMinor => l10n.commonFormationTripleMinor,
      FormationShape.threeFaceThree => l10n.commonFormationThreeFaceThree,
      FormationShape.fourFaceFour => l10n.commonFormationFourFaceFour,
      FormationShape.circleMixer => l10n.commonFormationCircleMixer,
      FormationShape.sicilianCircle => l10n.commonFormationSicilianCircle,
      FormationShape.scatterMixer => l10n.commonFormationScatterMixer,
      FormationShape.longways => l10n.commonFormationLongways,
      FormationShape.triplet => l10n.commonFormationTriplet,
      FormationShape.grid => l10n.commonFormationGrid,
      FormationShape.other => l10n.commonFormationOther,
    };

/// Full formation label, including free-text [Formation.detail] if present.
/// The detail is untrusted user text; it flows through a gen-l10n placeholder
/// and is rendered as plain text by the caller.
String formationLabel(AppLocalizations l10n, Formation formation) {
  final base = formationShapeLabel(l10n, formation.shape);
  final detail = formation.detail?.trim();
  return (detail == null || detail.isEmpty)
      ? base
      : l10n.commonFormationWithDetail(base, detail);
}

/// Turns `role1s` → `role1s`, `rightDiagonal` → `right diagonal`,
/// `threeQuarter` → `three quarter` for display.
///
/// Lives here rather than beside the figure param editor because it is the
/// shared presentation primitive for figure-param vocabulary: the dance editor
/// and the Advanced-search facet must label the same canonical token the same
/// way (issue #741). `figure_param_editors.dart` re-exports it so its existing
/// importers are unaffected.
String humanizeToken(String token) => token
    .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
    .toLowerCase();

/// The discrete, pickable value vocabulary for a figure parameter, or `null`
/// when the parameter has no closed vocabulary (rotation/beats/text). Used to
/// offer optional param dropdowns on an Advanced "has figure" row.
///
/// `spec.choices`, when present, IS the domain — for every kind that has one.
/// A spec may narrow its kind's fixed vocabulary, or opt into the
/// [ParamVocab.unspecified] sentinel, and this facet must offer exactly what
/// [ParamSpec.validate] accepts and `FigureParamEditor` renders: the three are
/// consumers of one contract and must not disagree about a param's domain
/// (issue #726 / PR #736 taught the other two this same rule; this is the
/// third). Offering the fixed vocabulary instead lets a search row build a
/// filter for a value the param cannot hold — and silently drops a sentinel
/// the user needs to search for. A spec that omits `choices` keeps exactly the
/// kind's fixed vocabulary, i.e. today's behaviour.
List<String>? figureParamChoices(ParamSpec spec) {
  switch (spec.kind) {
    case ParamKind.dancerSet:
    case ParamKind.dancerPair:
      return spec.choices ?? ParamVocab.dancerSets;
    case ParamKind.handedness:
    case ParamKind.shoulder:
      return spec.choices ?? ParamVocab.sides;
    case ParamKind.spinDirection:
      return spec.choices ?? ParamVocab.spins;
    case ParamKind.fraction:
      return spec.choices ?? ParamVocab.fractions;
    case ParamKind.direction:
      return spec.choices ?? ParamVocab.directions;
    case ParamKind.choice:
      return spec.choices;
    case ParamKind.rotation:
    case ParamKind.places:
    case ParamKind.beats:
    case ParamKind.text:
    case ParamKind.flag:
      return null;
  }
}

/// Whether [spec] admits the [ParamVocab.unspecified] sentinel, i.e. whether
/// "the source stated nothing here" is a representable state for this param.
bool paramAdmitsUnspecified(ParamSpec spec) =>
    spec.choices?.contains(ParamVocab.unspecified) ?? false;

/// The values a *user may pick* for a figure parameter: its [domain] minus the
/// [ParamVocab.unspecified] sentinel.
///
/// Deliberately distinct from the domain. The sentinel is a real, valid value —
/// [ParamSpec.validate] accepts it, [figureParamChoices] reports it, and the
/// renderer knows how to emit it — but it is meaningless as something a user
/// *chooses*: it means the SOURCE stated nothing, which is a fact about
/// provenance, not a choreographic value anyone sets on purpose. In search it
/// is worse than meaningless, because it sits next to "Any <param>", reads like
/// a synonym, and filters for the near-inverse set (issue #741).
///
/// So the sentinel is filtered out *here*, at the presentation edge, and never
/// in [figureParamChoices] or [ParamSpec.validate]: those two plus the editor
/// are the three consumers of one domain contract (issue #726 / PR #746) and
/// must not start disagreeing about what a param can hold.
List<String> figureParamSelectableChoices(List<String> domain) => [
  for (final choice in domain)
    if (choice != ParamVocab.unspecified) choice,
];

/// Human-readable label for a figure parameter's KEY (`meetTarget` -> "meet
/// target"), for field labels and the facet's "Any <param>" option.
///
/// The taxonomy carries no display name for a param key ([ParamSpec] has no
/// `label`), and it declares dozens of them, so per-key localized strings would
/// be a large, silently-degrading table — a param added to the taxonomy would
/// fall back to the raw identifier. Humanizing is what the dance editor already
/// does for the very same keys, so this keeps the two surfaces identical. Named
/// separately from [humanizeToken] so a future localized table has exactly one
/// call site to replace.
String figureParamKeyLabel(String paramKey) => humanizeToken(paramKey);

/// Display label for a single figure-param [choice].
///
/// THE one labelling path for figure-param vocabulary, shared by the dance
/// editor's `FigureParamEditor` and the Advanced-search facet's param
/// dropdowns. Extracted so the two cannot drift: before issue #741 the facet
/// rendered raw canonical tokens (`role1s`) while the editor rendered the same
/// token through the user's dialect ("Larks" / "Gents").
///
/// Dancer sets/pairs are dialect vocabulary and route through
/// [FigureRenderer.displayToken]; every other kind is structural vocabulary and
/// is humanized. The stored value is always the canonical token regardless of
/// the label shown.
String figureParamChoiceLabel(
  AppLocalizations l10n,
  ParamSpec spec,
  Dialect dialect,
  String choice,
) {
  // Defensive: the sentinel is filtered out of every pickable list by
  // [figureParamSelectableChoices], so this branch is only reached when
  // labelling a param's CURRENT unstated state — never a menu entry. Gated on
  // the spec admitting it so a free-`text` param whose value happens to be the
  // word "unspecified" is still shown verbatim.
  if (choice == ParamVocab.unspecified && paramAdmitsUnspecified(spec)) {
    return l10n.danceEditorParamNotStated;
  }
  final isDancerKind =
      spec.kind == ParamKind.dancerSet || spec.kind == ParamKind.dancerPair;
  return isDancerKind
      ? FigureRenderer.displayToken(choice, spec, dialect)
      : humanizeToken(choice);
}
