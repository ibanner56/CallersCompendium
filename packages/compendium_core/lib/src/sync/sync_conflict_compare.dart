import '../imports/shorthand_mappings.dart'
    show maxShorthandMappings, normalizeShorthandToken;
import '../snippet/snippet_library.dart' show kMaxSnippetLibraryEntries;
import 'canonical_json.dart';

/// One entry of a whole-collection setting, identified the way the user's own
/// library identifies it, for comparing two versions of the collection.
///
/// [key] matches the same entry across versions; [label] is what the user
/// knows it by (null when the entry has no name of its own — a walkthrough
/// snippet, shown by its text instead); [value] is the entry as stored.
class SyncCollectionEntry {
  const SyncCollectionEntry({
    required this.key,
    required this.label,
    required this.value,
  });

  final String key;
  final String? label;
  final Object? value;
}

/// How two versions of a whole-collection setting differ, entry by entry.
class SyncCollectionDiff {
  const SyncCollectionDiff({
    required this.onlyLocal,
    required this.onlyOther,
    required this.changed,
    required this.same,
  });

  /// Entries this device has and the other version lacks.
  final List<SyncCollectionEntry> onlyLocal;

  /// Entries the other version has and this device lacks.
  final List<SyncCollectionEntry> onlyOther;

  /// Entries both versions have, with different contents.
  final List<({SyncCollectionEntry local, SyncCollectionEntry other})> changed;

  /// How many entries are identical in both versions.
  final int same;

  bool get isEmpty => onlyLocal.isEmpty && onlyOther.isEmpty && changed.isEmpty;
}

/// The entries of a whole-collection setting's [value], or null when [key] is
/// not a whole-collection setting or [value] is not shaped like one.
///
/// Each key has its own notion of identity, matching how its library already
/// tells entries apart: a dialect by its name, a custom theme by its id, a
/// figure shorthand by its normalized token, a walkthrough snippet by its
/// figure signature. Malformed entries are skipped rather than failing the
/// comparison — this is display, and the merge already admitted the value.
List<SyncCollectionEntry>? syncCollectionEntries(String key, Object? value) {
  switch (key) {
    case 'custom_dialects':
      if (value is! List) return null;
      return [
        for (final entry in value)
          if (entry is Map && entry['name'] is String)
            SyncCollectionEntry(
              key: entry['name'] as String,
              label: entry['name'] as String,
              value: entry,
            ),
      ];
    case 'custom_themes':
      if (value is! List) return null;
      return [
        for (final entry in value)
          if (entry is Map && entry['id'] is String)
            SyncCollectionEntry(
              key: entry['id'] as String,
              label: entry['name'] is String ? entry['name'] as String : null,
              value: entry,
            ),
      ];
    case 'shorthand_mappings':
      if (value is! List) return null;
      return [
        for (final entry in value)
          if (entry is Map && entry['token'] is String)
            SyncCollectionEntry(
              key: normalizeShorthandToken(entry['token'] as String),
              label: entry['token'] as String,
              value: entry,
            ),
      ];
    case 'walkthrough_snippets':
      final snippets = value is Map ? value['snippets'] : null;
      if (snippets is! Map) return value == null ? const [] : null;
      return [
        for (final entry in snippets.entries)
          if (entry.key is String)
            SyncCollectionEntry(
              key: entry.key as String,
              label: null,
              value: entry.value,
            ),
      ];
  }
  return null;
}

/// Compares two versions of the whole-collection setting [key], or returns
/// null when either version cannot be read as that collection.
///
/// A missing (null) version counts as an empty collection, so a set that one
/// device never had reads as "only on the other device" in full.
SyncCollectionDiff? compareSyncCollection(
  String key,
  Object? local,
  Object? other,
) {
  final localEntries = local == null
      ? const <SyncCollectionEntry>[]
      : syncCollectionEntries(key, local);
  final otherEntries = other == null
      ? const <SyncCollectionEntry>[]
      : syncCollectionEntries(key, other);
  if (localEntries == null || otherEntries == null) return null;
  final otherByKey = {for (final entry in otherEntries) entry.key: entry};
  final localKeys = {for (final entry in localEntries) entry.key};
  final onlyLocal = <SyncCollectionEntry>[];
  final changed = <({SyncCollectionEntry local, SyncCollectionEntry other})>[];
  var same = 0;
  for (final entry in localEntries) {
    final match = otherByKey[entry.key];
    if (match == null) {
      onlyLocal.add(entry);
    } else if (canonicalJson(entry.value) == canonicalJson(match.value)) {
      same++;
    } else {
      changed.add((local: entry, other: match));
    }
  }
  return SyncCollectionDiff(
    onlyLocal: List.unmodifiable(onlyLocal),
    onlyOther: List.unmodifiable([
      for (final entry in otherEntries)
        if (!localKeys.contains(entry.key)) entry,
    ]),
    changed: List.unmodifiable(changed),
    same: same,
  );
}

