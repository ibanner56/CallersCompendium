import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../model/choreographer.dart';
import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/program.dart';
import '../model/published_source.dart';
import '../model/tag.dart';
import '../model/venue.dart';

const ListEquality<Object?> _listEq = ListEquality<Object?>();

/// Current version of the canonical [CompendiumArchive] JSON schema.
///
/// Bumped when the archive envelope or an entity's serialized shape changes in
/// a way a reader must know about. The reader is forward-compatible: it
/// tolerates unknown fields and reads an archive written by a newer version on
/// a best-effort basis (known fields only), surfacing a warning rather than
/// failing.
///
/// Version history:
/// * **v1** — the original envelope: dances, programs, choreographers,
///   published sources, custom fields, tags.
/// * **v2** — adds the schema-v14 venue entity: an optional top-level `venues`
///   array and a `program.venueId` soft link. A **v1** reader silently ignores
///   both, so an archive that actually carries venue data is stamped v2 (see
///   [requiredSchemaVersion]) to trip the "newer than supported" warning
///   instead of dropping the venue records. Venue-*less* archives keep being
///   stamped v1 so pre-venue readers still accept them byte-compatibly.
const int archiveSchemaVersion = archiveSchemaVersionVenues;

/// The original, pre-venue archive envelope version.
const int archiveSchemaVersionBase = 1;

/// The envelope version introduced with the schema-v14 venue entity (see
/// [archiveSchemaVersion]).
const int archiveSchemaVersionVenues = 2;

/// The minimum envelope version required to represent [archive] without silent
/// data loss on an older reader: [archiveSchemaVersionVenues] when it carries
/// any venue data (a non-empty `venues` list, or any program with a non-null
/// `venueId`), otherwise [archiveSchemaVersionBase].
///
/// The encoder stamps the wire version at `max(archive.schemaVersion, this)` so
/// venue-bearing archives always advertise v2 (old readers warn instead of
/// dropping venues) while venue-less archives stay backward-compatible at v1 —
/// and an explicitly higher requested version is still honored.
int requiredSchemaVersion(CompendiumArchive archive) =>
    archive.venues.isNotEmpty || archive.programs.any((p) => p.venueId != null)
    ? archiveSchemaVersionVenues
    : archiveSchemaVersionBase;

/// How a [CompendiumArchive] is applied to a live dataset on restore.
enum RestoreMode {
  /// Full-replace: the existing collection is cleared and the archive becomes
  /// the entire dataset. This is the backup/restore semantics and the one
  /// under which the round-trip identity property holds.
  replace,

  /// Merge: the archive is layered onto the existing collection by id — new
  /// entities are inserted and existing ids are updated (id-keyed upsert). Fuzzy
  /// dedupe-driven conflict resolution (link/duplicate/skip via
  /// `src/imports/dedupe.dart`) for user-to-user sharing is deferred to ROADMAP
  /// G.5; this mode does not yet consult those primitives.
  merge,
}

/// A versioned, full-fidelity snapshot of the core-persisted collection.
///
/// This is the in-memory form of the canonical JSON backup/exchange format
/// (`docs/design/imports.md` §"Generic JSON (6.6)"). It carries user *content*
/// — dances (with figures, links, citations, provenance), programs (with
/// slots), custom-field definitions, tags, choreographers, published sources,
/// and venues — at full fidelity. App-local concerns (settings, dialect library,
/// themes) are intentionally excluded; they are layered in at ROADMAP G.5.
///
/// Serialize with `encodeArchive`/`decodeArchive` in `archive_codec.dart`.
@immutable
class CompendiumArchive {
  const CompendiumArchive({
    this.schemaVersion = archiveSchemaVersionBase,
    required this.exportedAt,
    this.dances = const [],
    this.programs = const [],
    this.choreographers = const [],
    this.publishedSources = const [],
    this.customFields = const [],
    this.tags = const [],
    this.venues = const [],
  });

  /// The [archiveSchemaVersion] this archive is stamped as. Defaults to
  /// [archiveSchemaVersionBase]; the encoder raises the version it actually
  /// writes to at least [requiredSchemaVersion] so a venue-bearing archive is
  /// always advertised as v2 even when constructed with the default.
  final int schemaVersion;

  /// When the archive was produced (UTC).
  final DateTime exportedAt;

  final List<Dance> dances;
  final List<Program> programs;
  final List<Choreographer> choreographers;
  final List<PublishedSource> publishedSources;
  final List<CustomFieldDef> customFields;
  final List<Tag> tags;

  /// Reusable venue entities referenced by programs' `venueId`. Added
  /// alongside the schema-v14 venue entity; older archives simply omit the
  /// `venues` array and decode to an empty list.
  final List<Venue> venues;

