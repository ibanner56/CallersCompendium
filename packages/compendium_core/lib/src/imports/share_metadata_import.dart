import '../model/custom_field.dart';
import '../model/enums.dart';
import '../model/published_source.dart';
import '../model/tag.dart';
import '../serialization/compendium_archive.dart';
import '../storage/repositories/custom_field_repository.dart';
import '../storage/repositories/published_source_repository.dart';
import '../storage/repositories/tag_repository.dart';
import '../storage/shareable_text.dart';
import 'structured_draft.dart';

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
    List<ImportIssue>? issues,
  }) : issues = issues ?? [];

  final Map<String, String> tagIdByArchiveId;
  final Map<String, String> sourceIdByArchiveId;
  final Map<String, String> fieldIdByArchiveId;
  final List<String> insertedTagIds;
  final List<String> restoredTagIds;
  final List<String> insertedSourceIds;
  final List<String> restoredSourceIds;
  final List<String> insertedFieldIds;
  final List<String> restoredFieldIds;

  /// One `archive_custom_field_key_conflict` note per incoming custom field
  /// that went in under a suffixed key (see [ShareMetadataImporter]).
  final List<ImportIssue> issues;
}

/// Imports only the metadata referenced by a shared archive.
///
/// Archive ids are never trusted as receiver ids. Live compatible records are
/// reused without being overwritten; matching tombstones are revived (exact
/// ones for tags and sources, compatible ones for custom fields); all other
/// records get freshly generated ids.
///
/// A custom field is compatible with the receiver's when the key, the type and
/// (for a choice field) the set of choices match. The receiver's label, choice
/// order, and Show in list / Searchable / Include in sharing settings are their
/// own and never block a match (maintainer decision, 2026-10-29, INTAKE-2). A
/// field that is not compatible is never merged into theirs, which would change
/// what their values mean: it goes to `<key>_2`, `<key>_3`, … (the first free
/// key, or a compatible row already there; a deleted field of another type
/// still holds its key) as the `.USR` import does, with an
/// `archive_custom_field_key_conflict` note
/// (maintainer decision, 2026-10-29 round 2). [preview] raises the same notes
/// before anything is written, so the review can show them.
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
    final plannedFields = _planFields(
      archive.customFields,
      existingFields,
      result,
      freshId,
    );

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
          final planned = plannedFields[id]!;
          final actualId = await customFields.upsert(planned, at: now);
          if (actualId != id) {
            throw StateError(
              'custom field "${planned.key}" resolved to an unexpected '
              'receiver id',
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

  /// The notes [commit] would raise for [archive] against the receiver's
  /// custom fields as they are now, without writing anything. The import
  /// review shows them before the user commits (INTAKE-2).
  Future<List<ImportIssue>> preview(CompendiumArchive archive) async {
    if (archive.customFields.isEmpty) return const [];
    final existingFields = await customFields.listAllWithDeleted();
    final usedIds = {for (final item in existingFields) item.field.id};
    var next = 0;
    String placeholderId() {
      while (true) {
        final id = 'preview-${next++}';
        if (usedIds.add(id)) return id;
      }
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
    _planFields(archive.customFields, existingFields, result, placeholderId);
    return result.issues;
  }

  /// Reverts a committed [result]: removes the definitions, sources and tags
  /// this import created, and re-tombstones the ones it revived.
  ///
  /// Every `permanent` removal here is guarded **inside the repository's own
  /// transaction** (issue #1357). The tag loop used to be the exception: it
  /// read `tags.isInUse` first and skipped, which was check-then-act (this
  /// method opens no transaction of its own, so nothing stopped a dance
  /// acquiring the tag in the gap) and which no other caller of the tag hatch
  /// would have inherited. The check now lives in `TagRepository.delete`, so
  /// this loop catches [StateError] like its three neighbours.
  ///
  /// The **restored** loops keep their `isInUse` reads. Those call the ordinary
  /// tombstoning `delete`, which is deliberately unguarded for tags, so the
  /// check-then-act read is the only thing standing between a restored tag and
  /// a live dance that has since adopted it. Dropping it there would tombstone
  /// a tag out from under a live dance — the opposite of the fix.
  Future<void> undo(ShareMetadataImportResult result) async {
    for (final id in result.insertedFieldIds) {
      try {
        await customFields.delete(id, permanent: true);
      } on CustomFieldInUseException {
        // A surviving local dance may now use this imported definition.
      }
    }
    for (final id in result.restoredFieldIds) {
      try {
        await customFields.delete(id);
      } on CustomFieldInUseException {
        // A surviving local dance may now use this restored definition.
      }
    }
    for (final id in result.insertedSourceIds) {
      try {
        await sources.delete(id, permanent: true);
      } on StateError {
        // A surviving local dance may now cite this imported source.
      }
    }
    for (final id in result.restoredSourceIds) {
      try {
        await sources.delete(id);
      } on StateError {
        // A surviving local dance may now cite this restored source.
      }
    }
    for (final id in result.insertedTagIds) {
      try {
        await tags.hardDelete([id]);
      } on StateError {
        // A surviving live local dance may now carry this imported tag.
      }
    }
    for (final id in result.restoredTagIds) {
      // `delete` (non-permanent) tombstones and is deliberately unguarded, so
      // this read is the guard. See the note on this method.
      if (await tags.isInUse(id)) continue;
      await tags.delete(id);
    }
  }

  void _planTags(
    List<Tag> incoming,
    List<({Tag tag, bool deleted})> existing,
    ShareMetadataImportResult result,
    String Function() newId,
  ) {
    // Group existing rows by the canonical name `TagRepository.upsert` writes
    // and enforces as UNIQUE (`normalizeShareableText`), so a live tag that is
    // canonically equivalent to an incoming one — differing only in Unicode
    // form or in characters the codec strips — is adopted rather than minted
    // into a normalized-unique-name collision on insert.
    //
    // A canonical key can legitimately hold more than one raw row: the
    // normalisation-skip repair leaves canonically-equivalent legacy names
    // (e.g. NFC "café" beside NFD "café") unchanged. The group is therefore
    // kept as a bucket and resolved deterministically by [_bestMatch] — exact
    // raw match, then a live row, then the smallest id — never collapsed to
    // whichever row happened to be seen last.
    final buckets = <String, List<({Tag tag, bool deleted})>>{};
    for (final item in existing) {
      buckets
          .putIfAbsent(normalizeShareableText(item.tag.name), () => [])
          .add(item);
    }
    for (final tag in incoming) {
      final canonical = normalizeShareableText(tag.name);
      final match = _bestMatch(
        buckets[canonical],
        tag.name,
        (c) => c.tag.name,
        (c) => c.tag.id,
        (c) => c.deleted,
      );
      if (match != null) {
        result.tagIdByArchiveId[tag.id] = match.tag.id;
        if (match.deleted) result.restoredTagIds.add(match.tag.id);
      } else {
        final id = newId();
        result.tagIdByArchiveId[tag.id] = id;
        result.insertedTagIds.add(id);
        buckets.putIfAbsent(canonical, () => []).add((
          tag: Tag(id: id, name: tag.name, color: tag.color),
          deleted: false,
        ));
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
    final assignedReceiverIds = <String>{};
    for (final source in incoming) {
      ({PublishedSource source, bool deleted})? match;
      for (final item in existing) {
        if (!assignedReceiverIds.contains(item.source.id) &&
            _sameSource(item.source, source)) {
          match = item;
          break;
        }
      }
      if (match == null) {
        for (final item in planned.entries) {
          if (!assignedReceiverIds.contains(item.key) &&
              _sameSource(item.value.source, source)) {
            assignedReceiverIds.add(item.key);
            match = item.value;
            break;
          }
        }
      }
      if (match != null) {
        result.sourceIdByArchiveId[source.id] = match.source.id;
        assignedReceiverIds.add(match.source.id);
        if (match.deleted) result.restoredSourceIds.add(match.source.id);
        continue;
      }
      final id = newId();
      result.sourceIdByArchiveId[source.id] = id;
      assignedReceiverIds.add(id);
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

  /// Plans every incoming custom field onto a receiver id, and returns the
  /// definitions to insert by their new id.
  Map<String, CustomFieldDef> _planFields(
    List<CustomFieldDef> incoming,
    List<({CustomFieldDef field, bool deleted})> existing,
    ShareMetadataImportResult result,
    String Function() newId,
  ) {
    // Bucket by the canonical key `CustomFieldDefRepository.upsert` writes and
    // enforces as UNIQUE, for the same reason as tags (see [_planTags]): the
    // repair pass can leave canonically-equivalent legacy keys as distinct raw
    // rows, so resolve the bucket deterministically with [_bestMatch] before
    // applying the compatibility check.
    final buckets = <String, List<({CustomFieldDef field, bool deleted})>>{};
    for (final item in existing) {
      buckets
          .putIfAbsent(normalizeShareableText(item.field.key), () => [])
          .add(item);
    }
    // Rows this plan creates. Only a clash with one of the receiver's own rows
    // may name the field in the note: a clash with another field of the same
    // file would echo the file's text (see [ImportIssue.data]).
    final planned = <String, CustomFieldDef>{};
    // Receiver id → the archive field that resolved onto it. Two fields of one
    // file must never resolve to one definition, or a dance carrying both would
    // keep only one of the values (the `.USR` importer's `createdFor` rule).
    final claimedBy = <String, String>{};
    // Places [field] under [key] when the key is free, or holds a compatible
    // row no other field of this file has claimed, and returns null; otherwise
    // returns the row in the way.
    ({CustomFieldDef field, bool deleted})? place(
      CustomFieldDef field,
      String key,
    ) {
      final canonical = normalizeShareableText(key);
      final match = _bestMatch(
        buckets[canonical],
        key,
        (c) => c.field.key,
        (c) => c.field.id,
        (c) => c.deleted,
      );
      if (match == null) {
        final def = CustomFieldDef(
          id: newId(),
          key: key,
          label: field.label,
          type: field.type,
          choices: field.choices,
          showInList: field.showInList,
          searchable: field.searchable,
          shareable: field.shareable,
        );
        result.fieldIdByArchiveId[field.id] = def.id;
        result.insertedFieldIds.add(def.id);
        planned[def.id] = def;
        claimedBy[def.id] = field.id;
        buckets.putIfAbsent(canonical, () => []).add((
          field: def,
          deleted: false,
        ));
        return null;
      }
      final claimed = claimedBy[match.field.id];
      if ((claimed == null || claimed == field.id) &&
          _sameField(match.field, field)) {
        result.fieldIdByArchiveId[field.id] = match.field.id;
        claimedBy[match.field.id] = field.id;
        if (match.deleted) result.restoredFieldIds.add(match.field.id);
        return null;
      }
      return match;
    }

    // Every field tries its own key before any field moves to a numbered one,
    // so where a field lands never depends on the order of the file: a file
    // carrying both `tempo` and its own `tempo_2` keeps `tempo_2` for the
    // latter either way. A file may list the same definition twice; it is
    // planned once.
    final clashes =
        <(CustomFieldDef, ({CustomFieldDef field, bool deleted}))>[];
    for (final field in incoming) {
      if (result.fieldIdByArchiveId.containsKey(field.id)) continue;
      final clash = place(field, field.key);
      if (clash != null) clashes.add((field, clash));
    }
    for (final (field, clash) in clashes) {
      if (result.fieldIdByArchiveId.containsKey(field.id)) continue;
      // `<their key>_2`, `<their key>_3`, … until a free key or a compatible
      // row, so a file received twice lands on the same field again.
      var candidate = '${clash.field.key}_2';
      for (var n = 3; place(field, candidate) != null; n++) {
        candidate = '${clash.field.key}_$n';
      }
      // Named only when a live field of the receiver's really differs: a
      // deleted one is not "theirs" any more, a row this plan made holds the
      // file's text, and a field moved only because another field of the file
      // claimed a compatible row is not "different" from it.
      final theirs =
          !clash.deleted &&
          !planned.containsKey(clash.field.id) &&
          !_sameField(clash.field, field);
      result.issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'archive_custom_field_key_conflict',
          message:
              'shared custom field "${field.key}" (${field.type.name}) '
              'could not use that key; its values go into "$candidate".',
          data: theirs
              ? {'label': clash.field.label, 'key': candidate}
              : const {},
        ),
      );
    }
    return planned;
  }

  /// Chooses which row an incoming record adopts from a canonical-key [bucket].
  ///
  /// A canonical key can map to several raw rows because the normalisation-skip
  /// repair leaves canonically-equivalent legacy values unchanged, so the
  /// choice must be deterministic and independent of load order: an exact raw
  /// match ([rawKey]) wins first, then a live row over a tombstone, then the
  /// smallest id — the same precedence `TagRepository.idByName` applies. Returns
  /// `null` when the key is free.
  static T? _bestMatch<T>(
    List<T>? bucket,
    String rawKey,
    String Function(T) rawOf,
    String Function(T) idOf,
    bool Function(T) deletedOf,
  ) {
    if (bucket == null || bucket.isEmpty) return null;
    return bucket.reduce((best, candidate) {
      final candidateExact = rawOf(candidate) == rawKey;
      final bestExact = rawOf(best) == rawKey;
      if (candidateExact != bestExact) return candidateExact ? candidate : best;
      if (deletedOf(candidate) != deletedOf(best)) {
        return deletedOf(candidate) ? best : candidate;
      }
      return idOf(candidate).compareTo(idOf(best)) < 0 ? candidate : best;
    });
  }

  static bool _sameSource(PublishedSource a, PublishedSource b) =>
      a.title == b.title &&
      a.author == b.author &&
      a.year == b.year &&
      a.url == b.url &&
      a.notes == b.notes;

  /// Whether an incoming field means the same as receiver row [a]: the type
  /// and, for a choice field, the same set of choices. The caller matched the
  /// key already (canonically, so an NFC/NFD-equivalent key is the same key).
  ///
  /// The label, the choice order and the three display settings are the
  /// receiver's own and are deliberately not compared (INTAKE-2): a label that
  /// differs only in case (Caller's Companion's "Card" and "card" make the
  /// same key) or a field the receiver keeps out of sharing is still theirs.
  /// Choices are compared canonically (`normalizeShareableText`), as both
  /// the definition's choices and a dance's value are stored that way.
  static bool _sameField(CustomFieldDef a, CustomFieldDef b) =>
      a.type == b.type &&
      (a.type != CustomFieldType.choice ||
          _sameChoices(a.choices ?? const [], b.choices ?? const []));

  static bool _sameChoices(List<String> a, List<String> b) {
    final setA = a.map(normalizeShareableText).toSet();
    final setB = b.map(normalizeShareableText).toSet();
    return setA.length == setB.length && setA.containsAll(setB);
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
