import '../model/custom_field.dart';
import '../model/published_source.dart';
import '../model/tag.dart';
import '../serialization/compendium_archive.dart';
import '../storage/repositories/custom_field_repository.dart';
import '../storage/repositories/published_source_repository.dart';
import '../storage/repositories/tag_repository.dart';

/// The receiver-side ids and rollback ledger for metadata in a shared archive.
class ShareMetadataImportResult {
  ShareMetadataImportResult({
    required this.tagIdByArchiveId,
    required this.sourceIdByArchiveId,
    required this.fieldIdByArchiveId,
    required this.insertedTagIds,
    required this.restoredTagIds,
    required this.insertedSourceIds,
    required this.restoredSourceIds,
    required this.insertedFieldIds,
    required this.restoredFieldIds,
  });

  final Map<String, String> tagIdByArchiveId;
  final Map<String, String> sourceIdByArchiveId;
  final Map<String, String> fieldIdByArchiveId;
  final List<String> insertedTagIds;
  final List<String> restoredTagIds;
  final List<String> insertedSourceIds;
  final List<String> restoredSourceIds;
  final List<String> insertedFieldIds;
  final List<String> restoredFieldIds;
}

/// Imports only the metadata referenced by a shared archive.
///
/// Archive ids are never trusted as receiver ids. Live compatible records are
/// reused without being overwritten; exact tombstones are revived; all other
/// records get freshly generated ids. An incompatible custom-field key is
/// rejected because renaming it would silently change the meaning of values.
class ShareMetadataImporter {
  ShareMetadataImporter({
    required this.tags,
    required this.sources,
    required this.customFields,
  });

  final TagRepository tags;
  final PublishedSourceRepository sources;
  final CustomFieldDefRepository customFields;

  Future<ShareMetadataImportResult> commit(
    CompendiumArchive archive, {
    required DateTime now,
    required String Function() newId,
  }) async {
    _validateDuplicateIds(archive);
    final existingTags = await tags.listAllWithDeleted();
    final existingSources = await sources.listAllWithDeleted();
    final existingFields = await customFields.listAllWithDeleted();
    _validateReferences(archive);
    final usedIds = <String>{
      for (final item in existingTags) item.tag.id,
      for (final item in existingSources) item.source.id,
      for (final item in existingFields) item.field.id,
    };
    String freshId() {
      for (var attempt = 0; attempt < 100; attempt++) {
        final id = newId();
        if (usedIds.add(id)) return id;
      }
      throw StateError('unable to allocate a unique receiver metadata id');
    }

    final result = ShareMetadataImportResult(
      tagIdByArchiveId: {},
      sourceIdByArchiveId: {},
      fieldIdByArchiveId: {},
      insertedTagIds: [],
      restoredTagIds: [],
      insertedSourceIds: [],
      restoredSourceIds: [],
      insertedFieldIds: [],
      restoredFieldIds: [],
    );

    _planTags(archive.tags, existingTags, result, freshId);
    _planSources(archive.publishedSources, existingSources, result, freshId);
    _planFields(archive.customFields, existingFields, result, freshId);

    try {
      for (final tag in archive.tags) {
        final id = result.tagIdByArchiveId[tag.id]!;
        if (result.restoredTagIds.contains(id)) {
          await tags.restore(id, at: now);
        } else if (result.insertedTagIds.contains(id)) {
          final actualId = await tags.upsert(
            Tag(id: id, name: tag.name, color: tag.color),
            at: now,
          );
          if (actualId != id) {
            throw StateError(
              'tag "${tag.name}" resolved to an unexpected receiver id',
            );
          }
        }
      }
      for (final source in archive.publishedSources) {
        final id = result.sourceIdByArchiveId[source.id]!;
        if (result.restoredSourceIds.contains(id)) {
          await sources.restore(id, at: now);
        } else if (result.insertedSourceIds.contains(id)) {
          await sources.upsert(
            PublishedSource(
              id: id,
              title: source.title,
              author: source.author,
              year: source.year,
              url: source.url,
              notes: source.notes,
            ),
            at: now,
          );
        }
      }
      for (final field in archive.customFields) {
        final id = result.fieldIdByArchiveId[field.id]!;
        if (result.restoredFieldIds.contains(id)) {
          await customFields.restore(id, at: now);
        } else if (result.insertedFieldIds.contains(id)) {
          final actualId = await customFields.upsert(
            CustomFieldDef(
              id: id,
              key: field.key,
              label: field.label,
              type: field.type,
              choices: field.choices,
              showInList: field.showInList,
              searchable: field.searchable,
              shareable: field.shareable,
            ),
            at: now,
          );
          if (actualId != id) {
            throw StateError(
              'custom field "${field.key}" resolved to an unexpected receiver id',
            );
          }
        }
      }
      return result;
    } catch (_) {
      await undo(result);
      rethrow;
    }
  }

  Future<void> undo(ShareMetadataImportResult result) async {
    await customFields.hardDelete(result.insertedFieldIds);
    for (final id in result.restoredFieldIds) {
      await customFields.delete(id);
    }
    await sources.hardDelete(result.insertedSourceIds);
    for (final id in result.restoredSourceIds) {
      await sources.delete(id);
    }
    await tags.hardDelete(result.insertedTagIds);
    for (final id in result.restoredTagIds) {
      await tags.delete(id);
    }
  }

