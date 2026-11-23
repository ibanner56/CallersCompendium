import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Icons;

import '../../l10n/app_localizations.dart';

// `figureParamChoices` and `figureParamSelectableChoices` live in
// compendium_core (#2325) so a saved search can judge a stored figure parameter
// by the same rule as the panel; re-exported for this file's importers.
export 'package:compendium_core/compendium_core.dart'
    show figureParamChoices, figureParamSelectableChoices;

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

/// A glossary entry's stored dance [form]'s label (#1023), or [form] as
/// written for one a later build added.
String glossaryEntryFormLabel(AppLocalizations l10n, String form) {
  for (final value in DanceForm.values) {
    if (value.name == form) return danceFormLabel(l10n, value);
  }
  return form;
}

/// A representative icon for a dance form, used for the Collection tile's
/// leading avatar. Always paired with a text label (form name) so meaning is
/// never carried by the glyph alone.
IconData danceFormIcon(DanceForm form) => switch (form) {
  DanceForm.contra => Icons.view_stream_outlined,
  DanceForm.ecd => Icons.diversity_3_outlined,
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

/// The dance's authors with the year it was composed, as one line for the
/// dance detail screen and the Perform card: "Pat Shaw (1951)", the names
/// alone without a [composedOn], "Composed 1651" without names, and null with
/// neither. Only the year is shown, whatever else [composedOn] holds; the
/// editor keeps the month and day.
String? authorsWithYearLabel(
  AppLocalizations l10n,
  List<String> authorNames,
  PartialDate? composedOn,
) {
  final names = authorNames.join(', ');
  final year = composedOn?.year.toString();
  return switch ((names.isEmpty, year)) {
    (true, null) => null,
    (false, null) => names,
    (true, final year?) => l10n.danceComposedYear(year),
    (false, final year?) => l10n.danceAuthorsWithYear(names, year),
  };
}

/// Who interpreted the dance and when, as one line for the dance detail
/// screen and the Perform card: "Interpreted by Cecil Sharp (1916)", without
/// the year or the names when either is missing, and null with neither.
String? interpretersWithYearLabel(
  AppLocalizations l10n,
  List<String> interpreterNames,
  PartialDate? interpretedOn,
) {
  final names = interpreterNames.join(', ');
  final year = interpretedOn?.year.toString();
  return switch ((names.isEmpty, year)) {
    (true, null) => null,
    (false, null) => l10n.danceInterpretedBy(names),
    (true, final year?) => l10n.danceInterpretedYear(year),
    (false, final year?) => l10n.danceInterpretedByWithYear(names, year),
  };
}

/// The glyph for a dance's Barnes reference (where its tune is printed in the
/// Barnes books). Always paired with the labelled reference text.
const IconData barnesReferenceIcon = Icons.menu_book_outlined;

/// The glyph for a dance's tune details (meter and key). Always paired with
/// the labelled [meterAndKeyLabel] text, never shown alone.
const IconData tuneDetailsIcon = Icons.music_note_outlined;

/// A dance's meter and key as one labelled line, such as
/// "Meter: 6/8 · Key: G minor", for the dance detail screen and the Perform
/// card. Either part is left out when blank (after trimming); null when both
/// are. [render] is applied to each typed value, not to the labels, so a
/// caller can pass the dance's discouraged-term rendering.
String? meterAndKeyLabel(
  AppLocalizations l10n,
  Dance dance, {
  String Function(String value)? render,
}) {
  final meter = dance.meter.trim();
  final key = dance.musicalKey.trim();
  String shown(String value) => render == null ? value : render(value);
  final parts = [
    if (meter.isNotEmpty) l10n.danceMeterValue(shown(meter)),
    if (key.isNotEmpty) l10n.danceMusicalKeyValue(shown(key)),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

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
  DanceStatus.draft => l10n.commonDanceStatusDraft,
  DanceStatus.variation => l10n.commonDanceStatusVariation,
};

/// Human-readable label for a difficulty level (app UI string, not a dialect
/// term). Shipped levels retain localization; custom labels are user data.
String danceLevelLabel(AppLocalizations l10n, DifficultyLevel level) {
  if (level.id == DifficultyLevel.beginnerId &&
      level.label == DifficultyLevel.beginner.label) {
    return l10n.commonDanceLevelBeginner;
  }
  if (level.id == DifficultyLevel.intermediateId &&
      level.label == DifficultyLevel.intermediate.label) {
    return l10n.commonDanceLevelIntermediate;
  }
  if (level.id == DifficultyLevel.advancedId &&
      level.label == DifficultyLevel.advanced.label) {
    return l10n.commonDanceLevelAdvanced;
  }
  return level.label;
}

/// Localized label for a [FormationShape], for chips and filters.
String formationShapeLabel(
  AppLocalizations l10n,
  FormationShape shape,
) => switch (shape) {
  FormationShape.dupleImproper => l10n.commonFormationDupleImproper,
  FormationShape.progressedImproper => l10n.commonFormationProgressedImproper,
  FormationShape.reverseProgressionImproper =>
    l10n.commonFormationReverseProgressionImproper,
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
  FormationShape.quadruplet => l10n.commonFormationQuadruplet,
  FormationShape.other => l10n.commonFormationOther,
  FormationShape.dupleMinor => l10n.commonFormationDupleMinor,
  FormationShape.threeCoupleLongways => l10n.commonFormationThreeCoupleLongways,
  FormationShape.fourCoupleLongways => l10n.commonFormationFourCoupleLongways,
  FormationShape.fiveCoupleLongways => l10n.commonFormationFiveCoupleLongways,
  FormationShape.sixCoupleLongways => l10n.commonFormationSixCoupleLongways,
  FormationShape.circle => l10n.commonFormationCircle,
  FormationShape.square => l10n.commonFormationSquare,
  FormationShape.twoCoupleSet => l10n.commonFormationTwoCoupleSet,
};

/// The shape's label, marked improper when ECD's proper/improper checkbox is
/// set (ADR-006 §12, F2). A contra dance never sets it: its shape already says
/// proper or improper.
String _shapeWithImproper(AppLocalizations l10n, Formation formation) {
  final shape = formationShapeLabel(l10n, formation.shape);
  return formation.improper ? l10n.commonFormationImproperFlag(shape) : shape;
}

/// Full formation label, including free-text [Formation.detail] if present.
/// The detail is untrusted user text; it flows through a gen-l10n placeholder
/// and is rendered as plain text by the caller.
String formationLabel(AppLocalizations l10n, Formation formation) {
  final base = _shapeWithImproper(l10n, formation);
  final detail = formation.detail?.trim();
  return (detail == null || detail.isEmpty)
      ? base
      : l10n.commonFormationWithDetail(base, detail);
}

/// Full formation label with the detail rendered through the active dialect.
String formationDisplayLabel(
  AppLocalizations l10n,
  Formation formation,
  FigureRenderer renderer,
  Dialect dialect, {
  required bool canonicalizeDiscouragedTerms,
}) {
  final base = _shapeWithImproper(l10n, formation);
  final detail = formation.detail?.trim();
  if (detail == null || detail.isEmpty) return base;
  final renderedDetail = canonicalizeDiscouragedTerms
      ? renderer.renderFreeTextWithCanonicalDiscouragedTerms(detail, dialect)
      : renderer.renderFreeText(detail, dialect);
  return l10n.commonFormationWithDetail(base, renderedDetail);
}

/// Turns `role1s` → `role1s`, `rightDiagonal` → `right diagonal`,
/// `threeQuarter` → `three quarter` for display.
///
/// Lives here rather than beside the figure param editor because it is the
/// shared presentation primitive for figure-param vocabulary: the dance editor
/// and the Advanced-search facet must label the same canonical token the same
/// way (issue #741), and the dialect editor labels its dancer-substitution rows
/// with it too (issue #832). `figure_param_editors.dart` re-exports it so its
/// existing importers are unaffected.
///
/// Not dialect-aware by design — callers that need a dialect term reach for
/// [FigureRenderer.displayToken] (or [FigureRenderer.singleDancerDefaultTerm])
/// and fall back to this.
///
/// A capital that starts a word after a one-letter capital word is a break
/// too (`inARing` -> "in a ring"), as in the core renderer's humanizer.
String humanizeToken(String token) =>
    token.replaceAllMapped(_camelBoundary, (_) => ' ').toLowerCase();

final RegExp _camelBoundary = RegExp(
  r'(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])',
);

/// Human-readable label for a figure parameter's KEY (`meetTarget` -> "meet
/// target"), for field labels and the facet's "Any <param>" option.
///
/// The taxonomy carries no display name for a param key ([ParamSpec] has no
/// `label`), and it declares dozens of them. Canonical keys are therefore
/// humanized by default, while context-specific localized overrides can be
/// defined here when a UI label differs for a particular move. Keeping both
/// paths centralized ensures the dance editor and search surfaces stay aligned.
String figureParamKeyLabel(
  AppLocalizations l10n,
  String paramKey, {
  String? moveId,
}) {
  if (moveId == 'facing_star' && paramKey == 'who') {
    return l10n.figureParamFacingStarBackingUp;
  }
  return humanizeToken(paramKey);
}

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
/// is humanized. The single-dancer identities (`twosRole2`) are dancer
/// vocabulary too, and read as `<ordinal> <role term>` unless the dialect
/// rewords them — before issue #832 they fell through to humanization and this
/// picker showed `twos role2`. The stored value is always the canonical token
/// regardless of the label shown.
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
  // A fraction of `other` states its amount in a sibling param (#2120); as a
  // value on its own it means "some amount no named fraction states".
  if (spec.kind == ParamKind.fraction && choice == 'other') {
    return l10n.figureParamFractionOther;
  }
  final isDancerKind =
      spec.kind == ParamKind.dancerSet ||
      spec.kind == ParamKind.dancerPair ||
      spec.kind == ParamKind.dancerList;
  return isDancerKind
      ? FigureRenderer.displayToken(
          choice,
          // A list's token is labelled as a dancer set's (ECD's `who`).
          spec.kind == ParamKind.dancerList
              ? ParamSpec(
                  ParamKind.dancerSet,
                  defaultValue: null,
                  choices: spec.choices,
                )
              : spec,
          dialect,
        )
      : humanizeToken(choice);
}
