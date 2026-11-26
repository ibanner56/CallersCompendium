import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../model/choreographer.dart';
import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/difficulty_level.dart';
import '../model/enums.dart';
import '../model/formation.dart';
import '../model/program.dart';
import '../model/published_source.dart';
import '../model/tag.dart';
import '../model/user_glossary.dart';
import '../model/venue.dart';
import '../model/figure_source.dart';
import '../model/tunes_source.dart';

const ListEquality<Object?> _listEq = ListEquality<Object?>();
const DeepCollectionEquality _deepEq = DeepCollectionEquality();

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
/// * **v3** — adds ordered `difficultyLevels` and the stable
///   `dance.difficultyLevelId` relationship.
/// * **v4** — adds the optional `programSlot.isPurgedDance` discriminator.
/// * **v5** — adds `dance.figuresRaw`, the stored transcription of a dance that
///   could not be decoded, carried verbatim beside a well-formed empty
///   `figures` array. Stamped only on an archive that contains one, so a
///   healthy library still writes v1-v4 byte-identically. See
///   [archiveSchemaVersionUnreadableFigures] for why the bump is what makes an
///   older reader's loss audible rather than silent.
/// * **v6** — adds `dance.tunesRaw`, the stored tune list of a dance whose
///   `tunes_json` could not be decoded, carried verbatim beside a well-formed
///   empty `tunes` array. Stamped only when such a dance is present, so an
///   archive with undecodable figures but readable tunes still stamps v5.
/// * **v7** — adds `deletedTags`: tombstoned tags with their deletion instant
///   and the dances whose retained `dance_tags` row still points at them, so a
///   full backup restores a deleted tag and its association. Written by backup
///   mode only, and only when a tombstoned tag exists. See
///   [archiveSchemaVersionDeletedTags].
/// * **v8** — adds a dance's `meter` and `musicalKey`, `formation.improper`,
///   and the ECD formation shapes (ADR-006 §12, F2 and F3), its interpreters,
///   its `alternateTitles` and its `barnesReference`, and the square fields
///   (ADR-007 §8.1: `squareKind`, `repeatOrder`, `repeatOrderText`,
///   `newPartner`, `newPartnerText`, `singing`, `freeForm`). Stamped only
///   when a dance carries one of them. See
///   [archiveSchemaVersionEcdDanceFields].
///   Also a program's times, `startMinute`, `endMinute`, `lessonMinute` and
///   `arrivalMinute` (#2350), which joined v8 while it was unreleased. See
///   [archiveSchemaVersionProgramTimes].
///   Also a shared archive's `userFigures` section (#1023), written
///   unversioned from #1804 and stamped from #1885, which joined v8 while it
///   was unreleased: the stamp waited until no supported build refused a
///   newer archive at the share sheet. See [archiveSchemaVersionUserFigures].
const int archiveSchemaVersion = archiveSchemaVersionEcdDanceFields;

/// The original, pre-venue archive envelope version.
const int archiveSchemaVersionBase = 1;

/// The envelope version introduced with the schema-v14 venue entity (see
/// [archiveSchemaVersion]).
const int archiveSchemaVersionVenues = 2;

/// The envelope version introduced with configurable difficulty-level entities
/// and stable dance difficulty-level IDs.
const int archiveSchemaVersionDifficultyLevels = 3;

/// The envelope version introduced for explicit text-only purge captions.
const int archiveSchemaVersionProgramSlotMarkers = 4;

/// The envelope version introduced for a dance whose stored transcription could
/// not be decoded, carried verbatim in `figuresRaw` (#1347).
///
/// Stamped **only** on an archive that actually contains such a dance, per
/// [requiredSchemaVersion]. That conditionality is the whole point: a library
/// with no undecodable row still produces a v1-v4 archive, byte-identical to
/// what earlier builds wrote, so upgrading the app does not push anyone's
/// backups to a version their other installs cannot read.
///
/// **What an older reader does, and why the bump is what makes it safe.**
/// A pre-v5 reader ignores `figuresRaw` (unknown keys are skipped) and reads
/// the accompanying empty `figures` array. Without the bump that would be
/// silent: `_figuresFromJson(null)` and an empty array both yield `const []`,
/// so the dance would reconstruct as figureless and the restore would report
/// success — the user's transcription dropped with no signal. With the bump,
/// the same reader instead warns "archive schemaVersion 5 is newer than
/// supported 4; reading known fields only" and the loss becomes visible.
///
/// So: the archive **file** is lossless — the bytes are in it, and a v5 reader
/// reconstructs the case exactly. An older **reader** is not, and cannot be;
/// the bump's job is to make that audible rather than silent.
const int archiveSchemaVersionUnreadableFigures = 5;

