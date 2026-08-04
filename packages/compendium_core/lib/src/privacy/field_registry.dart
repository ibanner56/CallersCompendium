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
  'dances.level': _choreography,
  'dances.mixed_level': _choreography,
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

  // -------------------------------------------------------- choreographers --
  'choreographers.id': _key,
  'choreographers.name': const DataClassification(
    term: DpvTerm.name,
    subject: DataSubject.thirdParty,
    egress: EgressClass.shareable,
    note:
        'Personal data about a third party, shareable deliberately: '
        'authorship credit is the reason the field exists, and it is already '
        'published wherever the dance is published.',
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
  'programs.notes': _choreography,
  'programs.status': _choreography,
  'programs.hide_alternates': _choreography,
  'programs.created_at': _recordStamp,
  'programs.updated_at': _recordStamp,
  'programs.deleted_at': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note: 'Soft-delete tombstone; see dances.deleted_at.',
  ),

  // --------------------------------------------------------- program_slots --
  'program_slots.id': _key,
  'program_slots.program_id': _key,
  'program_slots.position': _choreography,
  'program_slots.dance_id': _key,
  'program_slots.text': _choreography,
  'program_slots.is_alt': _choreography,
  'program_slots.guest_caller': _performerCredit,
  'program_slots.planned_minutes': _choreography,
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

  // ---------------------------------------------------------- joins, tags --
  'dance_authors.dance_id': _key,
  'dance_authors.choreographer_id': _key,
  'dance_authors.position': _choreography,
  'dance_tags.dance_id': _key,
  'dance_tags.tag_id': _key,
  'tags.id': _key,
  'tags.name': _choreography,
  'tags.color': _choreography,
  'dance_sources.dance_id': _key,
  'dance_sources.source_id': _key,
  'dance_sources.page': _choreography,
  'dance_sources.number': _choreography,
  'dance_sources.position': _choreography,
  'dance_links.id': _key,
  'dance_links.dance_id': _key,
  'dance_links.kind': _choreography,
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
        'shared archive. The flag itself must be shareable so the recipient '
        'knows which fields the sender excluded — without it, an absent field '
        'in an archive would be ambiguous (deleted vs. excluded). This is the '
        'only field that directly controls egress of another field '
        '(custom_field_values.value_text). Added in #780.',
  ),
  'custom_field_values.dance_id': _key,
  'custom_field_values.field_id': _key,
  'custom_field_values.value_text': const DataClassification(
    term: DpvTerm.nonPersonal,
    subject: DataSubject.none,
    egress: EgressClass.shareable,
    note:
        'Holds either unbounded free text or a user-defined choice value, for '
        'a field the user invented and named. Shareable by maintainer ruling: '
        'custom fields are core collection data. Egress is conditional on the '
        'field definition\'s shareable flag (custom_field_defs.shareable, added '
        'in #780): when shareable = false, neither this field def nor its '
        'values are emitted in an archive. The one-time disclosure notice on '
        'field creation (obligation 1) and the per-field exclusion control '
        '(obligation 2) were both implemented in #780.',
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
const _contactName = DataClassification(
  term: DpvTerm.name,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceLocal,
);
const _contactPhone = DataClassification(
  term: DpvTerm.telephoneNumber,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceLocal,
);
const _contactEmail = DataClassification(
  term: DpvTerm.emailAddress,
  subject: DataSubject.thirdParty,
  egress: EgressClass.deviceLocal,
);
