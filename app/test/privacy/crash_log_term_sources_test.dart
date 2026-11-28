/// Term-source ratchet for the scrubbed crash-log export.
///
/// `collectSensitiveTerms` (`lib/src/diagnostics/sensitive_terms.dart`) is the
/// redaction list for the *default* diagnostics export, the one the UI labels
/// "scrubbed — user content, file paths, emails, and phone numbers removed".
/// Until the 2026 external audit it was the one egress surface whose list was
/// neither derived from nor checked against the privacy registry: the share
/// bundle has `share_bundle_egress_test.dart`; the crash export had nothing.
/// The hand-maintained list omitted every venue, choreographer and
/// published-source column — precisely the `thirdParty` fields the registry
/// withholds from every other route.
///
/// Why a column that is never *exported* can still reach the log: the pinned
/// `sqlite3` renders every bound parameter into a failed statement's exception
/// text (`Causing statement: …, parameters: …`), and drift's wrapper prints
/// that verbatim. A constraint or foreign-key failure on a `venues` write puts
/// the whole row — contact names, street address, locality — into the crash
/// record's `errorMessage`, and the export scrubs only what it has terms for.
///
/// (Superseded for the message itself: `CrashLogRecord.scrubbed` now withholds
/// `errorMessage` entirely, so this list is defence in depth for the stack and
/// other redacted text, not the only barrier.)
///
/// Shape follows `share_bundle_egress_test.dart` and the coverage ratchet in
/// `packages/compendium_core/test/privacy/`: derive the required set from the
/// real artefact (every TEXT column whose registry subject is `thirdParty` or
/// whose category is personal data, and every free-text TEXT column whatever
/// its registry axes — see [_isFreeTextColumn] for why the registry axis alone
/// under-covers the export's actual promise),
/// declare how each is covered, reconcile the two with a paste-ready failure,
/// and then prove the coverage is real by storing each declared value and
/// asserting the collector returns it.
///
/// [_exempt] is the by-name escape hatch, with a reason per entry. It is empty
/// today, and the stale-entry test below keeps it honest if that changes.
library;

import 'package:compendium_app/src/data/calendar_import_settings.dart'
    show kCalendarImportTitleFilterKey;
import 'package:compendium_app/src/data/display_defaults.dart'
    show
        ProgramTemplateEntry,
        encodeStartingProgramTemplate,
        kDefaultStartingProgramKey;
import 'package:compendium_app/src/data/program_templates.dart'
    show ProgramTemplate, encodeProgramTemplate, programTemplateKey;
