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
  });

  final CompendiumArchive archive;
  final List<ArchiveError> errors;
  final List<String> warnings;

  bool get hasErrors => errors.isNotEmpty;
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
