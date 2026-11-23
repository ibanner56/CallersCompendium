import '../../search/saved_search.dart';
import '../../util/uuid.dart';
import 'settings_repository.dart';

/// Most live saved searches [SavedSearchRepository.create] will let a device
/// hold, counting every one it can see, those a peer synced and those it
/// cannot read. Each is one synced settings value (the store keeps a quota of
/// blobs), and a list longer than this is not a list a caller can use; the
/// same order as the custom dialects' cap. It limits adding only: reading is
/// never limited, a peer may hold more, and [SavedSearchRepository.save] (an
/// update, or an Undo) does not count.
const int savedSearchMaxCount = 128;

/// One thing that depends on a saved search: what kind of thing, and what to
/// call it in a message ("an event rule", "the slot rule of Contra night").
final class SavedSearchUse {
  const SavedSearchUse({required this.kind, required this.label});

  final String kind;
  final String label;

  @override
  String toString() => 'SavedSearchUse($kind: $label)';
}

/// Answers "which of my records use the saved search [id]?" for one dependent
/// feature (an event rule, a template's slot rule, a suggestion preference).
typedef SavedSearchUsageLookup =
    Future<List<SavedSearchUse>> Function(String savedSearchId);

/// The lookups the dependent features register, so deleting a saved search
/// that something uses is refused (the venue precedent: a venue cannot be
/// deleted while a program is linked to it).
///
/// Nothing is registered until a dependent feature lands, so every delete is
/// allowed until then. A saved search can still arrive later by sync from a
/// peer that had not seen the delete; a dependent must handle a missing id.
/// Saved searches keep no back-reference list: it would sync and drift.
final class SavedSearchUsageRegistry {
  final Map<String, SavedSearchUsageLookup> _lookups = {};

  /// Registers [lookup] under [owner] (replacing an earlier one of the same
  /// owner, so a hot restart does not register twice).
  void register(String owner, SavedSearchUsageLookup lookup) =>
      _lookups[owner] = lookup;

  void unregister(String owner) => _lookups.remove(owner);

  /// Everything that uses [savedSearchId], from every registered lookup.
  Future<List<SavedSearchUse>> usesOf(String savedSearchId) async => [
    for (final lookup in _lookups.values.toList())
      ...await lookup(savedSearchId),
  ];
}

/// A saved search was not deleted because something still uses it.
final class SavedSearchInUse implements Exception {
  const SavedSearchInUse(this.id, this.uses);

  final String id;

  /// What uses it, for the message that names each.
  final List<SavedSearchUse> uses;

  @override
  String toString() => 'SavedSearchInUse($id, ${uses.length} use(s))';
}

/// Adding another saved search would pass [savedSearchMaxCount].
final class SavedSearchLimitReached implements Exception {
  const SavedSearchLimitReached();

  @override
  String toString() => 'SavedSearchLimitReached';
}

/// A stored saved search: readable, or kept in the list as needing attention.
final class StoredSavedSearch {
  const StoredSavedSearch.readable(SavedSearch this.search)
    : id = null,
      problem = null;

  const StoredSavedSearch.unreadable(String this.id, String this.problem)
    : search = null;

  final SavedSearch? search;

  /// The id of an unreadable one (a readable one has it in [search]).
  final String? id;

  /// Why it cannot be read, for an unreadable one.
  final String? problem;

  String get savedSearchId => search?.id ?? id!;
}

/// Saved searches, one settings value each under [savedSearchKeyPrefix]. A
/// saved search is the user's own configuration and syncs behind the
/// `savedSearches.v1` capability.
///
/// Deleting tombstones the key (a state change a peer must learn of), and a
/// later [save] of the same id revives it, which is how an Undo restores one.
class SavedSearchRepository {
  SavedSearchRepository(this._settings, {SavedSearchUsageRegistry? usage})
    : usage = usage ?? SavedSearchUsageRegistry();

  final SettingsRepository _settings;

  /// The dependents' "who uses this?" lookups, consulted by [delete].
  final SavedSearchUsageRegistry usage;

  /// Every live saved search, readable or not, by name (unreadable ones last),
  /// ties broken by id so the order is the same on every device.
  Future<List<StoredSavedSearch>> list() async {
    final keys = await _settings.keysWithPrefix(savedSearchKeyPrefix);
    final stored = <StoredSavedSearch>[];
    for (final key in keys) {
      final id = key.substring(savedSearchKeyPrefix.length);
      final value = await _settings.get(key);
      final read = SavedSearch.decode(id, value);
      stored.add(
        read.value != null
            ? StoredSavedSearch.readable(read.value!)
            : StoredSavedSearch.unreadable(id, read.problem!),
      );
    }
    int rank(StoredSavedSearch s) => s.search == null ? 1 : 0;
    stored.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byName = (a.search?.name.toLowerCase() ?? '').compareTo(
        b.search?.name.toLowerCase() ?? '',
      );
      return byName != 0 ? byName : a.savedSearchId.compareTo(b.savedSearchId);
    });
    return stored;
  }

  /// The saved search [id], or null when there is none or it cannot be read.
  Future<SavedSearch?> get(String id) async {
    final value = await _settings.get('$savedSearchKeyPrefix$id');
    return value == null ? null : SavedSearch.decode(id, value).value;
  }

  /// Saves a new search under a fresh id. Throws [SavedSearchLimitReached]
  /// when this device already holds [savedSearchMaxCount].
  Future<SavedSearch> create({
    required String name,
    required SavedSearchSpec spec,
    DateTime? at,
  }) async {
    final held = await _settings.keysWithPrefix(savedSearchKeyPrefix);
    if (held.length >= savedSearchMaxCount) {
      throw const SavedSearchLimitReached();
    }
    final search = SavedSearch(id: uuidV4(), name: name.trim(), spec: spec);
    await save(search, at: at);
    return search;
  }

  /// Writes [search] under its own id: an update, or the revival of a deleted
  /// one (an Undo). The value is checked as the store will keep it (after
  /// normalization), so a name or content this format cannot read, an empty id
  /// or keys that differ only by invisible characters throw [ArgumentError]
  /// here rather than being stored.
  Future<void> save(SavedSearch search, {DateTime? at}) async {
    if (search.id.trim().isEmpty) {
      throw ArgumentError.value(search.id, 'search.id', 'must not be empty');
    }
    final json = search.toJson();
    final check = SavedSearch.decodeAsStored(search.id, json);
    if (check.value == null) {
      throw ArgumentError.value(search.name, 'search', check.problem);
    }
    await _settings.set(search.settingsKey, json, at: at);
  }

  /// Deletes the saved search [id] (a tombstone, so the deletion syncs).
  /// Throws [SavedSearchInUse], naming each user, while a registered
  /// dependent still uses it; nothing is written then.
  Future<void> delete(String id, {DateTime? at}) async {
    final uses = await usage.usesOf(id);
    if (uses.isNotEmpty) throw SavedSearchInUse(id, uses);
    await _settings.remove('$savedSearchKeyPrefix$id', at: at);
  }
}
