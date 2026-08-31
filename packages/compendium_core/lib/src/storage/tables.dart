import 'package:drift/drift.dart';

import '../model/enums.dart';
import '../model/formation.dart';

// Design: docs/design/storage.md. `dance_figures` is a derived, rebuildable
// index over `dances.figures_json` (the authoritative store); `dance_fts` is
// a second derived index, created as a raw FTS5 virtual table (see
// database.dart) rather than a typed drift table, because it is
// content-less (`content=''`) and only ever written by the repository layer
// that also owns `dance_figures` — a typed table adds no safety there.
//
// ---------------------------------------------------------------------------
// The sync timestamp triple (`updated_at`, `deleted_at`, `existence_at`)
// ---------------------------------------------------------------------------
//
// Every *syncable kind* — dances, programs, choreographers, tags, published
// sources, custom field defs, venues, and settings keys — carries all three,
// as of schema v25 (issue #898). They answer three different questions and
// deliberately are not collapsed into fewer columns:
//
//   * `updated_at`   — which copy's **content** is newer. The merge
//                      discriminator. Advanced by any write that changes what
//                      the record would serialise.
//   * `deleted_at`   — **retention**: NULL means live, non-NULL is a
//                      tombstone and starts the purge / "Recently Deleted"
//                      countdown.
//   * `existence_at` — which **existence transition** (live -> deleted, or
//                      deleted -> live) happened later. Stamped *causally*,
//                      as `max(localNow, currentExistenceAt + 1 tick)`, rather
//                      than from a bare clock, so a transition is always
//                      strictly later than the one it supersedes even when the
//                      local clock is behind or has not advanced.
//
// `existence_at` is separate from `updated_at` because an ordinary content
// edit must NOT read as an existence transition, and separate from
// `deleted_at` because a *revival* has no `deleted_at` to order by — the
// column is NULL precisely when the record is live. Merging any pair of them
// re-creates a defect the third exists to prevent; see `docs/design/sync.md`
// before attempting to simplify.
//
// **Nullability.** All three are nullable on the tables that gained them in
// v25. That is a SQLite constraint, not a semantic one: `ALTER TABLE ... ADD
// COLUMN` refuses a NOT NULL column unless it carries a *constant* default,
// and there is no constant that is a truthful timestamp. The alternative — a
// full 12-step table rebuild per table — was judged disproportionate for a
// migration whose whole design goal is a reviewable blast radius. The v25
// migration backfills every pre-existing row and the repository layer stamps
// every write, so a NULL only appears if a row is written by something that
// bypasses the repositories.
//
// Nothing reads `existence_at` for a merge decision yet; there is no sync
// client. Its only writers are the causal stamping helper and the `restore()`
// paths.

/// Dance transcriptions. `figures_json` is authoritative; `dance_figures`
/// (below) is rebuilt from it on every write.
@DataClassName('DanceRow')
class Dances extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get form =>
      text().map(const EnumNameConverter(DanceForm.values))();
  TextColumn get formationShape =>
      text().map(const EnumNameConverter(FormationShape.values))();
  TextColumn get formationDetail => text().nullable()();
  TextColumn get progression =>
      text().map(const EnumNameConverter(Progression.values))();

  /// Persisted [PhraseStructure.raw] (`''` = the standard 4x16 structure).
  TextColumn get phraseStructure => text().withDefault(const Constant(''))();

  /// `figures_json` — see `serialization/figure_codec.dart`.
  TextColumn get figuresJson => text().withDefault(const Constant('[]'))();
  TextColumn get hook => text().withDefault(const Constant(''))();
  TextColumn get callingNotes => text().withDefault(const Constant(''))();

  /// Free-form step-by-step walkthrough of the dance; dialect-aware free text,
  /// distinct from the short [callingNotes]. Defaults to `''`. Added in schema
  /// v15 (issue #370). Dance-scalar content (not figure text), so it does NOT
  /// feed the derived `dance_figures`/`dance_fts` indexes.
  TextColumn get walkthrough => text().withDefault(const Constant(''))();
  TextColumn get status =>
      text().map(const EnumNameConverter(DanceStatus.values))();

  /// Difficulty on the ordered [DanceLevel] scale, persisted by enum name;
  /// nullable (`null` = unspecified). Added in schema v4 (CC-parity `Level`).
  TextColumn get level =>
      text().nullable().map(const EnumNameConverter(DanceLevel.values))();

  /// Marks a dance that spans the difficulty scale; kept separate from [level]
  /// so the ordered scale stays total. Added in schema v4 (CC `Mixed Level`).
  BoolColumn get mixedLevel => boolean().withDefault(const Constant(false))();

  /// Whether the dance is a **mixer** (dancers change partners each time
  /// through). A boolean flag orthogonal to [formationShape], not a
  /// [FormationShape] value — see `Dance.mixer` for the measured corpus
  /// asymmetry that rules out folding it into the formation enum. Added in
  /// schema v24 (issue #732).
  BoolColumn get mixer => boolean().withDefault(const Constant(false))();

  /// Curatorial star rating on the closed `1..5` scale; nullable (`null` =
  /// unrated). A first-class dance-scalar column (the `1..5` range is validated
  /// at the [Dance] boundary), not an enum or custom field. Added in schema v6
  /// (CC-parity `Rating`).
  IntColumn get rating => integer().nullable()();

  /// JSON array of tune name strings.
  TextColumn get tunesJson => text().withDefault(const Constant('[]'))();

  /// Author composition date at partial precision, persisted as the canonical
  /// [PartialDate] string (`YYYY` / `YYYY-MM` / `YYYY-MM-DD`); nullable.
  /// Added in schema v5. Distinct from the record stamp [createdAt].
  TextColumn get composedOn => text().nullable()();

  /// Author revision date at partial precision, persisted as the canonical
  /// [PartialDate] string; nullable. Added in schema v5. Distinct from the
  /// record stamp [updatedAt].
  TextColumn get revisedOn => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Existence-transition stamp; see the sync-triple note at the top of this
  /// file. Added in schema v25 (issue #898); `dances` already carried the
  /// other two.
  DateTimeColumn get existenceAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Dance authors (choreographers). "Traditional"/"Unknown" are real rows.