/// The envelope version introduced for a dance whose stored tune list could not
/// be decoded, carried verbatim in `tunesRaw` (#1347).
///
/// A separate version from [archiveSchemaVersionUnreadableFigures] for the
/// reason that one exists at all: a v5 reader understands `figuresRaw` and knows
/// nothing of `tunesRaw`, so it would ignore the key and read the accompanying
/// empty `tunes` array — reconstructing the dance with no tunes and reporting
/// success. Stamped only when such a dance is present, so an archive carrying
/// undecodable figures but readable tunes still stamps v5.
const int archiveSchemaVersionUnreadableTunes = 6;

/// The envelope version introduced for tombstoned tags in a full backup.
///
/// Tags are soft-deleted and their `dance_tags` rows are deliberately kept, so a
/// restored tag returns with its dances. Before v7 a backup wrote live tags
/// only, and dance hydration hides tombstoned ones, so a backup/restore round
/// trip silently dropped both the tombstone and the retained association.
///
/// Tombstones live in their own `deletedTags` array rather than inside `tags`
/// on purpose: a pre-v7 reader ignores an unknown key, so it restores exactly
/// the live tags it always did, whereas a `deletedAt` marker inside `tags` would
/// be ignored by that reader and the deleted tag would come back **live**. The
/// bump makes the older reader's omission audible ("newer than supported").
/// Stamped only when the archive carries a tombstoned tag, so a library that has
/// never deleted a tag still writes its earlier version byte-identically.
const int archiveSchemaVersionDeletedTags = 7;

/// The envelope version introduced for the fields English country dance added
/// to a dance (ADR-006 §12, F2 and F3, and §9.2's interpreter credits):
/// `meter`, `musicalKey`, `formation.improper`, `interpreterIds`,
/// `interpretedOn`, and the formation shapes from [FormationShape.dupleMinor]
/// on; two fields any dance can have, `alternateTitles` and
/// `barnesReference`; and the square fields (ADR-007 §8.1), `squareKind`,
/// `repeatOrder`, `repeatOrderText`, `newPartner`, `newPartnerText`,
/// `singing` and `freeForm`. The last nine joined v8 while it was unreleased.
///
/// A pre-v8 reader ignores these keys, so without the bump it would restore
/// the dance without its meter, key, interpreters, other titles, Barnes
/// reference or square fields, and as proper, and report success. A new shape it cannot read at all, and it skips that dance with a
/// warning; the stamp also makes a backup holding one refuse to restore there
/// rather than restore without it. Stamped only when a dance carries one of
/// them, so a library with none still writes its earlier version
/// byte-identically.
const int archiveSchemaVersionEcdDanceFields = 8;

/// The envelope version a program's times are stamped under: `startMinute`,
/// `endMinute`, `lessonMinute` and `arrivalMinute` (#2350, schema v42).
///
/// No build up to 0.10.0 reads them, so without a stamp it would restore or
/// import the program without its times and report success. They travel in
/// program share files as well as backups, so the stamp is the core archive's
/// rather than the backup envelope's: a share file is warned about (or, on a
/// build before the share intake stopped refusing newer archives, refused)
/// instead of losing them silently. Stamped only when a program has a time.
///
/// The same number as [archiveSchemaVersionEcdDanceFields] on purpose: both
/// joined v8 before it was released, and no released build reads either, so
/// a separate number would protect no extra build.
const int archiveSchemaVersionProgramTimes = 8;

/// The envelope version a program's applied event rules are stamped under:
/// `eventRuleIds` (#2340, schema v42).
///
/// No build up to 0.10.0 reads them, so without a stamp it would restore the
/// program with no rule applied and report success. Only a backup carries
/// them (share files strip them, `sanitizeProgramForShare`), but the key is
/// in the program body, which the core archive versions. Stamped only when a
/// program applies a rule.
///
/// The same number as [archiveSchemaVersionProgramTimes] on purpose: v8 had
/// not shipped when this joined it.
const int archiveSchemaVersionEventRules = 8;