/// The top-level fields of two record bodies whose values differ, in
/// [local]'s key order and then [other]'s, skipping [ignore].
///
/// Only keys present in at least one body are compared; a key one body lacks
/// compares as null. Identity and timestamp projections are ignored by
/// default: every version of a record carries its own.
List<String> syncDifferingFields(
  Map<String, Object?>? local,
  Map<String, Object?>? other, {
  Set<String> ignore = const {'id', 'createdAt', 'updatedAt', 'deletedAt'},
}) {
  final keys = <String>[...?local?.keys];
  for (final key in other?.keys ?? const <String>[]) {
    if (!keys.contains(key)) keys.add(key);
  }
  return [
    for (final key in keys)
      if (!ignore.contains(key) &&
          canonicalJson(local?[key]) != canonicalJson(other?[key]))
        key,
  ];
}

/// The most custom dialects a library keeps. Mirrors the app's backup limit
/// (`kMaxCustomDialects`); `sync_whole_collection_keys_test.dart` holds the
/// two together.
const int syncMaxCustomDialects = 128;

/// How many entries the library for whole-collection setting [key] keeps, or
/// null when it keeps any number. A combination above it would be cut short
/// when the library next loads, losing entries without a word, so it is
/// refused instead.
int? syncCollectionLimit(String key) => switch (key) {
  'custom_dialects' => syncMaxCustomDialects,
  'shorthand_mappings' => maxShorthandMappings,
  'walkthrough_snippets' => kMaxSnippetLibraryEntries,
  _ => null,
};

/// Both versions of a whole-collection setting combined into one.
class SyncCollectionCombination {
  const SyncCollectionCombination({
    required this.value,
    required this.count,
    required this.limit,
  });

  /// The combined setting value, shaped as the library stores it.
  final Object? value;

  /// How many entries it holds.
  final int count;

  /// The library's limit, or null when it has none.
  final int? limit;

  bool get overLimit => limit != null && count > limit!;
}

/// Combines two versions of the whole-collection setting [key]: every entry
/// either version has, in this device's order and then the other's. Where
/// both have an entry with different contents, the other device's is taken
/// for the keys in [takeOtherFor] and this device's for the rest. Returns
/// null when either version cannot be read as that collection.
SyncCollectionCombination? combineSyncCollection(
  String key,
  Object? local,
  Object? other, {
  Set<String> takeOtherFor = const {},
}) {
  final localEntries = local == null
      ? const <SyncCollectionEntry>[]
      : syncCollectionEntries(key, local);
  final otherEntries = other == null
      ? const <SyncCollectionEntry>[]
      : syncCollectionEntries(key, other);
  if (localEntries == null || otherEntries == null) return null;
  final otherByKey = {for (final entry in otherEntries) entry.key: entry};
  final combined = <SyncCollectionEntry>[
    for (final entry in localEntries)
      if (takeOtherFor.contains(entry.key) && otherByKey[entry.key] != null)
        otherByKey[entry.key]!
      else
        entry,
  ];
  final localKeys = {for (final entry in localEntries) entry.key};
  combined.addAll([
    for (final entry in otherEntries)
      if (!localKeys.contains(entry.key)) entry,
  ]);
  final Object? value;
  if (key == 'walkthrough_snippets') {
    final localMap = local is Map ? local : const <String, Object?>{};
    final otherMap = other is Map ? other : const <String, Object?>{};
    final conflicts = <String, Object?>{
      ...?(otherMap['conflicts'] as Map?)?.cast<String, Object?>(),
      ...?(localMap['conflicts'] as Map?)?.cast<String, Object?>(),
    };
    value = {
      'version': localMap['version'] ?? otherMap['version'],
      'snippets': {for (final entry in combined) entry.key: entry.value},
      if (conflicts.isNotEmpty) 'conflicts': conflicts,
    };
  } else {
    value = [for (final entry in combined) entry.value];
  }
  return SyncCollectionCombination(
    value: value,
    count: combined.length,
    limit: syncCollectionLimit(key),
  );
}
