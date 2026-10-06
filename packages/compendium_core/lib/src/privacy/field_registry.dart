import 'data_classification.dart';

/// The classification of every column the database persists, keyed by
/// `table.column` using the **SQL** names (as they appear in the schema, not
/// the Dart field names).
///
/// Adding a column without adding an entry here fails
/// `test/privacy/data_classification_coverage_test.dart`. That is the point:
/// the catalogue cannot silently fall behind the schema.
///
/// See `docs/dev/data-classification.md` for the rendered catalogue and for
/// guidance on choosing a classification.

/// Dance choreography and its structural metadata. Not about a person, and
/// shareable by design — a collection of dances is the thing users want to move
/// between devices, and the project's position is that choreography is not user
/// data.
const _choreography = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.none,
  egress: EgressClass.shareable,
);

/// An opaque surrogate key. Carries no meaning alone, but must travel for
/// relationships to survive a transfer.
const _key = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.none,
  egress: EgressClass.shareable,
  isIdentity: true,
  note:
      'Opaque identifier; meaningless alone, required for relational integrity '
      'across a transfer.',
);

/// A rebuildable index. Never transmitted: the receiving device recomputes it,
/// so sending it would be redundant as well as an extra copy to protect.
const _derivedIndex = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.none,
  egress: EgressClass.derived,
  note: 'Rebuilt from authoritative columns on write; recomputed on arrival.',
);

/// A record stamp. Not about the user as a person, but about their activity;
/// must travel because ordering across devices is defined in terms of it.
const _recordStamp = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.none,
  egress: EgressClass.shareable,
  note:
      'Record stamp, not author-supplied. Required for ordering across '
      'devices.',
);

/// An existence-transition stamp (`existence_at`) on every syncable kind.
///
/// A bare timestamp with no data subject: it records *when* a record last
/// crossed between existing and deleted, never who did it, from where, or on
/// which device. Classified `shareable` because the receiving device cannot
/// evaluate the existence rule at all without it — withholding it would not
/// protect anything, it would just make a deletion unresolvable and let deleted
/// records resurrect.
///
/// Deliberately its own entry rather than reusing [_recordStamp]. The two carry
/// the same three axis values today, but they answer different questions
/// (`updated_at`: which content is newer; `existence_at`: which existence
/// transition happened later) and a future change to one should not silently
/// move the other.
const _existenceStamp = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.none,
  egress: EgressClass.shareable,
  note:
      'Existence-transition stamp. A bare timestamp with no data subject; must '
      'travel or a receiver cannot decide which of two disagreeing copies is '
      'the later existence decision, and deletions resurrect.',
);

/// Local repair bookkeeping. It identifies rows whose shareable text the
/// normalization pass could not yet rewrite — a natural key another row's
/// normalized form occupies, or a value that cannot be normalized at all; it is
/// not user content and has no meaning on another device.
const _normalisationRepairState = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.none,
  egress: EgressClass.deviceScoped,
  note: 'Local collision-repair bookkeeping; never exported or synchronized.',
);

/// Device Sync protocol bookkeeping. These fields identify local state and
/// ordering, but carry no record content and have no meaning on another device.
const _syncBookkeeping = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.none,
  egress: EgressClass.deviceScoped,
  note: 'Device Sync bookkeeping; never exported or synchronized.',
);

/// An opaque pending sync candidate. Its serialized record may contain
/// third-party data, but it is held locally until a user resolves the review.
const _syncCandidatePayload = DataClassification(
  term: DpvTerm.unclassifiedPersonal,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceScoped,
  note:
      'Opaque serialized sync candidate may contain third-party record content; '
      'held locally until review and never synchronized as queue state.',
);

/// An opaque tombstone payload that is intentionally retransmitted by sync.
const _syncTombstonePayload = DataClassification(
  term: DpvTerm.unclassifiedPersonal,
  subject: DataSubject.thirdParty,
  egress: EgressClass.shareable,
  note:
      'Opaque serialized tombstone may contain third-party record content; '
      'shareable because pending deletion retransmits it to sync peers.',
);