/// The envelope version a shared archive's `userFigures` section is stamped
/// under: the definitions of the user's own new figures its dances use
/// (#1023, see [CompendiumArchive.userFigures]).
///
/// A reader that predates the section ignores the unknown key and imports the
/// dances, each use of a figure as the stored line of plain text it carries,
/// and drops the definitions without a word. The stamp makes it warn instead.
/// Stamped only when the section is written: in share mode, and only when a
/// figure is carried. A backup never writes the section (it carries the whole
/// glossary in its own), so it is never stamped on its account.
///
/// From #1804 until #1885 the section was written unversioned, by the
/// maintainer's decision: every build through 0.7.0 refuses a newer archive
/// opened from the share sheet or "Open with", so a stamp would have kept a
/// bundle carrying figures out of those builds there. #1804 also made the
/// share intake let a newer archive through to the review, and every release
/// from 0.8.0 has it, so the stamp waited for 0.7.0's end of life
/// (2026-11-30) and is for releases cut after it.
///
/// The same number as [archiveSchemaVersionEcdDanceFields] on purpose: v8 had
/// not shipped when this joined it, and no released build reads the section's
/// stamp differently, so a separate number would protect no extra build.
const int archiveSchemaVersionUserFigures = 8;

/// Whether [dance] carries anything only a v8 reader understands
/// ([archiveSchemaVersionEcdDanceFields]).
bool _hasEcdDanceFields(Dance dance) =>
    dance.meter.isNotEmpty ||
    dance.musicalKey.isNotEmpty ||
    dance.formation.improper ||
    dance.interpreterIds.isNotEmpty ||
    dance.interpretedOn != null ||
    dance.alternateTitles.isNotEmpty ||
    dance.barnesReference.isNotEmpty ||
    dance.squareKind != SquareKind.main ||
    dance.repeatOrder != SquareRepeatOrder.unstated ||
    dance.newPartner != SquareNewPartner.unstated ||
    dance.singing ||
    dance.freeForm != null ||
    // Every shape before ECD's is one contra offers; any other is newer.
    !contraFormationShapes.contains(dance.formation.shape);

/// The minimum envelope version required to represent [archive] without silent
/// data loss on an older reader: [archiveSchemaVersionProgramSlotMarkers] when
/// it carries a purge-caption marker, [archiveSchemaVersionDifficultyLevels]
/// when it carries configured difficulty levels or a dance-level ID,
/// [archiveSchemaVersionVenues] when it carries any venue data, otherwise
/// [archiveSchemaVersionBase]; and higher versions for the later cases below.
///
/// The encoder stamps the wire version at `max(archive.schemaVersion, this)` so
/// venue-bearing archives always advertise v2 (old readers warn instead of
/// dropping venues) while venue-less archives stay backward-compatible at v1 —
/// and an explicitly higher requested version is still honored.
///
/// [includeDeletedTags] is `false` when the archive is being encoded for
/// sharing, where `deletedTags` is never written, so it must not raise the
/// stamp either.
///
/// [includeUserFigures] is `true` only when the archive is being encoded for
/// sharing, the one mode that writes `userFigures`
/// ([archiveSchemaVersionUserFigures]). It defaults to `false` so that a call
/// without it returns what it did before the section was stamped: the section
/// raises the stamp only where the encoder says it is written.
int requiredSchemaVersion(
  CompendiumArchive archive, {
  bool includeDeletedTags = true,
  bool includeUserFigures = false,
}) {
  final hasDifficulty =
      archive.difficultyLevels.isNotEmpty ||
      archive.dances.any((d) => d.difficultyLevelId != null);
  final hasPurgeMarker = archive.programs.any(
    (p) => p.slots.any((s) => s.isPurgedDance != null),
  );
  // Checked highest-version first, so the first match wins: an ECD dance field
  // or a carried figure of the user's own requires v8, a tombstoned tag
  // requires v7, an undecodable tune
  // list requires v6, and only if there is none does an undecodable
  // transcription pull the archive to v5. Keep new cases in descending version
  // order or a lower version will shadow a higher one.
  if (archive.dances.any(_hasEcdDanceFields)) {
    return archiveSchemaVersionEcdDanceFields;
  }
  if (archive.programs.any((p) => p.hasTimes)) {
    return archiveSchemaVersionProgramTimes;
  }
  if (archive.programs.any((p) => p.eventRuleIds.isNotEmpty)) {
    return archiveSchemaVersionEventRules;
  }
  if (includeUserFigures && archive.userFigures.isNotEmpty) {
    return archiveSchemaVersionUserFigures;
  }
  if (includeDeletedTags && archive.deletedTags.isNotEmpty) {
    return archiveSchemaVersionDeletedTags;
  }
  if (archive.dances.any((d) => d.tunesSource is UnreadableTunes)) {
    return archiveSchemaVersionUnreadableTunes;
  }
  if (archive.dances.any((d) => d.figuresSource is UnreadableFigures)) {
    return archiveSchemaVersionUnreadableFigures;
  }
  if (hasPurgeMarker) return archiveSchemaVersionProgramSlotMarkers;
  if (hasDifficulty) return archiveSchemaVersionDifficultyLevels;
  return archive.venues.isNotEmpty ||
          archive.programs.any((p) => p.venueId != null)
      ? archiveSchemaVersionVenues
      : archiveSchemaVersionBase;
}

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
    this.difficultyLevels = const [],
    this.deletedTags = const [],
    this.userFigures = const [],
  });

  /// The [archiveSchemaVersion] this archive is stamped as. Defaults to
  /// [archiveSchemaVersionBase]; the encoder raises the version it actually
  /// writes to at least [requiredSchemaVersion] so archives carrying new fields
  /// advertise their required version even when constructed with the default.
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

  /// Configurable difficulty vocabulary in display order.
  final List<DifficultyLevel> difficultyLevels;

  /// Tombstoned tags of a full backup ([ArchiveSerializationMode.backup]);
  /// empty in a share archive and in any archive that predates v7.
  final List<ArchivedDeletedTag> deletedTags;

  /// The user's own new figures (#1023) the dances use, as `customFigure`
  /// entries without notes: what a shared archive carries so the receiver can
  /// add them (plan C12). Written in share mode only; a backup carries the
  /// whole glossary in its own section. When written, it stamps
  /// [archiveSchemaVersionUserFigures].
  final List<UserGlossaryEntry> userFigures;

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
      _listEq.equals(other.venues, venues) &&
      _listEq.equals(other.difficultyLevels, difficultyLevels) &&
      _listEq.equals(other.deletedTags, deletedTags) &&
      _deepEq.equals(
        other.userFigures.map(_userFigureFields).toList(),
        userFigures.map(_userFigureFields).toList(),
      );

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
    _listEq.hash(difficultyLevels),
    _listEq.hash(deletedTags),
    _deepEq.hash(userFigures.map(_userFigureFields).toList()),
  );
}

