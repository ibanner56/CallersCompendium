import 'package:collection/collection.dart' show mergeSort;

import '../imports/compound_shorthands.dart'
    show compoundShorthandsSettingKey, maxCompoundShorthands;
import '../imports/shorthand_mappings.dart'
    show maxShorthandMappings, normalizeShorthandToken;
import '../imports/user_figure_shorthands.dart'
    show maxUserFigureShorthands, userFigureShorthandsSettingKey;
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
/// tells entries apart: a dialect by its name, a custom theme by its id,
/// a figure or compound shorthand by its normalized token, a walkthrough
/// snippet by its figure signature. Malformed entries are skipped rather than
/// failing the comparison — this is display, and the merge already admitted
/// the value.
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
    case compoundShorthandsSettingKey || userFigureShorthandsSettingKey:
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
  Set<String> ignore = syncIdentityAndTimestampFields,
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
/// A nested path (`provenance.source`) marks its field as shown only in part:
/// of that field, only the listed parts are compared. Every other synced
/// field is in [syncUserHiddenFields], with the reason it is not shown;
/// `test/sync/sync_user_visible_fields_test.dart` fails the build for a
/// synced field in neither, so a new field cannot be left out of the
/// comparison — and settled without asking — by omission.
///
/// The conflict comparison labels exactly the top-level fields here (an app
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
    // Each link as the comparison shows it; its own id is not shown.
    'links',
    'links.kind',
    'links.label',
    'links.url',
    'links.targetDanceId',
    'links.transitive',
    'sourceCitations',
    'composedOn',
    'revisedOn',
    // Shown as its page shows it: where it came from, and its licence.
    'provenance',
    'provenance.source',
    'provenance.license',
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
    // Each slot as the comparison shows it, in position order: what it holds
    // and its details. Its own id and position number are not shown.
    'slots',
    'slots.danceId',
    'slots.text',
    'slots.isAlt',
    'slots.isPurgedDance',
    'slots.guestCaller',
    'slots.walkthroughMinutes',
    'slots.danceMinutes',
    'slots.performedAt',
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
  // The user's glossary (#709), as its Glossary page shows an entry. Its text
  // holds canonical role words, shown in the active dialect.
  SyncRecordKind.glossaryEntry => const {
    'name',
    'definition',
    'description',
    'keywords',
    'notes',
    'payload',
  },
  SyncRecordKind.figureNote => const {'notes'},
  SyncRecordKind.publishedSource ||
  SyncRecordKind.customFieldDef ||
  SyncRecordKind.difficultyLevel ||
  SyncRecordKind.setting => null,
};

/// The synced fields of a [kind] record that a comparison does not show,
/// each with the reason, by wire path: every synced field outside
/// [syncUserVisibleFields] but identity and timestamps. A version that
/// differs from another only here is settled without asking (sync-spec
/// §6.3), so a field belongs here only when nothing in the app shows it.
Map<String, String> syncUserHiddenFields(SyncRecordKind kind) => switch (kind) {
  SyncRecordKind.dance => const {
    'provenance.externalId':
        'The source site\'s own id for the dance. Never displayed; online '
        'search uses it (with the source) to mark a result as already in the '
        'collection, a hint rather than a field. Hidden by choice in PR '
        '#1729.',
    'provenance.importedAt':
        'When this copy was imported; nothing displays it for a dance.',
    'provenance.permission':
        'Import bookkeeping; the dance page shows the licence, not this.',
    'provenance.sourceVersion':
        'The source\'s format version, read only by import.',
    'links.id':
        'Each link\'s own id, generated where it was added; the comparison '
        'shows a link by its kind, label, destination and group.',
  },
  SyncRecordKind.program => const {
    'slots.id':
        'Each slot\'s own id, generated where it was added; the comparison '
        'matches slots by the dance or text they hold.',
    'slots.position':
        'The comparison shows slots in this order, which the projection '
        'keeps, but not the numbers themselves: renumbering alone is no '
        'difference.',
    'provenance':
        'Where an imported program came from. The program pages do not show '
        'it; the ContraDB import screen uses its source and id to badge a '
        'program as already imported, with the import date in the badge\'s '
        'tooltip. A hint on another screen rather than a field of the '
        'program: hidden by choice in PR #1729.',
  },
  SyncRecordKind.venue => const {
    'provenance':
        'Where an imported venue came from; nothing in the app displays it.',
  },
  SyncRecordKind.glossaryEntry => const {
    'kind':
        'Fixed when the entry is created: no edit changes it, so two versions '
        'of one entry do not differ in it. Nothing names it; an entry of a '
        'kind this build does not know is shown as made by a newer version. '
        'Hidden by the implementer in #709.',
  },
  SyncRecordKind.choreographer ||
  SyncRecordKind.tag ||
  SyncRecordKind.publishedSource ||
  SyncRecordKind.customFieldDef ||
  SyncRecordKind.difficultyLevel ||
  SyncRecordKind.setting ||
  SyncRecordKind.figureNote => const {},
};