  void _planTags(
    List<Tag> incoming,
    List<({Tag tag, bool deleted})> existing,
    ShareMetadataImportResult result,
    String Function() newId,
  ) {
    final byName = <String, ({Tag tag, bool deleted})>{
      for (final item in existing) item.tag.name: item,
    };
    for (final tag in incoming) {
      final match = byName[tag.name];
      if (match != null) {
        result.tagIdByArchiveId[tag.id] = match.tag.id;
        if (match.deleted) result.restoredTagIds.add(match.tag.id);
      } else {
        final id = newId();
        result.tagIdByArchiveId[tag.id] = id;
        result.insertedTagIds.add(id);
        byName[tag.name] = (
          tag: Tag(id: id, name: tag.name, color: tag.color),
          deleted: false,
        );
      }
    }
  }

  void _planSources(
    List<PublishedSource> incoming,
    List<({PublishedSource source, bool deleted})> existing,
    ShareMetadataImportResult result,
    String Function() newId,
  ) {
    final planned = <String, ({PublishedSource source, bool deleted})>{};
    for (final source in incoming) {
      ({PublishedSource source, bool deleted})? match;
      for (final item in existing) {
        if (_sameSource(item.source, source)) {
          match = item;
          break;
        }
      }
      if (match == null) {
        for (final item in planned.values) {
          if (_sameSource(item.source, source)) {
            match = item;
            break;
          }
        }
      }
      if (match != null) {
        result.sourceIdByArchiveId[source.id] = match.source.id;
        if (match.deleted) result.restoredSourceIds.add(match.source.id);
        continue;
      }
      final id = newId();
      result.sourceIdByArchiveId[source.id] = id;
      result.insertedSourceIds.add(id);
      planned[id] = (
        source: PublishedSource(
          id: id,
          title: source.title,
          author: source.author,
          year: source.year,
          url: source.url,
          notes: source.notes,
        ),
        deleted: false,
      );
    }
  }

  void _planFields(
    List<CustomFieldDef> incoming,
    List<({CustomFieldDef field, bool deleted})> existing,
    ShareMetadataImportResult result,
    String Function() newId,
  ) {
    final byKey = <String, ({CustomFieldDef field, bool deleted})>{
      for (final item in existing) item.field.key: item,
    };
    for (final field in incoming) {
      final match = byKey[field.key];
      if (match != null) {
        if (!_sameField(match.field, field)) {
          throw StateError(
            'shared archive custom field conflicts with local key "${field.key}"',
          );
        }
        result.fieldIdByArchiveId[field.id] = match.field.id;
        if (match.deleted) result.restoredFieldIds.add(match.field.id);
      } else {
        final id = newId();
        result.fieldIdByArchiveId[field.id] = id;
        result.insertedFieldIds.add(id);
        byKey[field.key] = (
          field: CustomFieldDef(
            id: id,
            key: field.key,
            label: field.label,
            type: field.type,
            choices: field.choices,
            showInList: field.showInList,
            searchable: field.searchable,
            shareable: field.shareable,
          ),
          deleted: false,
        );
      }
    }
  }

  static bool _sameSource(PublishedSource a, PublishedSource b) =>
      a.title == b.title &&
      a.author == b.author &&
      a.year == b.year &&
      a.url == b.url &&
      a.notes == b.notes;

  static bool _sameField(CustomFieldDef a, CustomFieldDef b) =>
      a.key == b.key &&
      a.label == b.label &&
      a.type == b.type &&
      _listEquals(a.choices, b.choices) &&
      a.showInList == b.showInList &&
      a.searchable == b.searchable &&
      a.shareable == b.shareable;

  static bool _listEquals(List<String>? a, List<String>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static void _validateDuplicateIds(CompendiumArchive archive) {
    _validateDuplicates(archive.tags, (tag) => tag.id);
    _validateDuplicates(archive.publishedSources, (source) => source.id);
    _validateDuplicates(archive.customFields, (field) => field.id);
  }

  static void _validateReferences(CompendiumArchive archive) {
    final tagIds = {for (final tag in archive.tags) tag.id};
    final sourceIds = {
      for (final source in archive.publishedSources) source.id,
    };
    final fieldIds = {for (final field in archive.customFields) field.id};
    for (final dance in archive.dances) {
      for (final id in dance.tagIds) {
        if (!tagIds.contains(id)) {
          throw StateError(
            'shared archive dance "${dance.id}" references missing tag "$id"',
          );
        }
      }
      for (final citation in dance.sourceCitations) {
        if (!sourceIds.contains(citation.sourceId)) {
          throw StateError(
            'shared archive dance "${dance.id}" references missing source '
            '"${citation.sourceId}"',
          );
        }
      }
      for (final value in dance.customFields) {
        if (!fieldIds.contains(value.fieldId)) {
          throw StateError(
            'shared archive dance "${dance.id}" references missing custom '
            'field "${value.fieldId}"',
          );
        }
      }
    }
  }

  static void _validateDuplicates<T>(
    List<T> values,
    String Function(T value) idOf,
  ) {
    final seen = <String, T>{};
    for (final value in values) {
      final id = idOf(value);
      final prior = seen[id];
      if (prior != null && prior != value) {
        throw StateError(
          'shared archive contains conflicting metadata id "$id"',
        );
      }
      seen[id] = value;
    }
  }
}
