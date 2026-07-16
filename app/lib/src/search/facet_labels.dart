import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Icons;

/// Human-readable labels for the facet enums, for chips and dropdowns.
String danceFormLabel(DanceForm form) => switch (form) {
  DanceForm.contra => 'Contra',
  DanceForm.ecd => 'English (ECD)',
  DanceForm.square => 'Square',
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

String progressionLabel(Progression p) => switch (p) {
  Progression.none => 'No progression',
  Progression.single => 'Single',
  Progression.double => 'Double',
  Progression.triple => 'Triple',
  Progression.quadruple => 'Quadruple',
  Progression.other => 'Other',
};

String danceStatusLabel(DanceStatus s) => switch (s) {
  DanceStatus.active => 'Active',
  DanceStatus.deprecated => 'Deprecated',
  DanceStatus.broken => 'Broken',
};

/// Human-readable label for a difficulty [DanceLevel] (app UI string, not a
/// dialect term).
String danceLevelLabel(DanceLevel level) => switch (level) {
  DanceLevel.beginner => 'Beginner',
  DanceLevel.intermediate => 'Intermediate',
  DanceLevel.advanced => 'Advanced',
};

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
