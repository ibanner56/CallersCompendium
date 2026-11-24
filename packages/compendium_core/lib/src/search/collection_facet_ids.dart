/// Ids of the built-in filter sections the user can hide from the Collection
/// page's Filters panel and the dance picker (issue #1419).
///
/// These are the `sectionId` slugs `FacetPanel` already gives its sections. They
/// are persisted under `kCollectionHiddenFacetsKey` (in the app), so they must not be
/// renamed. A custom-field section is identified by [customFieldFacetId] rather
/// than by its panel `sectionId`, because the latter embeds the field's type and
/// would stop matching if the field's type were edited.
abstract final class CollectionFacetIds {
  static const String form = 'form';
  static const String formation = 'formation';
  static const String progression = 'progression';
  static const String status = 'status';
  static const String level = 'level';
  static const String mixedLevel = 'mixed-level';
  static const String mixer = 'mixer';
  static const String minRating = 'min-rating';
  static const String callStatus = 'call-status';
  static const String author = 'author';
  static const String tunes = 'tunes';
  static const String meter = 'meter';
  static const String musicalKey = 'musical-key';
  static const String tags = 'tags';
  static const String source = 'source';

  /// Every built-in id, in the order the panel lists them.
  static const List<String> builtIns = [
    form,
    formation,
    progression,
    status,
    level,
    mixedLevel,
    mixer,
    minRating,
    callStatus,
    author,
    tunes,
    meter,
    musicalKey,
    tags,
    source,
  ];
}

/// The persisted id of the filter section for the custom field [defId].
///
/// Keyed by the definition id (not its label, which is user-authored and not
/// unique, and not the panel `sectionId`, which embeds the field type).
String customFieldFacetId(String defId) => '$_customFieldFacetIdPrefix$defId';

/// The custom-field definition id in [facetId], or `null` when [facetId] is not
/// a [customFieldFacetId].
String? customFieldIdOfFacetId(String facetId) =>
    facetId.startsWith(_customFieldFacetIdPrefix)
    ? facetId.substring(_customFieldFacetIdPrefix.length)
    : null;

const String _customFieldFacetIdPrefix = 'cf:';
