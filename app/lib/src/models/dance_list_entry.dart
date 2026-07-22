import 'package:compendium_core/compendium_core.dart';

/// A [Dance] plus everything the Collection list needs to render/sort/filter
/// it without re-querying repositories per row (authors and tags resolved
/// to names, last-called date looked up once for the whole list).
class DanceListEntry {
  DanceListEntry({
    required this.dance,
    required this.authorNames,
    required this.tagNames,
    this.tags = const [],
    required this.listCustomFields,
    required this.callCounts,
    this.lastCalled,
  });

  final Dance dance;
  final List<String> authorNames;
  final List<String> tagNames;

  /// The dance's tags as `(id, name)` pairs, in [Dance.tagIds] order, for tags
  /// whose name resolves. Carries the id (unlike [tagNames]) so a tapped tag
  /// chip in a list row can drive the Collection's id-based tag filter
  /// (issue #414).
  final List<({String id, String name})> tags;

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

/// English display labels for the facet enums, kept in the **source locale**
/// for the deferred export path (the plain-text / PDF builders in
/// `export/` and `compendium_core`), so exported documents stay byte-identical
/// English regardless of the app's UI locale (localization decision D2).
///
/// The facet enums live in the Flutter-free `compendium_core` package
/// (ADR-001) and cannot carry an `AppLocalizations`-aware label, so **UI** call
/// sites route through the localized helpers in `search/facet_labels.dart`
/// instead; these `.label` extensions are only for the export path.
extension FormationShapeLabel on FormationShape {
  String get label => switch (this) {
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
}

/// English full formation label (shape plus free-text [Formation.detail]),
/// for the export path only.
extension FormationLabel on Formation {
  String get label {
    final base = shape.label;
    final trimmed = detail?.trim();
    return (trimmed == null || trimmed.isEmpty) ? base : '$base — $trimmed';
  }
}

/// English label for a [DanceStatus], for the export path only.
extension DanceStatusExportLabel on DanceStatus {
  String get label => switch (this) {
    DanceStatus.active => 'Active',
    DanceStatus.deprecated => 'Deprecated',
    DanceStatus.broken => 'Broken',
  };
}

/// English label for a difficulty [DanceLevel], for the export path only.
extension DanceLevelExportLabel on DanceLevel {
  String get label => switch (this) {
    DanceLevel.beginner => 'Beginner',
    DanceLevel.intermediate => 'Intermediate',
    DanceLevel.advanced => 'Advanced',
  };
}
