import 'package:flutter/widgets.dart';

/// The set of data fields the user wants shown on each [DanceListTile] row.
///
/// Each value corresponds to one group of chips in the tile subtitle. The
/// preference is stored as a JSON list of name strings under
/// [kCollectionTileVisibleFieldsKey]. When a name is unrecognised (e.g. a
/// future field absent in an older build) it is silently ignored, so the set
/// is open-world safe.
///
/// All values default to visible: a caller who has not touched the setting sees
/// no change. The collection screen reads this scope and passes the result to
/// [DanceListTile.visibleFields]. Call sites that pass nothing render every chip,
/// so a new [DanceListTile] call site is unaffected until it explicitly opts in.
enum CollectionTileField {
  /// Author name(s) text line.
  authors,

  /// "Called ×N" chip.
  calledCount,

  /// Formation chip (always rendered by default, even without a color override).
  formation,

  /// Non-active status chip (e.g. Draft, Retired).
  status,

  /// Level chip and mixed-level chip.
  level,

  /// Rating chip.
  rating,

  /// All tag chips.
  tags,

  /// Chips for `showInList` custom fields.
  customFields;

  /// The full set of all fields — the default when no preference is stored.
  static const Set<CollectionTileField> all = {
    CollectionTileField.authors,
    CollectionTileField.calledCount,
    CollectionTileField.formation,
    CollectionTileField.status,
    CollectionTileField.level,
    CollectionTileField.rating,
    CollectionTileField.tags,
    CollectionTileField.customFields,
  };

  /// Encodes this field as a stable JSON string. Must not be renamed — the
  /// value is persisted in settings.
  String toJson() => name;

  /// Decodes a JSON string produced by [toJson]. Returns `null` for
  /// unrecognised values so open-world safety is handled at the call site.
  static CollectionTileField? fromJson(String raw) {
    for (final f in CollectionTileField.values) {
      if (f.name == raw) return f;
    }
    return null;
  }
}

/// Propagates the user's chosen set of [CollectionTileField]s to all
/// [DanceListTile] descendants as a live [ValueNotifier].
///
/// Placed at the root of the widget tree (alongside [RequirePerformedForHistoryScope])
/// so the settings screen — a sibling of the collection screen in the navigation
/// tree — can write to the notifier via [notifierOf].
///
/// **Scope of the preference:** only the collection screen opts in by passing
/// [CollectionTileFieldsScope.of] to [DanceListTile.visibleFields]. All other
/// [DanceListTile] call sites pass `null`, which defaults to
/// [CollectionTileField.all] inside the tile — so search results, program
/// lists, and the picker always render at full density without any override.
///
/// **Reading the value:** call [CollectionTileFieldsScope.of] inside `build`.
/// It returns [CollectionTileField.all] when no ancestor is present, preserving
/// the previous rendering for any call site that doesn't opt in.
///
/// **Writing the value:** call [CollectionTileFieldsScope.notifierOf] from a
/// settings widget to update and persist the preference.
class CollectionTileFieldsScope
    extends InheritedNotifier<ValueNotifier<Set<CollectionTileField>>> {
  const CollectionTileFieldsScope({
    super.key,
    required ValueNotifier<Set<CollectionTileField>> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The set of fields currently marked visible. Registers a rebuild dependency
  /// so the caller rebuilds whenever the notifier changes.
  ///
  /// Returns [CollectionTileField.all] (everything visible) when there is no
  /// [CollectionTileFieldsScope] ancestor, so tests and call sites without the
  /// scope wired behave identically to the pre-feature state.
  static Set<CollectionTileField> of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CollectionTileFieldsScope>();
    return scope?.notifier?.value ?? CollectionTileField.all;
  }

  /// Returns the underlying notifier for write-from-settings use. Does NOT
  /// register a rebuild dependency.
  ///
  /// Throws if no [CollectionTileFieldsScope] ancestor exists.
  static ValueNotifier<Set<CollectionTileField>> notifierOf(
    BuildContext context,
  ) {
    final scope = context
        .getInheritedWidgetOfExactType<CollectionTileFieldsScope>();
    if (scope == null) {
      throw FlutterError(
        'CollectionTileFieldsScope.notifierOf() called with a context that '
        'has no CollectionTileFieldsScope ancestor.',
      );
    }
    return scope.notifier!;
  }

  /// Decodes a raw settings value (from [kCollectionTileVisibleFieldsKey]) into
  /// a [Set<CollectionTileField>] for use as the initial notifier value.
  ///
  /// Three cases:
  ///
  /// - [stored] is not a `List` (key absent or corrupt) → [CollectionTileField.all]:
  ///   the preference has never been saved, so default to all visible.
  /// - [stored] is an empty `List` → empty set: the user deliberately turned off
  ///   every field and that choice must be honoured on restart.
  /// - [stored] is a non-empty `List` → decode recognised names; if every name is
  ///   unrecognised (e.g. stored on a future build, opened on an older one) fall
  ///   back to [CollectionTileField.all] so unknown fields don't disappear.
  static Set<CollectionTileField> decodeStored(dynamic stored) {
    if (stored is! List) return CollectionTileField.all;
    if (stored.isEmpty) return const {};
    final decoded = stored
        .whereType<String>()
        .map(CollectionTileField.fromJson)
        .whereType<CollectionTileField>()
        .toSet();
    return decoded.isEmpty ? CollectionTileField.all : decoded;
  }
}