/// A soft-delete tombstone (`deleted_at`) on a syncable kind.
///
/// Same reasoning as `dances.deleted_at`, which has carried it since long
/// before Device Sync: absence never means deletion, so the tombstone itself
/// has to travel or a device that has not synced recently will resurrect
/// something the user deleted elsewhere. No data subject — it says a record
/// stopped existing, not anything about a person.
const _tombstone = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.none,
  egress: EgressClass.shareable,
  note:
      'Soft-delete tombstone; see dances.deleted_at. Must travel, or a peer '
      'that has not synced recently resurrects a deleted record. Added to this '
      'kind.',
);

/// A freeform note attached to a person, place or source record.
///
/// Still classified as personal data — the field is unbounded and a user may
/// well have typed a phone number into it — but **shareable**: the maintainer
/// ruled these are the user's own words about their own collection, and that a
/// collection which loses its notes on transfer has lost something the user
/// cares about.
///
/// This pair is the registry design working as intended: category and egress
/// are independent axes, so a field can be personal data *and* travel, with the
/// reason recorded rather than implied.
///
/// Residual risk, accepted knowingly: a user who wrote "ask for Bob, 555-1234"
/// into a venue note will have that text travel with the note.
const _freeformNote = DataClassification(
  term: DpvTerm.unclassifiedPersonal,
  subject: DataSubject.thirdParty,
  egress: EgressClass.shareable,
  note:
      'Unbounded freeform text attached to a person, place or source. Personal '
      'data by category, shareable by decision (maintainer ruling: this is the '
      "user's own commentary on their own collection). May incidentally "
      'contain contact details the user typed there.',
);

/// Freeform text on a program or one of its slots: the evening's running notes
/// and a slot's own text (a break, a waltz, a reminder to the caller).
///
/// Same three axis values as [_choreography], and deliberately **not**
/// [_freeformNote], although the two are the same shape of unbounded text.
/// The registry classifies freeform fields by the field's *intent*, not by
/// what a user might type into it (`docs/dev/data-classification.md`, "Known
/// limitations": "Freeform fields are classified by intent, not by content").
/// A [_freeformNote] hangs off a person, place or source record and inherits
/// that record's subject; a program note hangs off an event plan, and its
/// intent is running order and choreography. Where a program does name a
/// third party — its caller, band, or a slot's guest caller — those are their
/// own columns, classified [_performerCredit]. The 2026 external audit read
/// the shape and asked why these two were not `thirdParty`; this note is the
/// answer. Maintainer decision: keep the by-intent classification.
const _programNote = DataClassification(
  term: DpvTerm.nonPersonal,
  subject: DataSubject.none,
  egress: EgressClass.shareable,
  note:
      'Freeform text attached to an event plan, not to a person, place or '
      'source, so it does not take _freeformNote\'s third-party subject. '
      'Classified by intent (running order, choreography), not by what a user '
      'might type — see "Freeform fields are classified by intent, not by '
      'content" in docs/dev/data-classification.md. Names on a program belong '
      'in programs.caller, programs.band and program_slots.guest_caller, which '
      'are third-party performer credits. Maintainer decision (2026 audit).',
);

/// A performer credit for a public event. Personal data about a third party,
/// classified [EgressClass.shareable] because an event\'s billing is already
/// public and a program without its caller and band is close to meaningless.
///
/// **Contested** — see the performer-names section of
/// `docs/dev/data-classification.md`.
const _performerCredit = DataClassification(
  term: DpvTerm.name,
  subject: DataSubject.thirdParty,
  egress: EgressClass.shareable,
  note:
      'Performer credit for a public event. CONTESTED — see the '
      'performer-names section of docs/dev/data-classification.md.',
);

