import '../imports/shorthand_mappings.dart'
    show maxShorthandMappings, normalizeShorthandToken;
import '../snippet/snippet_library.dart'
    show WalkthroughSnippetLibrary, kMaxSnippetLibraryEntries;
import 'canonical_json.dart';
import 'sync_reconciliation.dart' show rewriteSyncInboundReferences;
import 'sync_record_kind.dart';

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
      final library = _snippetLibrary(value);
      if (library == null) return value == null ? const [] : null;
      return [
        for (final entry in library.snippets.entries)
          SyncCollectionEntry(key: entry.key, label: null, value: entry.value),
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
  Set<String> ignore = _identityAndTimestampFields,
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

/// The fields of a [kind] record a person is shown when comparing two
/// versions of it, or null when every field is shown but identity and
/// timestamps (the fields [syncDifferingFields] ignores by default).
///
/// Fields left out — provenance, internal flags — are never what a person is
/// choosing between. The conflict comparison labels exactly these (an app
/// test holds the two together), and the merge uses them to decide whether a
/// tie needs a person at all ([syncUserVisibleContentHash]).
Set<String>? syncUserVisibleFields(SyncRecordKind kind) => switch (kind) {
  SyncRecordKind.dance => const {
    'title',
    'authorIds',
    'form',
    'formation',
    'progression',
    'phraseStructure',
    'figures',
    'hook',
    'callingNotes',
    'walkthrough',
    'difficultyLevelId',
    'mixedLevel',
    'mixer',
    'status',
    'rating',
    'tunes',
    'tagIds',
    'customFields',
    'links',
    'sourceCitations',
    'composedOn',
    'revisedOn',
    // Only its source and licence; see [syncUserVisibleBody].
    'provenance',
  },
  // The linked venue and the free-text venue are shown as one row.
  SyncRecordKind.program => const {
    'title',
    'eventDate',
    'venue',
    'venueId',
    'band',
    'caller',
    'dancerLevel',
    'status',
    'notes',
    'slots',
    'hideAlternates',
    'dialectName',
    'payMinorUnits',
    'payCurrency',
  },
  SyncRecordKind.choreographer => const {'name', 'website', 'notes'},
  SyncRecordKind.tag => const {'name', 'color'},
  SyncRecordKind.venue => const {
    'name',
    'eventName',
    'sponsor',
    'time',
    'genericSchedule',
    'price',
    'website',
    'notes',
  },
  SyncRecordKind.publishedSource ||
  SyncRecordKind.customFieldDef ||
  SyncRecordKind.difficultyLevel ||
  SyncRecordKind.setting => null,
};

/// What a person can see of a [kind] record's [body]: its
/// [syncUserVisibleFields], with references to records merged away by
/// natural-key reconciliation ([aliases], losing id to surviving id) read as
/// the records they were merged into. A dance's provenance is shown as where
/// it came from and its licence, so only those two of its fields are kept.
Map<String, Object?> syncUserVisibleBody(
  SyncRecordKind kind,
  Map<String, Object?> body, {
  Map<SyncRecordKind, Map<String, String>> aliases = const {},
}) {
  final resolved = aliases.isEmpty
      ? body
      : rewriteSyncInboundReferences(body, aliases);
  final visible = syncUserVisibleFields(kind);
  return {
    for (final entry in resolved.entries)
      if (visible == null
          ? !_identityAndTimestampFields.contains(entry.key)
          : visible.contains(entry.key))
        entry.key: switch ((kind, entry.key, entry.value)) {
          (SyncRecordKind.dance, 'provenance', final Map<Object?, Object?> p) =>
            {'source': p['source'], 'license': p['license']},
          _ => entry.value,
        },
  };
}

/// Hashes [syncUserVisibleBody]. Two versions with the same hash differ only
/// in ways a person could not tell apart, so choosing between them is
/// arbitrary and is never put to the user.
String syncUserVisibleContentHash(
  SyncRecordKind kind,
  Map<String, Object?> body, {
  Map<SyncRecordKind, Map<String, String>> aliases = const {},
}) => contentHash(syncUserVisibleBody(kind, body, aliases: aliases));

const _identityAndTimestampFields = {
  'id',
  'createdAt',
  'updatedAt',
  'deletedAt',
};

/// A walkthrough-snippet setting read exactly as the library loads it: keys
/// written under an older signature scheme are migrated to the current one,
/// so two devices' libraries are matched by the same signatures whatever
/// version each was saved at. Null when [value] is not a snippet library.
WalkthroughSnippetLibrary? _snippetLibrary(Object? value) {
  if (value is! Map || value['snippets'] is! Map) return null;
  return WalkthroughSnippetLibrary.fromJson(value.cast<String, Object?>());
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
    // Both libraries' retained alternatives are kept, signature by
    // signature; the library dedupes, sorts and caps them, and writes the
    // current signature version, since every key here is already current.
    final conflicts = <String, List<String>>{};
    for (final library in [_snippetLibrary(local), _snippetLibrary(other)]) {
      for (final entry in (library?.conflicts ?? const {}).entries) {
        conflicts.putIfAbsent(entry.key, () => []).addAll(entry.value);
      }
    }
    value = WalkthroughSnippetLibrary({
      for (final entry in combined) entry.key: entry.value as String,
    }, conflicts: conflicts).toJson();
  } else {
    value = [for (final entry in combined) entry.value];
  }
  return SyncCollectionCombination(
    value: value,
    count: combined.length,
    limit: syncCollectionLimit(key),
  );
}
