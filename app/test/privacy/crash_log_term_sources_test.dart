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
/// whose category is personal data, plus [_alsoRequiredColumns] — see there
/// for why the registry axis alone under-covers the export's actual promise),
/// declare how each is covered, reconcile the two with a paste-ready failure,
/// and then prove the coverage is real by storing each declared value and
/// asserting the collector returns it.
///
/// [_exempt] is the by-name escape hatch, with a reason per entry. It is empty
/// today, and the stale-entry test below keeps it honest if that changes.
library;

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
  'program_slots.guest_caller': 'TERMSRC guest caller',
  // -- published sources (thirdParty) --
  'published_sources.author': 'TERMSRC source author',
  'published_sources.notes': 'TERMSRC source notes',
  // -- Device Sync queues: whole serialized records (thirdParty) --
  'review_queue.candidate_blob': '{"TERMSRC":"review candidate blob"}',
  'pending_deletions.tombstone_blob': '{"TERMSRC":"tombstone blob"}',
  // -- not required by the registry; user content all the same --
  'venues.name': 'TERMSRC venue name',
  'venues.sponsor': 'TERMSRC venue sponsor',
  'published_sources.title': 'TERMSRC source title',
  'dances.walkthrough': 'TERMSRC dance walkthrough',
  'dance_links.label': 'TERMSRC link label',
  // -- also required: see _alsoRequiredColumns --
  'difficulty_levels.label': 'TERMSRC difficulty label',
  'venues.website': 'https://termsrc-venue.example',
  'venues.event_name': 'TERMSRC venue event',
  'venues.generic_schedule': 'TERMSRC venue schedule',
  'venues.time': 'TERMSRC venue time',
  'venues.price': 'TERMSRC venue price',
  'published_sources.url': 'https://termsrc-source.example',
};

/// Freeform scalar TEXT columns the registry classifies non-personal
/// (`DataSubject.none`, non-personal category) but which are required here all
/// the same, because the scrubbed export's contract ("user content … removed")
/// is not scoped to the registry's third-party/personal-data axis: a hall's
/// schedule text or a source's URL can reach an echoed crash-log parameter
/// exactly as a dance title can.
///
/// Deliberately a short, explicit, by-name list rather than a structural rule
/// derived from the registry — the registry has no axis for "is a simple
/// free-text scalar" and most non-personal columns are not that (an enum like
/// `dances.status`, a JSON blob like `dances.figures_json`, an id, a
/// timestamp). Widening `_requiredColumns` to every non-key TEXT column would
/// wrongly demand a term source for `dances.figures_json`, whose content is
/// already covered indirectly through the decoded `Figure` records
/// (`collectSensitiveTerms`), not as a raw column read. A new freeform scalar
/// column belongs in this list by the same judgement call as this one; the
/// "no also-required entry names a column already required" test below keeps
/// it from drifting into the registry-derived set.
const Set<String> _alsoRequiredColumns = {
  'difficulty_levels.label',
  'venues.website',
  'venues.event_name',
  'venues.generic_schedule',
  'venues.time',
  'venues.price',
  'published_sources.url',
};

/// Required columns that deliberately have no term source, with the reason.
/// Empty today. A column belongs here only if its value cannot reach a crash
/// record's text at all; "the collector cannot read it" is not a reason, it is
/// the gap this test exists to surface.
const Map<String, String> _exempt = {};

String _v(String column) => _sources[column]!;

final _now = DateTime.utc(2026, 1, 1);

/// Every TEXT column the registry classifies as third-party or personal data,
/// as `table.column` in SQL names, read from the live drift schema so a new
/// column is seen without anyone listing it here — plus [_alsoRequiredColumns],
/// the freeform scalar columns the registry does not classify that way but
/// which the export's broader "user content removed" contract still covers.
Set<String> _requiredColumns(CompendiumDatabase db) {
  final required = <String>{};
  for (final column in _textColumns(db)) {
    final entry = fieldClassifications[column];
    if (entry == null) continue;
    if (entry.subject == DataSubject.thirdParty || entry.term.isPersonalData) {
      required.add(column);
    }
  }
  required.addAll(_alsoRequiredColumns);
  return required;
}

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
  await repos.dances.create(
    Dance(
      id: 'd1',
      title: 'Fixture Reel',
      walkthrough: _v('dances.walkthrough'),
      links: [
        DanceLink(
          id: 'l1',
          kind: LinkKind.video,
          url: 'https://video.example/fixture',
          label: _v('dance_links.label'),
        ),
      ],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Fixture Program',
      band: _v('programs.band'),
      caller: _v('programs.caller'),
      payMinorUnits: 12345,
      payCurrency: _v('programs.pay_currency'),
      slots: [
        ProgramSlot(
          id: 'ps1',
          position: 0,
          danceId: 'd1',
          guestCaller: _v('program_slots.guest_caller'),
        ),
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
}

void main() {
  group('crash-log term-source ratchet', () {
    test('every third-party or personal text column has a term source', () {
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
            'in the privacy registry, but the scrubbed crash-log export has no '
            'term source for them, so a failed write echoing the row leaks '
            'them. Read each in collectSensitiveTerms '
            '(lib/src/diagnostics/sensitive_terms.dart) and declare a fixture '
            'value in _sources here:\n  ${missing.join('\n  ')}',
      );
    });

    test('no term source or exemption names a column that is not text', () {
      final repos = openTestRepositories();
      final text = _textColumns(repos.db);
      final stale = [
        for (final column in [..._sources.keys, ..._exempt.keys])
          if (!text.contains(column)) column,
      ]..sort();
      expect(
        stale,
        isEmpty,
        reason:
            'These entries name columns that are not TEXT columns of the '
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

    test(
      'no also-required entry names a column the registry already requires',
      () {
        final repos = openTestRepositories();
        final registryRequired = <String>{};
        for (final column in _textColumns(repos.db)) {
          final entry = fieldClassifications[column];
          if (entry == null) continue;
          if (entry.subject == DataSubject.thirdParty ||
              entry.term.isPersonalData) {
            registryRequired.add(column);
          }
        }
        final redundant =
            _alsoRequiredColumns.intersection(registryRequired).toList()
              ..sort();
        expect(
          redundant,
          isEmpty,
          reason:
              'These columns are now classified third-party or personal data '
              'by the registry itself, so their _alsoRequiredColumns entry is '
              'redundant. Delete it:\n  ${redundant.join('\n  ')}',
        );
      },
    );

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