import 'package:compendium_app/src/diagnostics/sensitive_terms.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show DriftSqlType;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// Registry column -> the distinctive value the fixture stores in it, which
/// the collector must return. Every value is unique so a hit is unambiguous,
/// and long enough (>= 2 chars) to clear the collector's minimum length. See
/// `short field values are not dropped` below for the two-character case this
/// deliberately does not exercise (a fixture value long enough to be
/// unambiguous can't also be short enough to prove the boundary).
///
/// Columns the registry *requires* (third-party or personal) come first; the
/// rest are user content this collector has always promised, or the identity
/// fields a user would recognise as their own words, covered on the same
/// footing so the fixture proves them too.
const Map<String, String> _sources = {
  // -- choreographers (thirdParty) --
  'choreographers.name': 'TERMSRC choreographer name',
  'choreographers.website': 'https://termsrc-choreographer.example',
  'choreographers.notes': 'TERMSRC choreographer notes',
  'choreographers.email': 'termsrc-choreographer@example.com',
  'choreographers.location': 'TERMSRC choreographer location',
  // -- venues: address block and contacts (thirdParty, deviceLocal) --
  'venues.address1': 'TERMSRC venue address1',
  'venues.address2': 'TERMSRC venue address2',
  'venues.city': 'TERMSRC venue city',
  'venues.state_prov': 'TERMSRC venue state',
  'venues.country': 'TERMSRC venue country',
  'venues.postal_code': 'TERMSRC-POSTAL',
  'venues.plus4': 'TERMSRC-PLUS4',
  'venues.notes': 'TERMSRC venue notes',
  'venues.contact1_name': 'TERMSRC venue contact one',
  'venues.contact1_phone': 'TERMSRC-555-0101',
  'venues.contact1_email': 'termsrc-contact1@example.com',
  'venues.contact2_name': 'TERMSRC venue contact two',
  'venues.contact2_phone': 'TERMSRC-555-0102',
  'venues.contact2_email': 'termsrc-contact2@example.com',
  // -- performer credits (thirdParty) --
  'programs.band': 'TERMSRC program band',
  'programs.caller': 'TERMSRC program caller',
  // An ISO-shaped code ('XTS' is the reserved testing currency) because the
  // Program constructor rejects anything else.
  'programs.pay_currency': 'XTS',
  // A hex digest (#2352): the archive codec keeps only that shape.
  'programs.calendar_event_key':
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  // Personal data about the caller (E1-01), and a hex digest too.
  'programs.calendar_feed_digest':
      'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  'program_slots.guest_caller': 'TERMSRC guest caller',
  // -- published sources (thirdParty) --
  'published_sources.author': 'TERMSRC source author',
  'published_sources.notes': 'TERMSRC source notes',
  // -- Device Sync queues: whole serialized records (thirdParty) --
  'review_queue.candidate_blob': '{"TERMSRC":"review candidate blob"}',
  'pending_deletions.tombstone_blob': '{"TERMSRC":"tombstone blob"}',
  'retained_sync_fields.payload': '{"TERMSRC":{"v":"kept newer field"}}',
  // -- not required by the registry; user content all the same: every free-text
  // column is required (_isFreeTextColumn) --
  'dances.title': 'TERMSRC dance title',
  'dances.formation_detail': 'TERMSRC formation detail',
  'dances.hook': 'TERMSRC dance hook',
  'dances.calling_notes': 'TERMSRC calling notes',
  'dances.meter': 'TERMSRC meter',
  'dances.musical_key': 'TERMSRC musical key',
  'dances.alternate_titles': 'TERMSRC other title',
  'dances.barnes_reference': 'TERMSRC Barnes reference',
  'dances.repeat_order_text': 'TERMSRC repeat order',
  'dances.new_partner_text': 'TERMSRC new partner',
  'dance_links.url': 'https://termsrc-link.example/fixture',
  'programs.title': 'TERMSRC program title',
  'programs.venue': 'TERMSRC program venue label',
  'programs.dancer_level': 'TERMSRC dancer level',
  'programs.notes': 'TERMSRC program notes',
  'programs.dialect_name': 'TERMSRC dialect name',
  'program_slots.text': 'TERMSRC slot text',
  'custom_field_defs.label': 'TERMSRC field label',
  'custom_field_values.value_text': 'TERMSRC field value',
  'tags.name': 'TERMSRC tag name',
  'event_rules.nickname': 'TERMSRC rule nickname',
  'venues.name': 'TERMSRC venue name',
  'venues.sponsor': 'TERMSRC venue sponsor',
  'published_sources.title': 'TERMSRC source title',
  'dances.walkthrough': 'TERMSRC dance walkthrough',
  'dance_links.label': 'TERMSRC link label',
  // -- free text too (_isFreeTextColumn), and _alsoRequiredColumns --
  'difficulty_levels.label': 'TERMSRC difficulty label',
  'venues.website': 'https://termsrc-venue.example',
  'venues.event_name': 'TERMSRC venue event',
  'venues.generic_schedule': 'TERMSRC venue schedule',
  'venues.time': 'TERMSRC venue time',
  'venues.price': 'TERMSRC venue price',
  'published_sources.url': 'https://termsrc-source.example',
  'user_glossary_entries.name': 'TERMSRC glossary name',
  'user_glossary_entries.definition': 'TERMSRC glossary definition',
  'user_glossary_entries.description': 'TERMSRC glossary description',
  'user_glossary_entries.notes': 'TERMSRC glossary notes',
  'user_glossary_entries.keywords_json': 'TERMSRC glossary keyword',
  'user_glossary_entries.payload_json': 'TERMSRC compound template note',
  'figure_notes.notes': 'TERMSRC figure note',
};