/// Classification for every persisted column. See the file doc comment.
final Map<String, DataClassification> fieldClassifications = {
  // ---------------------------------------------------------------- dances --
  'dances.id': _key,
  'dances.title': _choreography,
  'dances.form': _choreography,
  'dances.formation_shape': _choreography,
  'dances.formation_detail': _choreography,
  'dances.progression': _choreography,
  'dances.phrase_structure': _choreography,
  'dances.figures_json': _choreography,
  'dances.hook': _choreography,
  'dances.calling_notes': _choreography,
  'dances.walkthrough': _choreography,
  'dances.status': _choreography,
  'dances.level_id': _key,
  'dances.mixed_level': _choreography,
  'dances.mixer': _choreography,
  'dances.rating': _choreography,
  'dances.tunes_json': _choreography,
  'dances.composed_on': _choreography,
  'dances.revised_on': _choreography,
  'dances.created_at': _recordStamp,
  'dances.updated_at': _recordStamp,
  'dances.deleted_at': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note:
        'Soft-delete tombstone. Must travel, or a device that has not synced '
        'recently will resurrect a dance the user deleted elsewhere.',
  ),
  'dances.existence_at': _existenceStamp,

  // ------------------------------------------------------ difficulty_levels --
  'difficulty_levels.id': _key,
  'difficulty_levels.label': _choreography,
  'difficulty_levels.position': _choreography,
  'difficulty_levels.updated_at': _recordStamp,
  'difficulty_levels.deleted_at': _tombstone,
  'difficulty_levels.existence_at': _existenceStamp,

  // -------------------------------------------------------- choreographers --
  'choreographers.id': _key,
  'choreographers.name': const DataClassification(
    term: DpvTerm.name,
    subject: DataSubject.thirdParty,
    egress: EgressClass.shareable,
    note:
        'Personal data about a third party, shareable deliberately: '
        'authorship credit is the reason the field exists, and it is already '
        'published wherever the dance is published. Publication is why we may '
        'carry it, not a reason it stops being personal data — the same '
        'position library catalogues take on author names. See "Decisions on '
        'record" in docs/dev/data-classification.md for the citation.',
  ),
  'choreographers.website': const DataClassification(
    term: DpvTerm.websiteUrl,
    subject: DataSubject.thirdParty,
    egress: EgressClass.shareable,
    note: 'A public page the author chose to publish.',
  ),
  'choreographers.notes': _freeformNote,
  'choreographers.email': const DataClassification(
    term: DpvTerm.emailAddress,
    subject: DataSubject.thirdParty,
    egress: EgressClass.deviceLocal,
    note:
        'Private contact data for someone who does not use this app. This '
        'registry replaces the prose rule that lived on Choreographer.email.',
  ),
  'choreographers.location': const DataClassification(
    term: DpvTerm.locality,
    subject: DataSubject.thirdParty,
    egress: EgressClass.deviceLocal,
    note: 'Freeform locality, e.g. "Portland, OR".',
  ),
  'choreographers.deceased': const DataClassification(
    term: DpvTerm.deceasedFlag,
    subject: DataSubject.thirdParty,
    egress: EgressClass.deviceLocal,
    note: 'Personal data about someone who cannot exercise any rights over it.',
  ),
  'choreographers.updated_at': _recordStamp,
  'choreographers.deleted_at': _tombstone,
  'choreographers.existence_at': _existenceStamp,

  // ---------------------------------------------------------------- venues --
  // Split deliberately: a hall's identity is public, its address book is not.
  'venues.id': _key,
  'venues.name': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note:
        'A hall or grange — an organisation, not a person. Shareable so a '
        'program keeps a readable venue after a transfer.',
  ),
  'venues.website': const DataClassification(
    term: DpvTerm.websiteUrl,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note: "The venue's own public page.",
  ),
  'venues.event_name': _choreography,
  'venues.generic_schedule': _choreography,
  'venues.time': _choreography,
  'venues.price': _choreography,
  'venues.sponsor': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note:
        'An organisation underwriting a series — part of the venue\'s public '
        'identity (maintainer ruling). Free text, so it can hold a personal '
        'name, but unlike a custom field its meaning is fixed and known.',
  ),
  'venues.address1': _contactStreet,
  'venues.address2': _contactStreet,
  'venues.city': _contactCity,
  'venues.state_prov': _contactRegion,
  'venues.country': _contactCountry,
  'venues.postal_code': _contactPostal,
  'venues.plus4': _contactPostal,
  'venues.notes': _freeformNote,
  'venues.contact1_name': _contactName,
  'venues.contact1_phone': _contactPhone,
  'venues.contact1_email': _contactEmail,
  'venues.contact2_name': _contactName,
  'venues.contact2_phone': _contactPhone,
  'venues.contact2_email': _contactEmail,
  'venues.updated_at': _recordStamp,
  'venues.deleted_at': _tombstone,
  'venues.existence_at': _existenceStamp,

  // -------------------------------------------------------------- programs --
  'programs.id': _key,
  'programs.title': _choreography,
  'programs.event_date': _choreography,
  'programs.venue': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note: 'Free-text venue label, not an address. Coexists with venue_id.',
  ),
  'programs.venue_id': _key,
  'programs.band': _performerCredit,
  'programs.caller': _performerCredit,
  'programs.dancer_level': _choreography,
  'programs.notes': _programNote,
  'programs.status': _choreography,
  'programs.hide_alternates': _choreography,
  'programs.dialect_name': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'Name of a dialect from the caller\'s own library (user-authored '
        'text, like custom_dialects and active_dialect_ref, which are '
        'classified the same way). It names the caller\'s wording choice, '
        'not a venue contact or choreographer, so the subject is the app '
        'user. A soft by-name reference: a name that does not resolve on '
        'another device silently falls back to that device\'s app dialect.',
  ),
  'programs.pay_minor_units': const DataClassification(
    term: DpvTerm.income,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'What the caller is paid for the program (DPV pd:Income). The '
        'subject is the app user: it is their own earnings, not a fact about '
        'the venue, band or any other third party. Shareable so it follows '
        'the caller to their other devices and into their own archive '
        'export; it is not part of the shared program text or PDF.',
  ),
  'programs.pay_currency': const DataClassification(
    term: DpvTerm.income,
    subject: DataSubject.appUser,
    egress: EgressClass.shareable,
    note:
        'ISO 4217 code that programs.pay_minor_units is denominated in; '
        'meaningless without it, so it carries the same classification.',
  ),
  'programs.created_at': _recordStamp,
  'programs.updated_at': _recordStamp,
  'programs.deleted_at': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note: 'Soft-delete tombstone; see dances.deleted_at.',
  ),
  'programs.existence_at': _existenceStamp,

  // --------------------------------------------------------- program_slots --
  'program_slots.id': _key,
  'program_slots.program_id': _key,
  'program_slots.position': _choreography,
  'program_slots.dance_id': _key,
  'program_slots.text': _programNote,
  'program_slots.is_purged_dance': _choreography,
  'program_slots.is_alt': _choreography,
  'program_slots.guest_caller': _performerCredit,
  'program_slots.walkthrough_minutes': _choreography,
  'program_slots.dance_minutes': _choreography,
  'program_slots.performed_at': _choreography,

  // ----------------------------------------------------- published_sources --
  'published_sources.id': _key,
  'published_sources.title': _choreography,
  'published_sources.author': const DataClassification(
    term: DpvTerm.name,
    subject: DataSubject.thirdParty,
    egress: EgressClass.shareable,
    note: 'Published authorship credit; public by definition.',
  ),
  'published_sources.year': _choreography,
  'published_sources.url': const DataClassification(
    term: DpvTerm.websiteUrl,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
  ),
  'published_sources.notes': _freeformNote,
  'published_sources.updated_at': _recordStamp,
  'published_sources.deleted_at': _tombstone,
  'published_sources.existence_at': _existenceStamp,

  // ---------------------------------------------------------- joins, tags --
  'dance_authors.dance_id': _key,
  'dance_authors.choreographer_id': _key,
  'dance_authors.position': _choreography,
  'dance_tags.dance_id': _key,
  'dance_tags.tag_id': _key,
  'tags.id': _key,
  'tags.name': _choreography,
  'tags.color': _choreography,
  'tags.updated_at': _recordStamp,
  'tags.deleted_at': _tombstone,
  'tags.existence_at': _existenceStamp,
  'dance_sources.dance_id': _key,
  'dance_sources.source_id': _key,
  'dance_sources.page': _choreography,
  'dance_sources.number': _choreography,
  'dance_sources.position': _choreography,
  'dance_links.id': _key,
  'dance_links.dance_id': _key,
  'dance_links.kind': _choreography,
  'dance_links.transitive': _choreography,
  'dance_links.url': const DataClassification(
    term: DpvTerm.websiteUrl,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note: 'Citation or video link attached to a dance.',
  ),
  'dance_links.target_dance_id': _key,
  'dance_links.label': _choreography,

  // --------------------------------------------------------- custom fields --
  'custom_field_defs.id': _key,
  'custom_field_defs.key': _choreography,
  'custom_field_defs.label': _choreography,
  'custom_field_defs.type': _choreography,
  'custom_field_defs.choices_json': _choreography,
  'custom_field_defs.show_in_list': _choreography,
  'custom_field_defs.searchable': _choreography,
  'custom_field_defs.shareable': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note:
        'Per-field flag: whether this field and its values may travel in a '
        'shared archive. Classified shareable because the flag is carried on '
        'the defs that *are* emitted in share mode and is preserved in the '
        "owner's full-fidelity backup mode. Share mode omits definitions whose "
        'flag is false and their values; backup mode includes both so restore '
        'can reproduce the setting. This is the only field that directly '
        'controls egress of another field (custom_field_values.value_text). '
        'Added in #780; backup preservation fixed in #1037.',
  ),
  'custom_field_defs.updated_at': _recordStamp,
  'custom_field_defs.deleted_at': _tombstone,
  'custom_field_defs.existence_at': _existenceStamp,
  'custom_field_values.dance_id': _key,
  'custom_field_values.field_id': _key,
  'custom_field_values.value_text': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note:
        'Holds either unbounded free text or a user-defined choice value, for '
        'a field the user invented and named. Shareable by maintainer ruling: '
        'custom fields are core collection data. Egress in share mode is '
        'conditional on the field definition\'s shareable flag '
        '(custom_field_defs.shareable, added in #780): when shareable = false, '
        'neither this field def nor its values are emitted. Full-fidelity backup '
        'mode preserves the field and values regardless of that flag so restore '
        'does not lose owner data (fixed in #1037). The one-time disclosure '
        'notice on field creation (obligation 1) and the per-field exclusion '
        'control (obligation 2) were both implemented in #780.',
  ),
  'custom_field_values.value_num': _choreography,

  // ---------------------------------------------------------- derived index --
  'dance_figures.dance_id': _derivedIndex,
  'dance_figures.idx': _derivedIndex,
  'dance_figures.group_idx': _derivedIndex,
  'dance_figures.move': _derivedIndex,
  'dance_figures.beats': _derivedIndex,
  'dance_figures.progression': _derivedIndex,
  'dance_figures.params_json': _derivedIndex,
  'dance_figures.canonical_text': _derivedIndex,
  'dance_figures.section': _derivedIndex,

  // The FTS5 full-text index. Not a drift-typed table (created as raw SQL in
  // database.dart), so the coverage test reads its columns back with
  // pragma_table_info. Every column is a projection of shareable dance content
  // — but it is rebuilt wholesale on arrival, so none of it is transmitted.
  'dance_fts.dance_id': _derivedIndex,
  'dance_fts.title': _derivedIndex,
  'dance_fts.authors': _derivedIndex,
  'dance_fts.hook': _derivedIndex,
  'dance_fts.notes': _derivedIndex,
  'dance_fts.figures_text': _derivedIndex,
  'dance_fts.custom_values': _derivedIndex,
  'dance_fts.sources': _derivedIndex,
  'dance_substring_fts.dance_id': _derivedIndex,
  'dance_substring_fts.title': _derivedIndex,
  'dance_substring_fts.authors': _derivedIndex,
  'dance_substring_fts.hook': _derivedIndex,
  'dance_substring_fts.notes': _derivedIndex,
  'dance_substring_fts.figures_text': _derivedIndex,
  'dance_substring_fts.custom_values': _derivedIndex,
  'dance_substring_fts.sources': _derivedIndex,

  // ------------------------------------------------------------ provenance --
  'provenance.dance_id': _key,
  'provenance.source': _choreography,
  'provenance.external_id': _choreography,
  'provenance.imported_at': _recordStamp,
  'provenance.permission': _choreography,
  'provenance.license': _choreography,
  'provenance.source_version': _choreography,
  'program_provenance.program_id': _key,
  'program_provenance.source': _choreography,
  'program_provenance.external_id': _choreography,
  'program_provenance.imported_at': _recordStamp,
  'program_provenance.permission': _choreography,
  'program_provenance.license': _choreography,
  'program_provenance.source_version': _choreography,
  'venue_provenance.venue_id': _key,
  'venue_provenance.source': _choreography,
  'venue_provenance.external_id': _choreography,
  'venue_provenance.imported_at': _recordStamp,
  'venue_provenance.permission': _choreography,
  'venue_provenance.license': _choreography,
  'venue_provenance.source_version': _choreography,
  // Import history is device-local because it reveals which published
  // collections the app user chose to keep, rather than collection content.
  'collection_import_events.collection_id': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceLocal,
    note:
        'Published collection import history reveals the app user’s interests; '
        'it is not collection content and must remain on this device.',
  ),
  'collection_import_events.version': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceLocal,
    note:
        'Published collection import history reveals the app user’s interests; '
        'it is not collection content and must remain on this device.',
  ),
  'collection_import_events.archive_digest': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceLocal,
    note:
        'The digest identifies the specific published archive the app user '
        'imported and is retained only as local import history.',
  ),
  'collection_import_events.imported_at': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceLocal,
    note:
        'The timestamp records the app user’s import activity and is retained '
        'only as local import history.',
  ),

  // ------------------------------------------------------- settings, cache --
  'settings.key': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note:
        'The settings table is a key/value store; classifying the column '
        'says nothing about an individual preference. Per-key classification '
        'lives in the app package.',
  ),
  'settings.value_json': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.appUser,
    egress: EgressClass.deviceLocal,
    note:
        'Opaque JSON whose meaning depends on the key. Device-local at this '
        'layer so a blanket sync of the settings table cannot happen by '
        'accident; per-key rules decide what actually travels.',
  ),
  // The three sync stamps, added in #898. Classified `shareable` even though
  // `value_json` beside them is `deviceLocal`, and the difference is the point:
  // `value_json`'s device-local class is what stops the settings *table* being
  // synced wholesale, while the per-key classification in
  // `settings_registry.dart` decides which keys travel at all. For a key that
  // does travel, these three are ordinary record metadata that must accompany
  // it — a setting blob without its `updated_at` cannot be merged, and one
  // without `deleted_at`/`existence_at` cannot express that the user cleared
  // the preference, which is the whole reason `SettingsRepository.remove`
  // stopped being a hard delete. None of the three carries the value, so
  // classifying them shareable discloses only that a key changed or went away
  // at some instant, for a key the per-key gate has already admitted.
  'settings.updated_at': _recordStamp,
  'settings.deleted_at': _tombstone,
  'settings.existence_at': _existenceStamp,
  'normalisation_skips.table_name': _normalisationRepairState,
  'normalisation_skips.column_name': _normalisationRepairState,
  'normalisation_skips.record_id': _normalisationRepairState,
  'baseline_state.id': _syncBookkeeping,
  'baseline_state.epoch': _syncBookkeeping,
  'baseline_entries.kind': _syncBookkeeping,
  'baseline_entries.record_id': _syncBookkeeping,
  'baseline_entries.wire_hash': _syncBookkeeping,
  'baseline_entries.body_hash': _syncBookkeeping,
  'id_aliases.kind': _syncBookkeeping,
  'id_aliases.losing_id': _syncBookkeeping,
  'id_aliases.surviving_id': _syncBookkeeping,
  'pending_deletions.kind': _syncBookkeeping,
  'pending_deletions.record_id': _syncBookkeeping,
  'pending_deletions.tombstoned_at': _syncBookkeeping,
  'pending_deletions.tombstone_hash': _syncBookkeeping,
  'pending_deletions.tombstone_blob': _syncTombstonePayload,
  'review_queue.kind': _syncBookkeeping,
  'review_queue.record_id': _syncBookkeeping,
  'review_queue.counterpart_id': _syncBookkeeping,
  'review_queue.reason': _syncBookkeeping,
  'review_queue.candidate_blob': _syncCandidatePayload,
  'review_queue.candidate_hash': _syncBookkeeping,
  'review_queue.local_hash': _syncBookkeeping,
  'review_queue.queued_at': _syncBookkeeping,
  'published_records.kind': _syncBookkeeping,
  'published_records.record_id': _syncBookkeeping,
};

