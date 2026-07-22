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

/// The discrete, pickable value vocabulary for a figure parameter, or `null`
/// when the parameter has no closed vocabulary (rotation/beats/text). Used to
/// offer optional param dropdowns on an Advanced "has figure" row.
List<String>? figureParamChoices(ParamSpec spec) {
  switch (spec.kind) {
    case ParamKind.dancerSet:
    case ParamKind.dancerPair:
      return spec.choices ?? ParamVocab.dancerSets;
    case ParamKind.handedness:
    case ParamKind.shoulder:
      return ParamVocab.sides;
    case ParamKind.spinDirection:
      return ParamVocab.spins;
    case ParamKind.fraction:
      return ParamVocab.fractions;
    case ParamKind.direction:
      return ParamVocab.directions;
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
