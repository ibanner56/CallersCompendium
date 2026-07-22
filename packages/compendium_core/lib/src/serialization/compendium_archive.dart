import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../model/choreographer.dart';
import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/program.dart';
import '../model/published_source.dart';
import '../model/tag.dart';

const ListEquality<Object?> _listEq = ListEquality<Object?>();

/// Current version of the canonical [CompendiumArchive] JSON schema.
///
/// Bumped when the archive envelope or an entity's serialized shape changes in
/// a way a reader must know about. The reader is forward-compatible: it
/// tolerates unknown fields and reads an archive written by a newer version on
/// a best-effort basis (known fields only), surfacing a warning rather than
/// failing.
const int archiveSchemaVersion = 1;

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
/// slots), custom-field definitions, tags, choreographers, and published
/// sources — at full fidelity. App-local concerns (settings, dialect library,
/// themes) are intentionally excluded; they are layered in at ROADMAP G.5.
///
/// Serialize with `encodeArchive`/`decodeArchive` in `archive_codec.dart`.
@immutable
class CompendiumArchive {
  const CompendiumArchive({
    this.schemaVersion = archiveSchemaVersion,
    required this.exportedAt,
    this.dances = const [],
    this.programs = const [],
    this.choreographers = const [],
    this.publishedSources = const [],
    this.customFields = const [],
    this.tags = const [],
  });

  /// The [archiveSchemaVersion] this archive was written under.
  final int schemaVersion;

  /// When the archive was produced (UTC).
  final DateTime exportedAt;

  final List<Dance> dances;
  final List<Program> programs;
  final List<Choreographer> choreographers;
  final List<PublishedSource> publishedSources;
  final List<CustomFieldDef> customFields;
  final List<Tag> tags;

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
      _listEq.equals(other.tags, tags);

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