/// Every free-text TEXT column is required, whatever its registry axes: the
/// scrubbed export's contract ("user content … removed") is not scoped to the
/// registry's third-party/personal-data axis, and a hall's schedule text or a
/// dance's other title can reach an echoed crash-log parameter exactly as a
/// dance title can.
///
/// The registry has no axis for "free text", so the rule is structural: a
/// TEXT column is free text unless its name marks it as a key (`id`, `key`,
/// `kind`, `…_id`, `…_ids`), a JSON blob (`…_json`), a hash or digest
/// (`…_hash`, `…_digest`), or its table is sync bookkeeping
/// ([syncBookkeepingTables]), or it is in [_notFreeText] by name with a
/// reason. So a new TEXT column is required by default, and leaving it out
/// takes an entry here, with a reason a reviewer can judge. (It was a by-name
/// list of the required columns until the pre-release audit found it had
/// fallen behind: none of the release's new dance fields or event-rule
/// nicknames were on it.)
bool _isFreeTextColumn(String column) {
  final dot = column.indexOf('.');
  final table = column.substring(0, dot);
  final name = column.substring(dot + 1);
  if (syncBookkeepingTables.contains(table)) return false;
  if (const {'id', 'key', 'kind'}.contains(name)) return false;
  for (final suffix in const ['_id', '_ids', '_json', '_hash', '_digest']) {
    if (name.endsWith(suffix)) return false;
  }
  return !_notFreeText.containsKey(column);
}

/// TEXT columns [_isFreeTextColumn] does not require although their names do
/// not say why, with the reason. Most hold a value from a closed set or a
/// code, not the user's own words. Two, `dance_sources.page` and `number`,
/// are free text left out on purpose: as terms their short values would do
/// more harm than good. [_isFreeTextColumn] requires every other column.
const Map<String, String> _notFreeText = {
  'dances.form': 'an enum name',
  'dances.formation_shape': 'an enum name',
  'dances.progression': 'an enum name',
  'dances.square_kind': 'an enum name',
  'dances.repeat_order': 'an enum name (its free text is repeat_order_text)',
  'dances.new_partner': 'an enum name (its free text is new_partner_text)',
  'dances.status': 'an enum name',
  'dances.phrase_structure':
      'a phrase code such as AABB, parsed on read; as a term a two-letter '
      'code would blank that word all through the stack text',
  'dances.composed_on': 'a partial date',
  'dances.interpreted_on': 'a partial date',
  'dances.revised_on': 'a partial date',
  'dance_figures.move': 'a taxonomy move key',
  'dance_figures.section': 'a phrase label such as A1',
  'dance_figures.canonical_text':
      'a derived search index rendered from the figures; the user\'s words '
      'in it (notes, a custom figure\'s text) are collected from the figures',
  'dance_sources.page':
      'a page locator; as a term a short number would blank every matching '
      'line number in the stack text',
  'dance_sources.number': 'a tune number; the same reason as the page',
  'programs.status': 'an enum name',
  'programs.calendar_flag': 'an enum name',
  'programs.calendar_event_fingerprint':
      'truncated hashes of what the calendar import last wrote (#2354)',
  'collection_import_events.version': 'a published collection\'s version',
  'normalisation_skips.table_name': 'the name of one of the app\'s tables',
  'normalisation_skips.column_name': 'the name of one of the app\'s columns',
  'custom_field_defs.type': 'an enum name',
  'event_rules.quantifier': 'an enum name',
  'event_rules.scope': 'an enum name',
  'provenance.source': 'the importer\'s source name, set by the app',
  'provenance.permission': 'a permission code from the source',
  'provenance.license': 'a licence code from the source',
  'provenance.source_version': 'the source\'s version string',
  'program_provenance.source': 'the importer\'s source name, set by the app',
  'program_provenance.permission': 'a permission code from the source',
  'program_provenance.license': 'a licence code from the source',
  'program_provenance.source_version': 'the source\'s version string',
  'venue_provenance.source': 'the importer\'s source name, set by the app',
  'venue_provenance.permission': 'a permission code from the source',
  'venue_provenance.license': 'a licence code from the source',
  'venue_provenance.source_version': 'the source\'s version string',
};

