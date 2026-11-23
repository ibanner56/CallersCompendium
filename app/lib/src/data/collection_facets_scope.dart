import 'package:flutter/widgets.dart';

// The ids and helpers live in compendium_core (#2325); re-exported so the app's
// importers of this file keep working.
export 'package:compendium_core/compendium_core.dart'
    show CollectionFacetIds, customFieldFacetId, customFieldIdOfFacetId;

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