  @override
  bool operator ==(Object other) =>
      other is CompendiumArchive &&
      other.schemaVersion == schemaVersion &&
      other.exportedAt == exportedAt &&
      _listEq.equals(other.dances, dances) &&
      _listEq.equals(other.programs, programs) &&
      _listEq.equals(other.choreographers, choreographers) &&
      _listEq.equals(other.publishedSources, publishedSources) &&
      _listEq.equals(other.customFields, customFields) &&
      _listEq.equals(other.tags, tags) &&
      _listEq.equals(other.venues, venues);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    exportedAt,
    _listEq.hash(dances),
    _listEq.hash(programs),
    _listEq.hash(choreographers),
    _listEq.hash(publishedSources),
    _listEq.hash(customFields),
    _listEq.hash(tags),
    _listEq.hash(venues),
  );
}

/// The number of entities a shared/imported [archive] would write into the
/// collection: its dances, their author choreographers, its programs, and the
/// venues those programs reference. Program slots ride inside their program and
/// the published-source / custom-field / tag metadata is not committed by the
/// import path, so none of those is counted separately.
///
/// Used by the share-target intake (issue #432) to decide whether an incoming
/// bundle is unusually large (a **soft** cap). The count is derived once from
/// the already-validated, Dart-side-decoded archive — never trusted from any
/// self-reported field in the untrusted bundle — and drives an advisory warning
/// on the review screen, not a hard block.
int compendiumArchiveEntityCount(CompendiumArchive archive) =>
    archive.dances.length +
    archive.choreographers.length +
    archive.programs.length +
    archive.venues.length;

/// Which phase produced an [ArchiveError].
enum ArchiveErrorKind {
  /// Raised while decoding archive JSON into the in-memory model.
  read,

  /// Raised while writing a decoded archive into a live dataset.
  restore,
}

/// A structured archive failure carrying entity context, so the UI can report
/// "dance `<id>` could not be read" rather than surfacing a raw stack trace
/// (`docs/design/imports.md`, "Error handling & testing").
///
/// Errors are values, not thrown control flow, on the per-entity path: a
/// decode/restore collects them and processes the rest (partial-failure
/// tolerance). They *may* wrap an underlying [cause] for logging, but the
/// [message] is the user-facing text and never a stack trace.
@immutable
class ArchiveError {
  const ArchiveError({
    required this.kind,
    required this.entityType,
    required this.message,
    this.entityId,
    this.cause,
  });

  final ArchiveErrorKind kind;

  /// The kind of entity this error concerns (e.g. `dance`, `program`), or
  /// `archive` for envelope-level problems.
  final String entityType;

  /// Human-readable, entity-contextual description (no stack traces).
  final String message;

  /// The id of the offending entity, when known.
  final String? entityId;

  /// Optional underlying error for diagnostics/logging only. Never rendered as
  /// UX.
  final Object? cause;

  @override
  String toString() {
    final where = entityId == null ? '' : ' ($entityId)';
    return 'ArchiveError[${kind.name}] $entityType$where: $message';
  }
}

/// Thrown when an in-memory archive contains a custom numeric value that cannot
/// be represented in JSON. The field context points at legacy data that needs
/// repair before the archive can be exported.
class ArchiveEncodingException implements Exception {
  const ArchiveEncodingException({
    required this.danceId,
    required this.fieldId,
  });

  final String danceId;
  final String fieldId;

  @override
  String toString() =>
      'ArchiveEncodingException: dance "$danceId", custom field "$fieldId" '
      'contains a non-finite numeric value';
}

/// Outcome of decoding archive JSON: the recovered [archive] plus any
/// per-entity [errors] and non-fatal [warnings] (e.g. a newer schema version).
///
/// Decoding never throws for recoverable problems — a malformed entity is
/// skipped and recorded in [errors] while the rest of the archive still loads.
@immutable
class ArchiveReadResult {
  const ArchiveReadResult({
    required this.archive,
    this.errors = const [],
    this.warnings = const [],
    this.droppedEntities = const [],
  });

  final CompendiumArchive archive;
  final List<ArchiveError> errors;
  final List<String> warnings;

  /// Entities dropped during decode because they carried an **unknown enum
  /// value** — a field written by a newer app version. Each entry is a
  /// human-readable reference such as `dance (d2)`.
  ///
  /// Deliberately distinct from [errors]: a drop is forward-compatible (not
  /// corruption), so a *merge* can safely tolerate it and keep the survivors.
  /// But it also means the decoded [archive] is **not a faithful copy** of its
  /// source — it is missing entities. A destructive *replace* restore off such
  /// an archive would silently discard the dropped entities, so callers MUST
  /// refuse replace mode when this is non-empty (issue #430). It is surfaced
  /// separately from [warnings] precisely so this "incomplete" signal cannot be
  /// lost among benign, non-structural warnings.
  final List<String> droppedEntities;

  bool get hasErrors => errors.isNotEmpty;

  /// Whether decode dropped any entity for forward-compatibility reasons.
  /// An incomplete archive must never drive a destructive replace restore.
  bool get isIncomplete => droppedEntities.isNotEmpty;
}

/// Outcome of applying an archive to a live dataset.
@immutable
class ArchiveRestoreResult {
  const ArchiveRestoreResult({
    this.errors = const [],
    this.warnings = const [],
  });

  final List<ArchiveError> errors;
  final List<String> warnings;

  bool get hasErrors => errors.isNotEmpty;
}