/// What an archive compares of one of [CompendiumArchive.userFigures]: an
/// entry has no equality of its own.
List<Object?> _userFigureFields(UserGlossaryEntry e) => [
  e.id,
  e.kindName,
  e.name,
  e.definition,
  e.description,
  e.keywords,
  e.notes,
  e.payload,
  e.createdAt,
];

/// A tombstoned [Tag] in a full backup: the tag, when it was deleted, and the
/// dances whose retained `dance_tags` row still names it.
///
/// [danceIds] is the same information as a per-dance list of retained tag ids,
/// grouped by tag so that the tombstone and the associations it can restore
/// travel as one record and cannot disagree. It includes tombstoned dances.
@immutable
class ArchivedDeletedTag {
  const ArchivedDeletedTag({
    required this.tag,
    required this.deletedAt,
    this.danceIds = const [],
  });

  final Tag tag;

  /// When the tag was deleted (UTC).
  final DateTime deletedAt;

  final List<String> danceIds;

  @override
  bool operator ==(Object other) =>
      other is ArchivedDeletedTag &&
      other.tag == tag &&
      other.deletedAt == deletedAt &&
      _listEq.equals(other.danceIds, danceIds);

  @override
  int get hashCode => Object.hash(tag, deletedAt, _listEq.hash(danceIds));
}

/// The number of entities a shared/imported [archive] would write into the
/// collection: its dances, their author choreographers, programs, referenced
/// metadata, and the venues those programs reference. Program slots ride inside
/// their program.
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
    archive.venues.length +
    archive.difficultyLevels.length +
    archive.publishedSources.length +
    archive.customFields.length +
    archive.tags.length +
    archive.deletedTags.length;

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
      'contains a non-finite or unrepresentable numeric value';
}

/// Normalizes a domain [ArgumentError] caused by malformed archive content.
///
/// Archive boundaries convert this Dart [Error] into a narrow exception so it
/// can be recorded in an [ArchiveReadResult] or [ArchiveRestoreResult] without
/// also swallowing unrelated programming errors.
class ArchiveContentValidationException implements Exception {
  const ArchiveContentValidationException(this.cause);

  final ArgumentError cause;

  @override
  String toString() => 'ArchiveContentValidationException: $cause';
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