/// Columns [_isFreeTextColumn] leaves out by their name that are required all
/// the same.
const Set<String> _alsoRequiredColumns = {
  // A JSON list of the user's own words for a glossary entry (#709).
  'user_glossary_entries.keywords_json',
};

/// Required columns that deliberately have no term source, with the reason.
/// Empty today. A column belongs here only if its value cannot reach a crash
/// record's text at all; "the collector cannot read it" is not a reason, it is
/// the gap this test exists to surface.
const Map<String, String> _exempt = {};

String _v(String column) => _sources[column]!;

/// This release's free text kept in settings values, not columns: the
/// settings value column is a JSON blob, so [_requiredColumns] cannot see it.
/// Each is stored by [_populate] and must be returned by the collector.
const Map<String, String> _settingsSources = {
  'saved search name': 'TERMSRC saved search name',
  'saved search text': 'TERMSRC saved search text',
  'program template name': 'TERMSRC template name',
  'program template slot text': 'TERMSRC template slot note',
  'program template rule label': 'TERMSRC template rule label',
  'saved search tune': 'TERMSRC saved search tune',
  'saved search text field value': 'TERMSRC saved search field value',
  'starting program slot text': 'TERMSRC starting program note',
  'calendar title filter': 'TERMSRC calendar title filter',
  // The settings keys the registry classifies as personal data
  // (_personalSettingsKeys).
  'default caller': 'TERMSRC default caller',
  'default band': 'TERMSRC default band',
  'calendar address': 'https://termsrc-calendar.example/feed.ics',
  'sync id': 'TERMSRC-sync-id',
};

/// Every settings key the registry classifies as personal or third-party data
/// -> the [_settingsSources] entry [_populate] stores in it. Checked against
/// the registry, so a new personal setting needs a term source.
const Map<String, String> _personalSettingsKeys = {
  'default_program_caller': 'default caller',
  'default_program_band': 'default band',
  'calendar_feed_url': 'calendar address',
  'sync_id': 'sync id',
};

/// Personal settings keys with no term source, and why.
const Map<String, String> _exemptPersonalSettingsKeys = {
  'sync_last_used_fingerprint':
      'salted, slow verifiers of store addresses, not text: no stored value '
      'is the address itself, and as terms they would match nothing',
};

/// A compound parameter's name, which the user chose: stored in the payload
/// beside [_sources]' template note, and collected with it.
const _glossaryParamKey = 'TERMSRC compound parameter';

/// A term's source citation (#1023), which can name a published author:
/// stored in a term's payload, and collected with it.
const _termSource = 'TERMSRC term source citation';

final _now = DateTime.utc(2026, 1, 1);

/// Every TEXT column the registry classifies as third-party or personal data,
/// and every free-text TEXT column ([_isFreeTextColumn]), as `table.column` in
/// SQL names, read from the live drift schema so a new column is seen without
/// anyone listing it here — plus [_alsoRequiredColumns].
Set<String> _requiredColumns(CompendiumDatabase db) => {
  ..._registryRequiredColumns(db),
  ..._textColumns(db).where(_isFreeTextColumn),
  ..._alsoRequiredColumns,
};

/// Every TEXT column the registry classifies as third-party or personal data.
Set<String> _registryRequiredColumns(CompendiumDatabase db) => {
  for (final column in _textColumns(db))
    if (fieldClassifications[column] case final entry?)
      if (entry.subject == DataSubject.thirdParty || entry.term.isPersonalData)
        column,
};

/// Every TEXT column of the live schema, as `table.column` in SQL names.
Set<String> _textColumns(CompendiumDatabase db) => {
  for (final table in db.allTables)
    for (final column in table.$columns)
      if (column.type == DriftSqlType.string)
        '${table.actualTableName}.${column.name}',
};