@DataClassName('ChoreographerRow')
class Choreographers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get website => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// Private contact email; nullable freeform. Added in schema v7 (CC-parity
  /// author contact). Never emitted in shareable exports (see [Choreographer]).
  TextColumn get email => text().nullable()();

  /// Private freeform locality; nullable. Added in schema v7.
  TextColumn get location => text().nullable()();

  /// Whether the author is deceased; defaults to false. Added in schema v7.
  BoolColumn get deceased => boolean().withDefault(const Constant(false))();

  /// Sync timestamp triple; see the note at the top of this file. Added in
  /// schema v25 (issue #898), which also converted
  /// `ChoreographerRepository.delete` from a hard delete to a tombstone.
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get existenceAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ordered dance <-> choreographer join. `position` gives an unambiguous
/// authorship order (never inferred from row order).
@DataClassName('DanceAuthorRow')
class DanceAuthors extends Table {
  TextColumn get danceId =>
      text().references(Dances, #id, onDelete: KeyAction.cascade)();
  TextColumn get choreographerId =>
      text().references(Choreographers, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {danceId, choreographerId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {danceId, position},
  ];
}

/// Derived, one row per figure, rebuilt from `dances.figures_json` on every
/// dance write. Enables indexed structural search without a full scan
/// (ContraDB's unqueryable-JSON-blob pitfall).
@DataClassName('DanceFigureRow')
class DanceFigures extends Table {
  TextColumn get danceId =>
      text().references(Dances, #id, onDelete: KeyAction.cascade)();
  IntColumn get idx => integer()();

  /// Correlation group: all rows flattened from one **top-level** figure share
  /// this value, and it is monotonic across a dance's top-level figures. Unlike
  /// [idx] (unique per row, as the `{danceId, idx}` PK requires), [groupIdx] is
  /// deliberately **not** unique — the concurrent sides of a `meanwhile`
  /// container (flattened per side, #590) all carry the container's single
  /// [groupIdx]. The `Then` sequence operator correlates on
  /// `a.group_idx < b.group_idx` so two concurrent sides, sharing a group, are
  /// never treated as one-before-the-other (#748). Added in schema v22; existing
  /// rows default to 0 and are repopulated by the derived-index rebuild.
  IntColumn get groupIdx => integer().withDefault(const Constant(0))();
  TextColumn get move => text()();
  IntColumn get beats => integer().withDefault(const Constant(0))();
  BoolColumn get progression => boolean().withDefault(const Constant(false))();

  /// Figure `params` as JSON (queried via SQLite JSON1, `params_json ->> ...`).
  TextColumn get paramsJson => text().withDefault(const Constant('{}'))();

  /// Rendered canonical text (dialect-free); feeds `dance_fts.figures_text`.
  TextColumn get canonicalText => text().withDefault(const Constant(''))();

  /// Derived phrase label (`A1`, `B2`, …) of the phrase in which this figure
  /// *starts* ([SectionedFigure.label]); nullable to stay forward-compatible
  /// with structureless forms. Added in schema v2 for section-aware search.
  TextColumn get section => text().nullable()();

  @override
  Set<Column> get primaryKey => {danceId, idx};
}

/// Programs (event set lists).
@DataClassName('ProgramRow')
class Programs extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  DateTimeColumn get eventDate => dateTime().nullable()();
  TextColumn get venue => text().nullable()();

  /// Optional reference to a first-class [Venues] row (`venues.id`), added in
  /// schema v14. A deliberately un-constrained soft reference (no drift
  /// `.references()`/FK): the free-text [venue] label and this entity link
  /// coexist non-destructively. Referential integrity is enforced at the app
  /// layer instead of by a DB constraint — `ProgramRepository` rejects a write
  /// whose non-null `venueId` has no matching venue (checked inside the write
  /// transaction), and `VenueRepository.delete` atomically refuses to remove a
  /// venue any program still references. Import paths resolve-or-null a dangling
  /// `venueId` before persisting, so a bundle can carry a program whose venue
  /// record is absent without tripping the write-time check.
  TextColumn get venueId => text().nullable()();
  TextColumn get band => text().nullable()();
  TextColumn get caller => text().nullable()();
  TextColumn get dancerLevel => text().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get status =>
      text().map(const EnumNameConverter(ProgramStatus.values))();
  BoolColumn get hideAlternates =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Existence-transition stamp; see the sync-triple note at the top of this
  /// file. Added in schema v25 (issue #898); `programs` already carried the
  /// other two.
  DateTimeColumn get existenceAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One slot in a program. `danceId` is nullable and `SET NULL` on delete —
/// soft-deleted dances are never hard-deleted in normal operation, but a
/// hard purge must not leave a dangling FK; the slot's `text` (if any)
/// survives as a tombstone caption.
@DataClassName('ProgramSlotRow')
class ProgramSlots extends Table {
  TextColumn get id => text()();
  TextColumn get programId =>
      text().references(Programs, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get danceId =>
      text().nullable().references(Dances, #id, onDelete: KeyAction.setNull)();
  TextColumn get text_ => text().nullable().named('text')();
  BoolColumn get isAlt => boolean().withDefault(const Constant(false))();
  TextColumn get guestCaller => text().nullable()();
  IntColumn get plannedMinutes => integer().nullable()();
  DateTimeColumn get performedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Definitions of user-created custom fields.
@DataClassName('CustomFieldDefRow')
class CustomFieldDefs extends Table {
  TextColumn get id => text()();
  TextColumn get key => text().unique()();
  TextColumn get label => text()();
  TextColumn get type =>
      text().map(const EnumNameConverter(CustomFieldType.values))();

  /// JSON array of choice strings; only meaningful for `choice` fields.
  TextColumn get choicesJson => text().nullable()();
  BoolColumn get showInList => boolean().withDefault(const Constant(false))();
  BoolColumn get searchable => boolean().withDefault(const Constant(true))();

  /// Whether this field's values may travel in a shared archive (file export,
  /// share sheet, future sync). Defaults to `true` — all new fields are
  /// shareable unless the user opts out. Set to `false` to exclude the field
  /// definition and every value for it from archive serialisation. Added in
  /// schema v23 (issue #780).
  BoolColumn get shareable => boolean().withDefault(const Constant(true))();

  /// Sync timestamp triple; see the note at the top of this file. Added in
  /// schema v25 (issue #898), which also converted
  /// `CustomFieldDefRepository.delete` from a hard delete to a tombstone.
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get existenceAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Custom field values attached to a dance. Booleans are stored as 0/1 in
/// `valueNum` (see [CustomFieldValue.matchesType] for the source-of-truth
/// typing, enforced by the repository layer before a row is written).
@DataClassName('CustomFieldValueRow')
class CustomFieldValues extends Table {
  TextColumn get danceId =>
      text().references(Dances, #id, onDelete: KeyAction.cascade)();
  TextColumn get fieldId =>
      text().references(CustomFieldDefs, #id, onDelete: KeyAction.cascade)();
  TextColumn get valueText => text().nullable()();
  RealColumn get valueNum => real().nullable()();

  @override
  Set<Column> get primaryKey => {danceId, fieldId};
}

/// Flat user tags.
@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  IntColumn get color => integer().nullable()();

  /// Sync timestamp triple; see the note at the top of this file. Added in
  /// schema v25 (issue #898), which also converted `TagRepository.delete` from
  /// a hard delete to a tombstone. Tags are the one converted kind with **no**
  /// referential guard, so this is also the one whose `dance_tags` rows now
  /// outlive the delete — every read that joins through `tags` filters on
  /// `deleted_at IS NULL` for that reason.
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get existenceAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Dance <-> tag join.
@DataClassName('DanceTagRow')
class DanceTags extends Table {
  TextColumn get danceId =>
      text().references(Dances, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {danceId, tagId};
}

/// A link attached to a dance: source citation, video, related dance, other.
@DataClassName('DanceLinkRow')
class DanceLinks extends Table {
  TextColumn get id => text()();
  TextColumn get danceId =>
      text().references(Dances, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text().map(const EnumNameConverter(LinkKind.values))();
  TextColumn get url => text().nullable()();
  @ReferenceName('relatedDanceLinks')
  TextColumn get targetDanceId =>
      text().nullable().references(Dances, #id, onDelete: KeyAction.setNull)();
  TextColumn get label => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A reusable published source (book, collection, magazine, website) that
/// dances cite. A first-class entity (like [Choreographers]/[Tags]); the
/// per-dance page/number lives on the [DanceSources] join. Added in schema v8.
@DataClassName('PublishedSourceRow')
class PublishedSources extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// Sync timestamp triple; see the note at the top of this file. Added in
  /// schema v25 (issue #898), which also converted
  /// `PublishedSourceRepository.delete` from a hard delete to a tombstone.
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get existenceAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ordered dance <-> published-source join carrying the citation detail
/// (freeform `page`/`number`). `position` gives an unambiguous citation order
/// (never inferred from row order); mirrors [DanceAuthors]. Added in schema v8.
@DataClassName('DanceSourceRow')
class DanceSources extends Table {
  TextColumn get danceId =>
      text().references(Dances, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceId =>
      text().references(PublishedSources, #id, onDelete: KeyAction.cascade)();
  TextColumn get page => text().nullable()();
  TextColumn get number => text().nullable()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {danceId, sourceId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {danceId, position},
  ];
}

/// A reusable venue (hall, church, grange, festival site) that programs are
/// held at. A first-class entity (like [PublishedSources]/[Choreographers]);
/// a program links to it by [Programs.venueId] while the free-text
/// [Programs.venue] label persists independently. Added in schema v14.
///
/// Faithful to Caller's Companion's `Venue` table minus its FileMaker plumbing
/// (`VenueDisplay_c`, `zc_*`/`zi_*`, `zk_Constant`, `SiteID`): CC's stored
/// display column is reimplemented as the computed `Venue.displayName` getter,
/// not persisted here. All columns are `.nullable()` except [id] and [name].
@DataClassName('VenueRow')
class Venues extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get address1 => text().nullable()();
  TextColumn get address2 => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get stateProv => text().nullable()();
  TextColumn get country => text().nullable()();
  TextColumn get postalCode => text().nullable()();
  TextColumn get plus4 => text().nullable()();
  TextColumn get website => text().nullable()();
  TextColumn get sponsor => text().nullable()();
  TextColumn get eventName => text().nullable()();
  TextColumn get time => text().nullable()();
  TextColumn get genericSchedule => text().nullable()();
  TextColumn get price => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get contact1Name => text().nullable()();
  TextColumn get contact1Phone => text().nullable()();
  TextColumn get contact1Email => text().nullable()();
  TextColumn get contact2Name => text().nullable()();
  TextColumn get contact2Phone => text().nullable()();
  TextColumn get contact2Email => text().nullable()();

  /// Sync timestamp triple; see the note at the top of this file. Added in
  /// schema v25 (issue #898), which also converted `VenueRepository.delete`
  /// from a hard delete to a tombstone. [VenueRepository.hardDelete] stays a
  /// hard delete: it exists solely to roll back a just-committed import, and a
  /// rollback must leave no trace to publish.
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get existenceAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Import provenance, one row per venue (at most). Mirrors [Provenance] (the
/// dance provenance table) and [ProgramProvenance]; added in schema v26
/// (issue #899) so re-importing the same bundle recognises a venue that was
/// previously imported from the same source. Provenance-based dedupe is exact
/// (`(source, external_id)` pair), which means it can operate on shared bundles
/// where the postal address has been redacted and the content-fingerprint path
/// ([venueFingerprint]) produces no key.
@DataClassName('VenueProvenanceRow')
class VenueProvenance extends Table {
  TextColumn get venueId =>
      text().references(Venues, #id, onDelete: KeyAction.cascade)();
  TextColumn get source =>
      text().map(const EnumNameConverter(ProvenanceSource.values))();
  TextColumn get externalId => text().nullable()();
  DateTimeColumn get importedAt => dateTime()();
  TextColumn get permission => text().nullable()();
  TextColumn get license => text().nullable()();
  TextColumn get sourceVersion => text().nullable()();

  @override
  Set<Column> get primaryKey => {venueId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {source, externalId},
  ];
}

/// Import provenance, one row per dance (at most).
///
/// Carried a `raw_payload` column (the verbatim imported source record) until
/// schema v21, when it was dropped: nothing ever read it, and for an HTML
/// import it stored the whole source page — kilobytes per dance that
/// round-tripped through every backup (#781).
@DataClassName('ProvenanceRow')
class Provenance extends Table {
  TextColumn get danceId =>
      text().references(Dances, #id, onDelete: KeyAction.cascade)();
  TextColumn get source =>
      text().map(const EnumNameConverter(ProvenanceSource.values))();
  TextColumn get externalId => text().nullable()();
  DateTimeColumn get importedAt => dateTime()();
  TextColumn get permission => text().nullable()();
  TextColumn get license => text().nullable()();
  TextColumn get sourceVersion => text().nullable()();

  @override
  Set<Column> get primaryKey => {danceId};
}

/// Import provenance, one row per program (at most). Mirrors [Provenance]
/// (the dance provenance table); added in schema v10 so re-importing a
/// Caller's Companion `.USR` dedupes Sets onto the same program (keyed on
/// `(source, externalId)`) instead of creating duplicates. `null`-provenance
/// (user-created) programs simply have no row here and never dedupe.
///
/// Carried a `raw_payload` column until schema v21, when it was dropped
/// alongside [Provenance]'s. On this table it was doubly redundant: no import
/// path ever wrote it, so it was null for every row in existence (#781).
@DataClassName('ProgramProvenanceRow')
class ProgramProvenance extends Table {
  TextColumn get programId =>
      text().references(Programs, #id, onDelete: KeyAction.cascade)();
  TextColumn get source =>
      text().map(const EnumNameConverter(ProvenanceSource.values))();
  TextColumn get externalId => text().nullable()();
  DateTimeColumn get importedAt => dateTime()();
  TextColumn get permission => text().nullable()();
  TextColumn get license => text().nullable()();
  TextColumn get sourceVersion => text().nullable()();

  @override
  Set<Column> get primaryKey => {programId};
}

/// One idempotent row per published collection version imported on this device.
///
/// The digest is retained so the app can display which immutable archive was
/// imported without deriving that fact from the surviving dances.
@DataClassName('CollectionImportEventRow')
class CollectionImportEvents extends Table {
  TextColumn get collectionId => text()();
  TextColumn get version => text()();
  TextColumn get archiveDigest => text()();
  DateTimeColumn get importedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {collectionId, version};
}

/// Free-form app settings (dialect choice, prefs, source URLs), keyed by a
/// stable string key; `valueJson` holds an arbitrary JSON-encoded value.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();

  /// Sync timestamp triple; see the note at the top of this file. Added in
  /// schema v25 (issue #898), which also converted `SettingsRepository.remove`
  /// from a hard delete to a tombstone — without one, a removed setting cannot
  /// be expressed on the wire and a peer would resurrect it.
  ///
  /// Note the internal control markers this table also holds
  /// ([derivedRebuildRequiredKey] and friends). Those are cleared by a raw
  /// `DELETE` in `CompendiumRepositories`, deliberately *not* tombstoned: they
  /// are migration bookkeeping, not user data, and a tombstoned marker read
  /// back as present would re-run or skip a one-time repair.
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get existenceAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Durable records for unique natural-key values that could not yet be
/// normalized because another row occupies the transformed value.
@DataClassName('NormalisationSkipRow')
class NormalisationSkips extends Table {
  TextColumn get tableNameValue => text().named('table_name')();
  TextColumn get columnNameValue => text().named('column_name')();
  TextColumn get recordId => text()();

  @override
  Set<Column> get primaryKey => {tableNameValue, columnNameValue, recordId};
}

// A `snapshots` table lived here until schema v21. It recorded the
// last-imported snapshot per external source so the app could offer "update
// available" prompts for a hosted CallersBox archive — a feature that was
// then cut (ROADMAP 6.2/6.3, and `docs/design/callersbox-snapshot.md`, which
// is marked superseded: the app imports directly from the source instead).
// The table, its repository and its test were dropped in #782; nothing ever
// wrote a row.
