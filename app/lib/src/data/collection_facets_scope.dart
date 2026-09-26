import 'package:flutter/widgets.dart';

/// Ids of the built-in filter sections the user can hide from the Collection
/// page's Filters panel and the dance picker (issue #1419).
///
/// These are the `sectionId` slugs `FacetPanel` already gives its sections. They
/// are persisted under [kCollectionHiddenFacetsKey], so they must not be
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

/// The set of filter-section ids the user has chosen to hide, propagated to
/// every `FacetPanel` as a live [ValueNotifier] (issue #1419).
///
/// This is a **deny-list**, unlike the sibling `CollectionTileFieldsScope`
/// allow-list: the preference is "hide these", so a filter that is new — a
/// custom field created after the setting was saved, or a built-in added by a
/// later release — is visible by default rather than silently hidden. Nothing
/// hidden (the empty set) is what an unset, empty or corrupt preference means.
///
/// Ids are opaque strings and unknown ones are kept, so a preference written by
/// a newer build survives a round trip through an older one, and the id of a
/// deleted custom field is inert.
///
/// Hiding is display-only. It never deletes data and does not change what the
/// search core can do; the Advanced panel is a separate path.
///
/// **Reading:** [CollectionFacetsScope.of] inside `build`/`didChangeDependencies`
/// — returns the empty set without an ancestor, so a `FacetPanel` mounted
/// without the scope (tests) shows every filter. **Writing:** [notifierOf] from
/// the Settings screen.
class CollectionFacetsScope
    extends InheritedNotifier<ValueNotifier<Set<String>>> {
  const CollectionFacetsScope({
    super.key,
    required ValueNotifier<Set<String>> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The ids currently hidden. Registers a rebuild dependency.
  static Set<String> of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CollectionFacetsScope>();
    return scope?.notifier?.value ?? const <String>{};
  }

  /// The notifier for write-from-settings use. Does NOT register a rebuild
  /// dependency. Throws if there is no [CollectionFacetsScope] ancestor.
  static ValueNotifier<Set<String>> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<CollectionFacetsScope>();
    if (scope == null) {
      throw FlutterError(
        'CollectionFacetsScope.notifierOf() called with a context that has no '
        'CollectionFacetsScope ancestor.',
      );
    }
    return scope.notifier!;
  }

  /// Decodes a raw settings value (from `kCollectionHiddenFacetsKey`).
  ///
  /// A value that is not a `List` (key absent or corrupt) is the empty set, and
  /// non-`String` entries are dropped: whatever cannot be read is treated as
  /// "not hidden", so a bad value can never remove a filter.
  static Set<String> decodeStored(dynamic stored) {
    if (stored is! List) return const <String>{};
    return stored.whereType<String>().toSet();
  }

  /// The JSON form persisted for [hidden]: sorted, so the stored value does not
  /// depend on the order the user ticked the boxes.
  static List<String> encode(Set<String> hidden) => hidden.toList()..sort();
}