/// Tables with at least one column classified as Device Sync bookkeeping.
///
/// Writes to these tables are the sync engine's own state, not user edits, so
/// they must never schedule a sync pass. "Any column", not "every column":
/// `pending_deletions` and `review_queue` also hold payload columns with their
/// own classification. Derived by identity with the private classification, so
/// a table gains or loses membership by changing the registry alone.
final Set<String> syncBookkeepingTables = {
  for (final entry in fieldClassifications.entries)
    if (identical(entry.value, _syncBookkeeping))
      entry.key.substring(0, entry.key.indexOf('.')),
};

const _contactStreet = DataClassification(
  term: DpvTerm.street,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceLocal,
);
const _contactCity = DataClassification(
  term: DpvTerm.city,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceLocal,
);
const _contactRegion = DataClassification(
  term: DpvTerm.region,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceLocal,
);
const _contactCountry = DataClassification(
  term: DpvTerm.country,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceLocal,
);
const _contactPostal = DataClassification(
  term: DpvTerm.postalCode,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceLocal,
);

/// Shared by the six `venues.contact*` columns: the one recorded exception to
/// [EgressClass.deviceLocal], kept as a note rather than a new egress class
/// (post-audit finding flows-9; the maintainer stated no preference, and the
/// note was the sweep's call because it changes no behaviour).
const _venueContactConsentNote =
    'One exception to device-local: when the user exports or shares a program '
    '(PDF, JSON or .ccshare) whose venue has contacts, a dialog lists each '
    'populated contact field unticked, and only the fields ticked there go to '
    'the recipient, with the user\'s explicit consent for that one export '
    '(sanitizeVenueForShare). Nothing is remembered for the next export, and '
    'the field still never reaches Device Sync or other project-operated '
    'infrastructure. Allowed because a program handed to another organiser '
    'is often unusable without the hall contact, and only the user knows '
    'whether that person expects to be passed on. The tick is the user\'s '
    'consent, not the contact\'s, which is why the subject stays third-party '
    'and nothing is ticked by default.';

const _contactName = DataClassification(
  term: DpvTerm.name,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceLocal,
  note: _venueContactConsentNote,
);
const _contactPhone = DataClassification(
  term: DpvTerm.telephoneNumber,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceLocal,
  note: _venueContactConsentNote,
);
const _contactEmail = DataClassification(
  term: DpvTerm.emailAddress,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceLocal,
  note: _venueContactConsentNote,
);
