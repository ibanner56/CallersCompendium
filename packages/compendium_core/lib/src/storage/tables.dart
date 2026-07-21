import 'package:drift/drift.dart';

import '../model/enums.dart';
import '../model/formation.dart';

// Design: docs/design/storage.md. `dance_figures` is a derived, rebuildable
// index over `dances.figures_json` (the authoritative store); `dance_fts` is
// a second derived index, created as a raw FTS5 virtual table (see
// database.dart) rather than a typed drift table, because it is
// content-less (`content=''`) and only ever written by the repository layer
// that also owns `dance_figures` — a typed table adds no safety there.

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
  TextColumn get status =>
      text().map(const EnumNameConverter(DanceStatus.values))();

  /// Difficulty on the ordered [DanceLevel] scale, persisted by enum name;
  /// nullable (`null` = unspecified). Added in schema v4 (CC-parity `Level`).
  TextColumn get level =>
      text().nullable().map(const EnumNameConverter(DanceLevel.values))();

  /// Marks a dance that spans the difficulty scale; kept separate from [level]
  /// so the ordered scale stays total. Added in schema v4 (CC `Mixed Level`).
  BoolColumn get mixedLevel => boolean().withDefault(const Constant(false))();

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
  /// schema v13. A deliberately un-constrained soft reference (no drift
  /// `.references()`/FK): the free-text [venue] label and this entity link
  /// coexist non-destructively, and referential integrity is enforced at the
  /// app layer by `VenueRepository.delete`'s guard rather than a DB constraint
  /// (so an import can carry a program whose venue record is absent without
  /// tripping a foreign key).
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
/// [Programs.venue] label persists independently. Added in schema v13.
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

  @override
  Set<Column> get primaryKey => {id};
}

/// Import provenance, one row per dance (at most).
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
  TextColumn get rawPayload => text().nullable()();
  TextColumn get sourceVersion => text().nullable()();

  @override
  Set<Column> get primaryKey => {danceId};
}

/// Import provenance, one row per program (at most). Mirrors [Provenance]
/// (the dance provenance table); added in schema v10 so re-importing a
/// Caller's Companion `.USR` dedupes Sets onto the same program (keyed on
/// `(source, externalId)`) instead of creating duplicates. `null`-provenance
/// (user-created) programs simply have no row here and never dedupe.
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
  TextColumn get rawPayload => text().nullable()();
  TextColumn get sourceVersion => text().nullable()();

  @override
  Set<Column> get primaryKey => {programId};
}

/// Free-form app settings (dialect choice, prefs, source URLs), keyed by a
/// stable string key; `valueJson` holds an arbitrary JSON-encoded value.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Records the last-imported snapshot per external source (e.g. a hosted
/// CallersBox archive), so the app can offer "update available" prompts.
@DataClassName('SnapshotRow')
class Snapshots extends Table {
  TextColumn get source => text()();
  DateTimeColumn get snapshotDate => dateTime()();
  TextColumn get manifestJson => text()();
  DateTimeColumn get importedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {source};
}
