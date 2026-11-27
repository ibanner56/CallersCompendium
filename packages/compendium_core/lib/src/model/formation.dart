import 'package:meta/meta.dart';

import 'enums.dart';

/// Canonical formation shapes, seeded from The Caller's Box vocabulary.
///
/// One enum serves every dance form; [offeredFormationShapes] says which
/// values each form offers. The values from [dupleMinor] on were added for
/// English country dance (ADR-006 §12, F2): ECD records proper or improper in
/// [Formation.improper] rather than in the shape, so its shapes name only the
/// set. [tripleMinor], [sicilianCircle] and [other] are shared with contra.
///
/// Values are stored by name (`dances.formation_shape`, the archive and Device
/// Sync), so a value is never renamed or removed. A build that predates a value
/// skips a dance that carries it, with a warning.
enum FormationShape {
  dupleImproper,
  progressedImproper,
  reverseProgressionImproper,
  becketCw,
  becketCcw,
  dupleProper,
  dupleIndecent,
  tripleMinor,
  threeFaceThree,
  fourFaceFour,
  circleMixer,
  sicilianCircle,
  scatterMixer,
  longways,
  triplet,
  grid,
  quadruplet,
  other,

  /// ECD: a longways set danced in minor sets of two couples.
  dupleMinor,

  /// ECD: a longways set of exactly three couples.
  threeCoupleLongways,

  /// ECD: a longways set of exactly four couples.
  fourCoupleLongways,

  /// ECD: a longways set of exactly five couples.
  fiveCoupleLongways,

  /// ECD: a longways set of exactly six couples.
  sixCoupleLongways,

  /// ECD: a circle. Squares use it too, for a Southern big circle or big set
  /// (ADR-007 §8.1).
  circle,

  /// ECD: a square set, and a traditional square's own (ADR-007 §8.1).
  square,

  /// ECD: a set of two couples, such as "2 couple set - on the side with
  /// partner" (ADR-006 §9.2, point 6).
  twoCoupleSet,
}

/// The shapes ECD offers: those the maintainer listed (ADR-006 §12, F2), with
/// the two-couple set and the Sicilian circle added later (§9.2, points 5 and
/// 6), then [FormationShape.other] for a source whose formation none of them
/// names. No Becket circle (§9.1, point 2). A "three-couple set" or
/// "four-couple set" is the matching longways shape (§9.2, point 6). A
/// longways set of no stated number of couples, contra's [FormationShape.longways],
/// was added later (the maintainer, 27 November 2026): an English Becket is a
/// longways set with "Becket" as its detail ([ecdFormationFromContra]).
const List<FormationShape> ecdFormationShapes = [
  FormationShape.dupleMinor,
  FormationShape.tripleMinor,
  FormationShape.twoCoupleSet,
  FormationShape.threeCoupleLongways,
  FormationShape.fourCoupleLongways,
  FormationShape.fiveCoupleLongways,
  FormationShape.sixCoupleLongways,
  FormationShape.longways,
  FormationShape.circle,
  FormationShape.sicilianCircle,
  FormationShape.square,
  FormationShape.other,
];

/// The shapes contra offers: every shape that existed before ECD's were added,
/// unchanged (ADR-006 §12, F2: contra's shapes don't change).
const List<FormationShape> contraFormationShapes = [
  FormationShape.dupleImproper,
  FormationShape.progressedImproper,
  FormationShape.reverseProgressionImproper,
  FormationShape.becketCw,
  FormationShape.becketCcw,
  FormationShape.dupleProper,
  FormationShape.dupleIndecent,
  FormationShape.tripleMinor,
  FormationShape.threeFaceThree,
  FormationShape.fourFaceFour,
  FormationShape.circleMixer,
  FormationShape.sicilianCircle,
  FormationShape.scatterMixer,
  FormationShape.longways,
  FormationShape.triplet,
  FormationShape.grid,
  FormationShape.quadruplet,
  FormationShape.other,
];

/// The shapes a traditional square offers (ADR-007 §8.1): the square set
/// first, which a new square dance starts on; a circle, for a Southern big
/// circle or big set such as the Kentucky running set; and
/// [FormationShape.other] for anything else, such as a hexagon square.
///
/// The maintainer agreed that squares use [FormationShape.square] and left the
/// rest to research (ADR-007 Q13, 20 November 2026). Contra's longways,
/// becket and mixer shapes are left out because no held square or source
/// dances a square in them. `grid` waits for the Caller's Box search to show
/// whether its "Grid Contra/Square" marks squares.
const List<FormationShape> squareFormationShapes = [
  FormationShape.square,
  FormationShape.circle,
  FormationShape.other,
];

/// The shapes a dance of [form] offers when its formation is chosen.
///
/// A stored shape outside this list is still read and shown: an ECD dance
/// imported before the ECD shapes existed keeps its contra shape until it is
/// migrated (ADR-006 §12, F5), and a square imported before the square shapes
/// existed keeps `other` with detail "Square" until it is converted (ADR-007
/// §8.4).
List<FormationShape> offeredFormationShapes(DanceForm form) => switch (form) {
  DanceForm.ecd => ecdFormationShapes,
  DanceForm.square => squareFormationShapes,
  DanceForm.contra => contraFormationShapes,
};

/// Whether a dance of [form] records proper or improper apart from its shape,
/// in [Formation.improper]. Only ECD does: contra's shapes already say it
/// (ADR-006 §12, F2).
bool formHasImproperFlag(DanceForm form) => form == DanceForm.ecd;

/// A dance formation: canonical [shape] plus optional free-text [detail].
///
/// Enum-with-detail avoids ContraDB's regex-over-free-text weakness while
/// never losing information from unusual source formations.
@immutable
class Formation {
  const Formation(this.shape, {this.detail, this.improper = false});

  final FormationShape shape;

  /// Free-text qualifier (e.g. "double progression variant"). Canonicalized
  /// on input like all free text. Not normalized by this constructor (kept
  /// `const`-constructible for the common canonical-shape case) — callers
  /// building a [Formation] from user-entered or imported text should treat
  /// an empty/whitespace-only string as equivalent to `null` themselves.
  final String? detail;

  /// Whether the dance starts improper: ECD's proper/improper checkbox
  /// (ADR-006 §12, F2). `false` is proper, the usual case in ECD.
  ///
  /// Meaningful only where [formHasImproperFlag] holds for the dance's form.
  /// Contra's shapes already say proper or improper, so `Dance` clears the
  /// flag for any other form: a contra dance never holds it.
  final bool improper;

  Formation copyWith({FormationShape? shape, String? detail, bool? improper}) =>
      Formation(
        shape ?? this.shape,
        detail: detail ?? this.detail,
        improper: improper ?? this.improper,
      );

  @override
  bool operator ==(Object other) =>
      other is Formation &&
      other.shape == shape &&
      other.detail == detail &&
      other.improper == improper;

  @override
  int get hashCode => Object.hash(shape, detail, improper);

  @override
  String toString() =>
      'Formation(${shape.name}${detail == null ? '' : ', $detail'}'
      '${improper ? ', improper' : ''})';
}