/// What a person can see of a [kind] record's [body]: its
/// [syncUserVisibleFields], with references to records merged away by
/// natural-key reconciliation ([aliases], losing id to surviving id) read as
/// the records they were merged into. Of a field shown only in part, only
/// the listed parts are kept.
Map<String, Object?> syncUserVisibleBody(
  SyncRecordKind kind,
  Map<String, Object?> body, {
  Map<SyncRecordKind, Map<String, String>> aliases = const {},
}) {
  final resolved = syncResolveComparedReferences(body, aliases);
  final visible = syncUserVisibleFields(kind);
  Object? shown(String key, Object? value) {
    final parts = {
      for (final path in visible ?? const <String>{})
        if (path.startsWith('$key.')) path.substring(key.length + 1),
    };
    if (parts.isEmpty) return value;
    Object? keep(Object? entry) =>
        entry is Map ? {for (final part in parts) part: entry[part]} : entry;
    if (value is Map) return keep(value);
    if (value is! List) return value;
    final order = _shownInOrderOf[(kind, key)];
    final entries = [...value];
    if (order != null) {
      num at(Object? entry) => entry is Map ? (entry[order] as num?) ?? 0 : 0;
      mergeSort(entries, compare: (a, b) => at(a).compareTo(at(b)));
    }
    return [for (final entry in entries) keep(entry)];
  }

  return {
    for (final entry in resolved.entries)
      if (visible == null
          ? !syncIdentityAndTimestampFields.contains(entry.key)
          : visible.contains(entry.key))
        entry.key: shown(entry.key, entry.value),
  };
}

/// [body] with every reference to a record merged away by natural-key
/// reconciliation or dance deduplication ([aliases], losing id to surviving
/// id) read as the record it was merged into: what inbound apply rewrites
/// ([rewriteSyncInboundReferences]), and also the dances a dance's links and
/// a program's slots cite. For comparing versions and naming what they cite;
/// it does not change what apply writes. Returns [body] itself when there are
/// no aliases.
Map<String, Object?> syncResolveComparedReferences(
  Map<String, Object?> body,
  Map<SyncRecordKind, Map<String, String>> aliases,
) {
  if (aliases.isEmpty) return body;
  final resolved = rewriteSyncInboundReferences(body, aliases);
  final dances = aliases[SyncRecordKind.dance];
  if (dances == null) return resolved;
  String? dance(Object? id) {
    if (id is! String) return null;
    var current = id;
    final seen = {id};
    for (var next = dances[current]; next != null; next = dances[current]) {
      if (!seen.add(next)) break;
      current = next;
    }
    return current;
  }

  for (final (key, part) in const [
    ('links', 'targetDanceId'),
    ('slots', 'danceId'),
  ]) {
    final entries = resolved[key];
    if (entries is! List) continue;
    resolved[key] = [
      for (final entry in entries)
        entry is Map ? _withResolved(entry, part, dance) : entry,
    ];
  }
  return resolved;
}

Object? _withResolved(
  Map<Object?, Object?> entry,
  String part,
  String? Function(Object?) resolve,
) {
  final id = resolve(entry[part]);
  return id == null ? entry : {...entry, part: id};
}

/// List fields the comparison shows in the order of a part it does not show:
/// the projection orders entries by that part before dropping it.
const Map<(SyncRecordKind, String), String> _shownInOrderOf = {
  (SyncRecordKind.program, 'slots'): 'position',
};

/// Hashes [syncUserVisibleBody]. Two versions with the same hash differ only
/// in ways a person could not tell apart, so choosing between them is
/// arbitrary and is never put to the user.
String syncUserVisibleContentHash(
  SyncRecordKind kind,
  Map<String, Object?> body, {
  Map<SyncRecordKind, Map<String, String>> aliases = const {},
}) => contentHash(syncUserVisibleBody(kind, body, aliases: aliases));

/// Identity and timestamps, never compared between versions: each copy
/// names its own id, and its stamps decide a tie rather than being what it
/// is decided between. `createdAt` does order the collection's "Recently
/// added" sort, and is left out by choice (PR #1729): which of two creation
/// times a record keeps is not a choice a person can weigh.
const Set<String> syncIdentityAndTimestampFields = {
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
  compoundShorthandsSettingKey => maxCompoundShorthands,
  userFigureShorthandsSettingKey => maxUserFigureShorthands,
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
