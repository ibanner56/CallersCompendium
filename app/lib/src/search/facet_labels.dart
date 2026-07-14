import 'package:compendium_core/compendium_core.dart';

/// Human-readable labels for the facet enums, for chips and dropdowns.
String danceFormLabel(DanceForm form) => switch (form) {
  DanceForm.contra => 'Contra',
  DanceForm.ecd => 'English (ECD)',
  DanceForm.square => 'Square',
};

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
