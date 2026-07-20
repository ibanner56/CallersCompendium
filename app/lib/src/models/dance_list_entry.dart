import 'package:compendium_core/compendium_core.dart';

/// A [Dance] plus everything the Collection list needs to render/sort/filter
/// it without re-querying repositories per row (authors and tags resolved
/// to names, last-called date looked up once for the whole list).
class DanceListEntry {
  DanceListEntry({
    required this.dance,
    required this.authorNames,
    required this.tagNames,
    required this.listCustomFields,
    required this.callCounts,
    this.lastCalled,
  });

  final Dance dance;
  final List<String> authorNames;
  final List<String> tagNames;

  /// `showInList` custom field values as `label: display value` pairs, in
  /// [CustomFieldDef] declaration order.
  final List<String> listCustomFields;

  /// How many times this dance has been called (all vs. performed-only),
  /// loaded once for the whole list. Drives the "called ×N" chip; the tile
  /// picks the tally matching the active "Require mark-performed" setting.
  final DanceCallCounts callCounts;
  final DateTime? lastCalled;

  String get title => dance.title;
}

/// Human-readable label for a [FormationShape], for chips and filters.
String formationShapeLabel(FormationShape shape) => switch (shape) {
  FormationShape.dupleImproper => 'Duple improper',
  FormationShape.becketCw => 'Becket (CW)',
  FormationShape.becketCcw => 'Becket (CCW)',
  FormationShape.dupleProper => 'Duple proper',
  FormationShape.dupleIndecent => 'Duple indecent',
  FormationShape.tripleMinor => 'Triple minor',
  FormationShape.threeFaceThree => 'Three-face-three',
  FormationShape.fourFaceFour => 'Four-face-four',
  FormationShape.circleMixer => 'Circle mixer',
  FormationShape.sicilianCircle => 'Sicilian circle',
  FormationShape.scatterMixer => 'Scatter mixer',
  FormationShape.longways => 'Longways',
  FormationShape.triplet => 'Triplet',
  FormationShape.grid => 'Grid',
  FormationShape.other => 'Other',
};

/// Full formation label, including free-text [Formation.detail] if present.
String formationLabel(Formation formation) {
  final base = formationShapeLabel(formation.shape);
  final detail = formation.detail?.trim();
  return (detail == null || detail.isEmpty) ? base : '$base — $detail';
}