/// Stores one row per entity with every declared value in place.
Future<void> _populate(CompendiumRepositories repos) async {
  // ignore: unused_result
  await repos.choreographers.upsert(
    Choreographer(
      id: 'c1',
      name: _v('choreographers.name'),
      website: _v('choreographers.website'),
      notes: _v('choreographers.notes'),
      email: _v('choreographers.email'),
      location: _v('choreographers.location'),
    ),
  );
  await repos.venues.upsert(
    Venue(
      id: 'v1',
      name: _v('venues.name'),
      website: _v('venues.website'),
      sponsor: _v('venues.sponsor'),
      eventName: _v('venues.event_name'),
      time: _v('venues.time'),
      genericSchedule: _v('venues.generic_schedule'),
      price: _v('venues.price'),
      address1: _v('venues.address1'),
      address2: _v('venues.address2'),
      city: _v('venues.city'),
      stateProv: _v('venues.state_prov'),
      country: _v('venues.country'),
      postalCode: _v('venues.postal_code'),
      plus4: _v('venues.plus4'),
      notes: _v('venues.notes'),
      contact1Name: _v('venues.contact1_name'),
      contact1Phone: _v('venues.contact1_phone'),
      contact1Email: _v('venues.contact1_email'),
      contact2Name: _v('venues.contact2_name'),
      contact2Phone: _v('venues.contact2_phone'),
      contact2Email: _v('venues.contact2_email'),
    ),
  );
  await repos.publishedSources.upsert(
    PublishedSource(
      id: 's1',
      title: _v('published_sources.title'),
      author: _v('published_sources.author'),
      url: _v('published_sources.url'),
      notes: _v('published_sources.notes'),
    ),
  );
  await repos.difficultyLevels.upsert(
    DifficultyLevel(
      id: 'fixture-difficulty',
      label: _v('difficulty_levels.label'),
      position: 99,
    ),
  );
  await repos.userGlossary.upsert(
    UserGlossaryEntry(
      id: 'fixture-glossary',
      kindName: UserGlossaryEntryKind.compound.name,
      name: _v('user_glossary_entries.name'),
      definition: _v('user_glossary_entries.definition'),
      description: _v('user_glossary_entries.description'),
      notes: _v('user_glossary_entries.notes'),
      keywords: [_v('user_glossary_entries.keywords_json')],
      payload: {
        'params': [
          {'key': _glossaryParamKey, 'kind': 'handedness'},
        ],
        'figures': [
          figureToJson(
            Figure(
              move: 'swing',
              note: _v('user_glossary_entries.payload_json'),
            ),
          ),
        ],
        'bindings': <Object?>[],
      },
      createdAt: DateTime.utc(2026, 10, 14),
    ),
  );
  await repos.userGlossary.upsert(
    UserGlossaryEntry(
      id: 'fixture-term',
      kindName: UserGlossaryEntryKind.term.name,
      name: 'Fixture term',
      definition: 'A word.',
      description: 'Of the fixture.',
      payload: glossaryTermPayload('contra', source: _termSource),
      createdAt: DateTime.utc(2026, 10, 16),
    ),
  );
  await repos.figureNotes.set('swing', _v('figure_notes.notes'));
  // ignore: unused_result
  await repos.tags.upsert(Tag(id: 't1', name: _v('tags.name')));
  // ignore: unused_result
  await repos.customFieldDefs.upsert(
    CustomFieldDef(
      id: 'f1',
      key: 'fixture',
      label: _v('custom_field_defs.label'),
      type: CustomFieldType.text,
    ),
  );
  await repos.dances.create(
    Dance(
      id: 'd1',
      title: _v('dances.title'),
      formation: Formation(
        FormationShape.dupleImproper,
        detail: _v('dances.formation_detail'),
      ),
      hook: _v('dances.hook'),
      callingNotes: _v('dances.calling_notes'),
      walkthrough: _v('dances.walkthrough'),
      meter: _v('dances.meter'),
      musicalKey: _v('dances.musical_key'),
      alternateTitles: [
        _v('dances.alternate_titles'),
        'TERMSRC second other title',
      ],
      tagIds: const ['t1'],
      customFields: [
        CustomFieldValue(
          fieldId: 'f1',
          value: _v('custom_field_values.value_text'),
        ),
      ],
      links: [
        DanceLink(
          id: 'l1',
          kind: LinkKind.video,
          url: _v('dance_links.url'),
          label: _v('dance_links.label'),
        ),
      ],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  // Only an English dance keeps a Barnes reference, and only a square its
  // repeat order and new-partner text.
  await repos.dances.create(
    Dance(
      id: 'd2',
      title: 'Fixture English dance',
      form: DanceForm.ecd,
      barnesReference: _v('dances.barnes_reference'),
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  await repos.dances.create(
    Dance(
      id: 'd3',
      title: 'Fixture square',
      form: DanceForm.square,
      repeatOrder: SquareRepeatOrder.other,
      repeatOrderText: _v('dances.repeat_order_text'),
      newPartner: SquareNewPartner.other,
      newPartnerText: _v('dances.new_partner_text'),
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  // The saved search the event rule names, and this release's settings text
  // (_settingsSources).
  await repos.settings.set('${savedSearchKeyPrefix}fixture-search', {
    'v': savedSearchFormatVersion,
    'text': _settingsSources['saved search text'],
    'name': _settingsSources['saved search name'],
  });
  await repos.settings.set(
    programTemplateKey('fixture-template'),
    encodeProgramTemplate(
      ProgramTemplate(
        id: 'fixture-template',
        name: _settingsSources['program template name']!,
        entries: [
          ProgramTemplateEntry(
            text: _settingsSources['program template slot text'],
          ),
          ProgramTemplateEntry.rule(
            savedSearchId: 'fixture-search',
            label: _settingsSources['program template rule label']!,
          ),
        ],
      ),
    ),
  );
  await repos.settings.set(
    kCalendarImportTitleFilterKey,
    _settingsSources['calendar title filter'],
  );
  // A search's Filters-panel words: read from the stored value as it is.
  await repos.settings.set('${savedSearchKeyPrefix}fixture-facets', {
    'v': savedSearchFormatVersion,
    'name': 'Fixture facets',
    'facets': {
      'tunes': [_settingsSources['saved search tune']],
      'textValues': {
        'f1': {
          'op': 'contains',
          'value': _settingsSources['saved search text field value'],
        },
      },
    },
  });
  await repos.settings.set(
    kDefaultStartingProgramKey,
    encodeStartingProgramTemplate([
      ProgramTemplateEntry(
        text: _settingsSources['starting program slot text'],
      ),
      const ProgramTemplateEntry(text: Program.breakSlotText),
    ]),
  );
  for (final MapEntry(key: key, value: source)
      in _personalSettingsKeys.entries) {
    await repos.settings.set(key, _settingsSources[source]);
  }
  // ignore: unused_result
  await repos.eventRules.create(
    savedSearchId: 'fixture-search',
    quantifier: EventRuleQuantifier.atLeast,
    count: 1,
    scope: EventRuleScope.wholeProgram,
    nickname: _v('event_rules.nickname'),
  );
  await repos.programs.create(
    Program(
      id: 'p1',
      title: _v('programs.title'),
      venue: _v('programs.venue'),
      dancerLevel: _v('programs.dancer_level'),
      notes: _v('programs.notes'),
      dialectName: _v('programs.dialect_name'),
      band: _v('programs.band'),
      caller: _v('programs.caller'),
      payMinorUnits: 12345,
      payCurrency: _v('programs.pay_currency'),
      calendarEventKey: _v('programs.calendar_event_key'),
      calendarFeedDigest: _v('programs.calendar_feed_digest'),
      slots: [
        ProgramSlot(
          id: 'ps1',
          position: 0,
          danceId: 'd1',
          guestCaller: _v('program_slots.guest_caller'),
        ),
        ProgramSlot(id: 'ps2', position: 1, text: _v('program_slots.text')),
      ],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  await repos.syncLocal.enqueueReview(
    kind: SyncRecordKind.dance,
    recordId: 'd1',
    counterpartId: 'peer-d1',
    reason: 'conflict',
    candidateBlob: _v('review_queue.candidate_blob'),
    candidateHash: 'candidate-hash',
    queuedAt: _now,
  );
  await repos.syncLocal.upsertPendingDeletion(
    kind: SyncRecordKind.venue,
    recordId: 'v-gone',
    tombstonedAt: _now,
    tombstoneHash: 'tombstone-hash',
    tombstoneBlob: _v('pending_deletions.tombstone_blob'),
  );
  await repos.syncLocal.setRetainedSyncFields(
    kind: SyncRecordKind.program,
    recordId: 'p1',
    payload: _v('retained_sync_fields.payload'),
  );
}

void main() {
  group('crash-log term-source ratchet', () {
    test('every third-party, personal or free-text column has a term source', () {
      final repos = openTestRepositories();
      final missing =
          _requiredColumns(repos.db)
              .difference(_sources.keys.toSet())
              .difference(_exempt.keys.toSet())
              .toList()
            ..sort();
      expect(
        missing,
        isEmpty,
        reason:
            'These TEXT columns are classified third-party or personal data '
            'in the privacy registry, or hold free text, but the scrubbed '
            'crash-log export has no term source for them, so a failed write '
            'echoing the row leaks them. Read each in collectSensitiveTerms '
            '(lib/src/diagnostics/sensitive_terms.dart) and declare a fixture '
            'value in _sources here, or, if it holds no free text, list it in '
            '_notFreeText with the reason:\n  ${missing.join('\n  ')}',
      );
    });

    test('no term source or exemption names a column that is not text', () {
      final repos = openTestRepositories();
      final text = _textColumns(repos.db);
      final stale = [
        for (final column in [
          ..._sources.keys,
          ..._exempt.keys,
          ..._notFreeText.keys,
          ..._alsoRequiredColumns,
        ])
          if (!text.contains(column)) column,
      ]..sort();
      expect(
        stale,
        isEmpty,
        reason:
            'These entries (term sources, exemptions, not-free-text or '
            'also-required columns) name columns that are not TEXT columns of the '
            'current schema — renamed, dropped, or mistyped. Fix them so this '
            'test keeps describing the real boundary:\n  ${stale.join('\n  ')}',
      );
    });

    test('no exemption names a column the registry does not require', () {
      final repos = openTestRepositories();
      final required = _requiredColumns(repos.db);
      final stale = [
        for (final column in _exempt.keys)
          if (!required.contains(column)) column,
      ]..sort();
      expect(
        stale,
        isEmpty,
        reason:
            'These exemptions are for columns that are no longer classified '
            'third-party or personal. Delete them:\n  ${stale.join('\n  ')}',
      );
    });

    test('no also-required entry names a column already required', () {
      final repos = openTestRepositories();
      final requiredAnyway = {
        ..._registryRequiredColumns(repos.db),
        ..._textColumns(repos.db).where(_isFreeTextColumn),
      };
      final redundant =
          _alsoRequiredColumns.intersection(requiredAnyway).toList()..sort();
      expect(
        redundant,
        isEmpty,
        reason:
            'These columns are now required by the registry or as free text, '
            'so their _alsoRequiredColumns entry is redundant. Delete '
            'it:\n  ${redundant.join('\n  ')}',
      );
    });

    test('the collector returns this release\'s settings text', () async {
      final repos = openTestRepositories();
      await _populate(repos);

      final terms = await collectSensitiveTerms(repos);

      final uncollected = [
        for (final entry in _settingsSources.entries)
          if (!terms.contains(entry.value)) entry.key,
      ]..sort();
      expect(
        uncollected,
        isEmpty,
        reason:
            'The fixture stored each of these in settings and '
            'collectSensitiveTerms did not return it:\n  '
            '${uncollected.join('\n  ')}',
      );
    });

    test('every personal settings key has a term source', () {
      final personal = [
        for (final entry in settingsClassifications.entries)
          if (entry.value.term.isPersonalData ||
              entry.value.subject == DataSubject.thirdParty)
            entry.key,
      ]..sort();
      expect(
        personal,
        unorderedEquals([
          ..._personalSettingsKeys.keys,
          ..._exemptPersonalSettingsKeys.keys,
        ]),
        reason:
            'The registry classifies these settings keys as personal or '
            'third-party data. Read each new one in collectSensitiveTerms and '
            'declare it in _personalSettingsKeys (or, with a reason, in '
            '_exemptPersonalSettingsKeys); delete an entry the registry no '
            'longer classifies that way.',
      );
    });

    test('the break token is not a term', () async {
      final repos = openTestRepositories();
      await _populate(repos);
      await repos.programs.create(
        Program(
          id: 'p-break',
          title: 'Fixture with a break',
          slots: [
            ProgramSlot(id: 'pb1', position: 0, text: Program.breakSlotText),
          ],
          createdAt: _now,
          updatedAt: _now,
        ),
      );

      final terms = await collectSensitiveTerms(repos);

      expect(
        terms.map((t) => t.toLowerCase()),
        isNot(contains(Program.breakSlotText.toLowerCase())),
      );
    });

    test('a saved search or template that does not decode is still '
        'collected, as stored', () async {
      final repos = openTestRepositories();
      await repos.settings.set('${savedSearchKeyPrefix}broken', {
        'v': 99,
        'name': 'TERMSRC unreadable search',
      });
      await repos.settings.set(
        programTemplateKey('broken'),
        '{"version":99,"name":"TERMSRC unreadable template"}',
      );

      final terms = await collectSensitiveTerms(repos);

      expect(terms, contains('TERMSRC unreadable search'));
      expect(
        terms.any((t) => t.contains('TERMSRC unreadable template')),
        isTrue,
      );
    });

    test('the collector returns a compound\'s parameter names', () async {
      final repos = openTestRepositories();
      await _populate(repos);
      expect(await collectSensitiveTerms(repos), contains(_glossaryParamKey));
      expect(
        await collectSensitiveTerms(repos),
        contains(_termSource),
        reason: 'a term\'s source citation (#1023)',
      );
    });

    test('the collector returns every declared source value', () async {
      final repos = openTestRepositories();
      await _populate(repos);

      final terms = await collectSensitiveTerms(repos);

      final uncollected = [
        for (final entry in _sources.entries)
          if (!terms.contains(entry.value)) entry.key,
      ]..sort();
      expect(
        uncollected,
        isEmpty,
        reason:
            'The fixture stored a distinctive value in each of these columns '
            'and collectSensitiveTerms did not return it. Either the collector '
            'does not read the column (add it) or the fixture does not reach '
            'it (fix _populate):\n  ${uncollected.join('\n  ')}',
      );
    });

    test(
      'soft-deleted person, place and source rows still contribute',
      () async {
        // A tombstoned row is still on disk and still bound by the statement
        // that eventually purges it, so its values must stay in the term set
        // until the row is gone.
        final repos = openTestRepositories();
        await _populate(repos);
        await repos.programs.softDelete('p1', at: _now);
        await repos.venues.delete('v1');
        await repos.publishedSources.delete('s1');
        await repos.dances.softDelete('d1', at: _now);
        await repos.choreographers.delete('c1');

        final terms = await collectSensitiveTerms(repos);

        for (final column in const [
          'venues.contact1_name',
          'venues.address1',
          'choreographers.name',
          'choreographers.location',
          'published_sources.author',
        ]) {
          expect(
            terms,
            contains(_v(column)),
            reason: 'lost on delete: $column',
          );
        }
      },
    );

    test('short field values are not dropped', () async {
      // Real two-character values are common in exactly the columns most
      // required by the registry: a US state code, a country code, a short
      // surname. The collector must keep them (CrashRedactor.userContentTerms
      // matches a term this short on a word boundary, not as a substring, so
      // keeping them does not risk over-redaction — see crash_redactor_test.dart).
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.choreographers.upsert(
        Choreographer(id: 'short-c1', name: 'Li'),
      );
      await repos.venues.upsert(
        Venue(
          id: 'short-v1',
          name: 'Short Fixture Venue',
          stateProv: 'CA',
          country: 'US',
        ),
      );

      final terms = await collectSensitiveTerms(repos);

      for (final short in const ['Li', 'CA', 'US']) {
        expect(terms, contains(short), reason: 'dropped short value: $short');
      }
    });
  });
}
