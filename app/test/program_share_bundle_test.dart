import 'package:compendium_app/src/export/program_share_bundle.dart';
import 'package:compendium_app/src/export/share_sanitization.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance(String id, String title, {List<String> authorIds = const []}) =>
    Dance(
      id: id,
      title: title,
      authorIds: authorIds,
      figures: [
        Figure(move: 'swing', params: {'beats': 16, 'who': 'partners'}),
      ],
      sourceCitations: const [],
      customFields: const [],
      createdAt: _now,
      updatedAt: _now,
    );

Choreographer _choreographer(
  String id,
  String name, {
  String? email,
  String? location,
}) => Choreographer(id: id, name: name, email: email, location: location);

ProgramSlot _slot(
  int position, {
  String? danceId,
  String? text,
  bool isAlt = false,
}) => ProgramSlot(
  id: 's$position',
  position: position,
  danceId: danceId,
  text: text,
  isAlt: isAlt,
);

Program _program({
  required List<ProgramSlot> slots,
  String title = 'Friday Contra',
  String? venueId,
}) => Program(
  id: 'p1',
  title: title,
  slots: slots,
  venueId: venueId,
  createdAt: _now,
  updatedAt: _now,
);

Venue _venue(String id, {bool withContacts = false}) => Venue(
  id: id,
  name: 'Town Hall',
  address1: '10 Main St',
  city: 'Montpelier',
  stateProv: 'VT',
  country: 'USA',
  contact1Name: withContacts ? 'Alex Caller' : null,
  contact1Phone: withContacts ? '555-0100' : null,
  contact1Email: withContacts ? 'alex@example.com' : null,
  contact2Name: withContacts ? 'Bo Booker' : null,
  contact2Phone: withContacts ? '555-0200' : null,
  contact2Email: withContacts ? 'bo@example.com' : null,
);

/// Runs every dance in [json] through the full adapter path so we assert on the
/// dances the existing importer would actually commit.
Future<List<Dance>> _importedDances(String json) async {
  final adapter = GenericJsonAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: json));
  final dances = <Dance>[];
  for (final record in discovered) {
    final raw = await adapter.fetch(record);
    final draft = adapter.parse(raw);
    dances.add(draft.dance);
  }
  return dances;
}

void main() {
  group('buildProgramShareBundle', () {
    final catalog = {
      'd1': _dance('d1', 'Rory O\'More'),
      'd2': _dance('d2', 'The Nice Combination'),
      'd3': _dance('d3', 'Chinese New Year'),
    };
    Dance? danceFor(String id) => catalog[id];
    Choreographer? choreographerFor(String id) => null;

    test('embeds every referenced dance, deduped, and preserves the program', () {
      final program = _program(
        slots: [
          _slot(0, danceId: 'd1'),
          _slot(1, text: 'Break'),
          _slot(2, danceId: 'd2'),
          _slot(3, danceId: 'd1'), // repeated id -> deduped
        ],
      );

      final json = buildProgramShareBundle(
        program,
        danceFor: danceFor,
        choreographerFor: choreographerFor,
        venueFor: (_) => null,
        now: _now,
      );
      final archive = decodeArchive(json).archive;

      expect(archive.dances.map((d) => d.id).toSet(), {'d1', 'd2'});
      expect(archive.dances.length, 2, reason: 'repeated danceId is deduped');
      expect(archive.programs.single.id, 'p1');
      // Slot order (and the note-only slot's text) is preserved by the program.
      expect(archive.programs.single.slots.map((s) => s.position), [
        0,
        1,
        2,
        3,
      ]);
      expect(
        archive.programs.single.slots[1].text,
        'Break',
        reason: 'note-only slot carries its own text',
      );
    });

    test('skips referenced dances that cannot be resolved', () {
      final program = _program(
        slots: [
          _slot(0, danceId: 'd1'),
          _slot(1, danceId: 'missing'),
        ],
      );

      final archive = decodeArchive(
        buildProgramShareBundle(
          program,
          danceFor: danceFor,
          choreographerFor: choreographerFor,
          venueFor: (_) => null,
        ),
      ).archive;

      expect(archive.dances.map((d) => d.id), ['d1']);
    });

    test('a note-only program embeds no dances', () {
      final program = _program(
        slots: [
          _slot(0, text: 'Waltz'),
          _slot(1, text: 'Break'),
        ],
      );

      final archive = decodeArchive(
        buildProgramShareBundle(
          program,
          danceFor: danceFor,
          choreographerFor: choreographerFor,
          venueFor: (_) => null,
        ),
      ).archive;

      expect(archive.dances, isEmpty);
      expect(archive.programs.single.slots.length, 2);
    });

    test(
      'round-trips through the existing GenericJsonAdapter importer',
      () async {
        final program = _program(
          slots: [
            _slot(0, danceId: 'd1'),
            _slot(1, danceId: 'd2'),
            _slot(2, danceId: 'd3'),
            _slot(3, danceId: 'd2'), // duplicate must not import twice
          ],
        );

        final json = buildProgramShareBundle(
          program,
          danceFor: danceFor,
          choreographerFor: choreographerFor,
          venueFor: (_) => null,
          now: _now,
        );
        final imported = await _importedDances(json);

        expect(imported.map((d) => d.id).toSet(), {'d1', 'd2', 'd3'});
        expect(imported.length, 3);
        expect(
          imported.firstWhere((d) => d.id == 'd1').title,
          'Rory O\'More',
          reason: 'dance content survives the round-trip',
        );
      },
    );

    group('choreographers (author attribution, #412)', () {
      final authored = {
        'd1': _dance('d1', 'Rory O\'More', authorIds: ['c1']),
        'd2': _dance('d2', 'The Nice Combination', authorIds: ['c1', 'c2']),
        'd3': _dance('d3', 'Chinese New Year', authorIds: ['c-missing']),
        'd4': _dance('d4', 'Anonymous Reel'),
      };
      Dance? authoredDanceFor(String id) => authored[id];

      final choreographers = {
        'c1': _choreographer(
          'c1',
          'Cary Ravitz',
          email: 'cary@example.com',
          location: 'Lexington, KY',
        ),
        'c2': _choreographer('c2', 'Tom Hinds'),
      };
      Choreographer? choreographerCatalogFor(String id) => choreographers[id];

      test('includes only choreographers referenced by bundled dances', () {
        final program = _program(
          slots: [
            _slot(0, danceId: 'd1'),
            _slot(1, danceId: 'd2'),
          ],
        );

        final archive = decodeArchive(
          buildProgramShareBundle(
            program,
            danceFor: authoredDanceFor,
            choreographerFor: choreographerCatalogFor,
            venueFor: (_) => null,
            now: _now,
          ),
        ).archive;

        expect(archive.choreographers.map((c) => c.id).toSet(), {'c1', 'c2'});
      });

      test('a choreographer shared by several dances appears exactly once', () {
        // d1 -> c1, d2 -> c1 + c2. c1 is referenced twice but must not double.
        final program = _program(
          slots: [
            _slot(0, danceId: 'd1'),
            _slot(1, danceId: 'd2'),
            _slot(2, danceId: 'd1'), // repeated dance id too
          ],
        );

        final archive = decodeArchive(
          buildProgramShareBundle(
            program,
            danceFor: authoredDanceFor,
            choreographerFor: choreographerCatalogFor,
            venueFor: (_) => null,
            now: _now,
          ),
        ).archive;

        expect(
          archive.choreographers.where((c) => c.id == 'c1').length,
          1,
          reason: 'a choreographer referenced by multiple dances is deduped',
        );
        expect(archive.choreographers.length, 2);
      });

      test('a dance with no authors bundles fine with no choreographers', () {
        final program = _program(slots: [_slot(0, danceId: 'd4')]);

        final archive = decodeArchive(
          buildProgramShareBundle(
            program,
            danceFor: authoredDanceFor,
            choreographerFor: choreographerCatalogFor,
            venueFor: (_) => null,
            now: _now,
          ),
        ).archive;

        expect(archive.dances.map((d) => d.id), ['d4']);
        expect(archive.choreographers, isEmpty);
      });

      test('an unresolvable author id is skipped, never fatal', () {
        // d3 references 'c-missing', which choreographerFor cannot resolve.
        final program = _program(
          slots: [
            _slot(0, danceId: 'd1'),
            _slot(1, danceId: 'd3'),
          ],
        );

        final archive = decodeArchive(
          buildProgramShareBundle(
            program,
            danceFor: authoredDanceFor,
            choreographerFor: choreographerCatalogFor,
            venueFor: (_) => null,
            now: _now,
          ),
        ).archive;

        expect(archive.dances.map((d) => d.id).toSet(), {'d1', 'd3'});
        expect(
          archive.choreographers.map((c) => c.id),
          ['c1'],
          reason: 'the unresolved author id is dropped, the dance still ships',
        );
      });

      test('strips private email/location from shared choreographers', () {
        final program = _program(slots: [_slot(0, danceId: 'd1')]);

        final json = buildProgramShareBundle(
          program,
          danceFor: authoredDanceFor,
          choreographerFor: choreographerCatalogFor,
          venueFor: (_) => null,
          now: _now,
        );
        final shared = decodeArchive(json).archive.choreographers.single;

        expect(shared.id, 'c1');
        expect(shared.name, 'Cary Ravitz', reason: 'attribution is preserved');
        expect(shared.email, isNull, reason: 'private contact is not shared');
        expect(
          shared.location,
          isNull,
          reason: 'private contact is not shared',
        );
        // Defense in depth: the raw JSON must not carry the private fields.
        expect(json.contains('cary@example.com'), isFalse);
        expect(json.contains('Lexington, KY'), isFalse);
      });
    });

    group('venues (gathering + redaction, #515)', () {
      test('gathers the referenced venue, contacts cleared by default', () {
        final program = _program(
          slots: [_slot(0, danceId: 'd1')],
          venueId: 'v1',
        );

        final json = buildProgramShareBundle(
          program,
          danceFor: danceFor,
          choreographerFor: choreographerFor,
          venueFor: (id) =>
              id == 'v1' ? _venue('v1', withContacts: true) : null,
          now: _now,
        );
        final venue = decodeArchive(json).archive.venues.single;

        expect(venue.id, 'v1');
        expect(venue.name, 'Town Hall');
        // The postal address is classified deviceLocal in the privacy
        // registry and is cleared unconditionally (issue #853).
        expect(venue.city, isNull);
        expect(venue.stateProv, isNull);
        // All six contact fields are redacted by default (omit-by-default).
        expect(venue.contact1Name, isNull);
        expect(venue.contact1Phone, isNull);
        expect(venue.contact1Email, isNull);
        expect(venue.contact2Name, isNull);
        expect(venue.contact2Phone, isNull);
        expect(venue.contact2Email, isNull);
        // Defense in depth: no contact PII in the raw payload.
        expect(json.contains('Alex Caller'), isFalse);
        expect(json.contains('alex@example.com'), isFalse);
        expect(json.contains('555-0100'), isFalse);
      });

      test('honors includeVenueContact for opted-in fields only', () {
        final program = _program(
          slots: [_slot(0, danceId: 'd1')],
          venueId: 'v1',
        );

        final json = buildProgramShareBundle(
          program,
          danceFor: danceFor,
          choreographerFor: choreographerFor,
          venueFor: (_) => _venue('v1', withContacts: true),
          includeVenueContact: {VenueContactField.contact1Email},
          now: _now,
        );
        final venue = decodeArchive(json).archive.venues.single;

        expect(venue.contact1Email, 'alex@example.com');
        // Everything not opted in is still cleared.
        expect(venue.contact1Name, isNull);
        expect(venue.contact1Phone, isNull);
        expect(venue.contact2Name, isNull);
        expect(venue.contact2Phone, isNull);
        expect(venue.contact2Email, isNull);
        // Only the opted-in value appears in the raw payload.
        expect(json.contains('alex@example.com'), isTrue);
        expect(json.contains('bo@example.com'), isFalse);
        expect(json.contains('555-0100'), isFalse);
      });

      test('omits an unresolvable venueId, never fatal', () {
        final program = _program(
          slots: [_slot(0, danceId: 'd1')],
          venueId: 'missing',
        );

        final archive = decodeArchive(
          buildProgramShareBundle(
            program,
            danceFor: danceFor,
            choreographerFor: choreographerFor,
            venueFor: (_) => null,
            now: _now,
          ),
        ).archive;

        expect(archive.venues, isEmpty);
        // The program still carries its (now dangling) venueId for the receiver.
        expect(archive.programs.single.venueId, 'missing');
      });

      test('embeds no venue and skips the resolver without a venueId', () {
        final program = _program(slots: [_slot(0, danceId: 'd1')]);

        var called = false;
        final archive = decodeArchive(
          buildProgramShareBundle(
            program,
            danceFor: danceFor,
            choreographerFor: choreographerFor,
            venueFor: (_) {
              called = true;
              return null;
            },
            now: _now,
          ),
        ).archive;

        expect(archive.venues, isEmpty);
        expect(
          called,
          isFalse,
          reason: 'the resolver is not consulted when venueId is null',
        );
      });

      test('the embedded sanitized venue survives a codec round-trip', () {
        final program = _program(
          slots: [_slot(0, danceId: 'd1')],
          venueId: 'v1',
        );

        final json = buildProgramShareBundle(
          program,
          danceFor: danceFor,
          choreographerFor: choreographerFor,
          venueFor: (_) => _venue('v1', withContacts: true),
          now: _now,
        );
        final decoded = decodeArchive(json).archive;

        // Canonical round-trip identity holds for the sanitized venue.
        expect(encodeArchive(decoded), json);
        final venue = decoded.venues.single;
        expect(venue.name, 'Town Hall');
        expect(populatedVenueContactFields(venue), isEmpty);
      });
    });
  });

  group('programShareBundleFileName', () {
    test('sanitizes illegal characters to underscores and keeps .ccshare', () {
      expect(
        programShareBundleFileName('Friday Contra: 3/9 <Town Hall>'),
        'Friday_Contra__3_9__Town_Hall_.ccshare',
      );
    });

    test('preserves safe characters', () {
      expect(
        programShareBundleFileName('spring-fling_2026.v1'),
        'spring-fling_2026.v1.ccshare',
      );
    });

    test('falls back to a stable default for an empty/all-illegal title', () {
      expect(programShareBundleFileName('   '), 'program.ccshare');
      expect(programShareBundleFileName('///'), 'program.ccshare');
    });

    test('does not allow path traversal through the title', () {
      final name = programShareBundleFileName('../../etc/passwd');
      expect(name.contains('/'), isFalse);
      expect(
        name.contains('..'),
        isTrue,
        reason: 'dots are safe; separators are not',
      );
      expect(name, endsWith('.ccshare'));
    });
  });

  // The whole point of #412: verify on the RECEIVE side that the choreographers
  // the builder now embeds actually restore author attribution end-to-end, via
  // the real receive-side commit engine (CompendiumArchiveImporter ->
  // ImportPipeline) over the real CompendiumDatabase (FK enforced).
  group('end-to-end author attribution on the receiver (#412)', () {
    // #432 moved the commit engine out of ArchiveIntakeService (now a
    // validation-only gate) into the core CompendiumArchiveImporter, which the
    // review screen drives after consent. This helper exercises that same
    // engine directly — decode Dart-side (as intake does), then commit — to keep
    // the receive-side author-attribution coverage.
    Future<CompendiumArchiveImportResult> receive(
      CompendiumRepositories repos,
      String json,
    ) async {
      final archive = decodeArchive(json).archive;
      final importer = CompendiumArchiveImporter(
        ImportPipeline(repos.dances, repos.choreographers),
        repos.programs,
        repos.venues,
      );
      return importer.import(json, archive, now: DateTime.utc(2026, 7, 20));
    }

    Future<Dance> danceByTitle(
      CompendiumRepositories repos,
      String title,
    ) async =>
        (await repos.dances.listAll()).firstWhere((d) => d.title == title);

    Future<List<String>> authorNamesOf(
      CompendiumRepositories repos,
      Dance dance,
    ) async {
      final names = <String>[];
      for (final id in dance.authorIds) {
        final c = await repos.choreographers.getById(id);
        if (c != null) names.add(c.name);
      }
      return names;
    }

    test('a received authored dance keeps its choreographer', () async {
      final repos = openTestRepositories();

      final program = _program(slots: [_slot(0, danceId: 'd1')]);
      final json = buildProgramShareBundle(
        program,
        danceFor: (id) =>
            id == 'd1' ? _dance('d1', 'Rory O\'More', authorIds: ['c1']) : null,
        choreographerFor: (id) => id == 'c1'
            ? _choreographer(
                'c1',
                'Cary Ravitz',
                email: 'cary@example.com',
                location: 'Lexington, KY',
              )
            : null,
        venueFor: (_) => null,
        now: _now,
      );

      final result = await receive(repos, json);
      expect(result.primaryProgramId, isNotNull);

      final imported = await danceByTitle(repos, 'Rory O\'More');
      expect(await authorNamesOf(repos, imported), [
        'Cary Ravitz',
      ], reason: 'the received dance is attributed, not authorless');

      // The program slot resolves to the imported dance (no placeholder).
      final importedProgram = (await repos.programs.listAll()).single;
      expect(importedProgram.slots.single.danceId, imported.id);
      expect(
        result.programIssues.where(
          (i) => i.code == 'archive_program_unresolved_dance',
        ),
        isEmpty,
      );

      // The received choreographer carries no private contact data.
      final author = await repos.choreographers.getById(
        imported.authorIds.single,
      );
      expect(author!.email, isNull);
      expect(author.location, isNull);
    });

    test('reuses a choreographer the receiver already has, by name', () async {
      final repos = openTestRepositories();
      // The receiver already knows this author under a DIFFERENT id.
      // ignore: unused_result
      await repos.choreographers.upsert(
        Choreographer(id: 'local-cary', name: 'Cary Ravitz'),
      );

      final program = _program(slots: [_slot(0, danceId: 'd1')]);
      final json = buildProgramShareBundle(
        program,
        danceFor: (id) => id == 'd1'
            ? _dance('d1', 'Rory O\'More', authorIds: ['sender-cary'])
            : null,
        choreographerFor: (id) =>
            id == 'sender-cary' ? _choreographer(id, 'Cary Ravitz') : null,
        venueFor: (_) => null,
        now: _now,
      );

      final result = await receive(repos, json);
      expect(result.primaryProgramId, isNotNull);

      final imported = await danceByTitle(repos, 'Rory O\'More');
      expect(imported.authorIds, ['local-cary'], reason: 'matched by name');
      expect(
        await repos.choreographers.listAll(),
        hasLength(1),
        reason: 'no duplicate choreographer created',
      );
    });

    test(
      'a received dance with no authors imports fine, unattributed',
      () async {
        final repos = openTestRepositories();

        final program = _program(slots: [_slot(0, danceId: 'd1')]);
        final json = buildProgramShareBundle(
          program,
          danceFor: (id) => id == 'd1' ? _dance('d1', 'Anonymous Reel') : null,
          choreographerFor: (_) => null,
          venueFor: (_) => null,
          now: _now,
        );

        final result = await receive(repos, json);
        expect(result.primaryProgramId, isNotNull);

        final imported = await danceByTitle(repos, 'Anonymous Reel');
        expect(imported.authorIds, isEmpty);
        expect(await repos.choreographers.listAll(), isEmpty);
      },
    );

    test('a shared program keeps its venue link, contacts redacted', () async {
      final repos = openTestRepositories();

      final program = _program(
        slots: [_slot(0, danceId: 'd1')],
        venueId: 'v1',
      );
      final json = buildProgramShareBundle(
        program,
        danceFor: (id) => id == 'd1' ? _dance('d1', 'Rory O\'More') : null,
        choreographerFor: (_) => null,
        venueFor: (id) => id == 'v1' ? _venue('v1', withContacts: true) : null,
        now: _now,
      );

      final result = await receive(repos, json);
      expect(result.primaryProgramId, isNotNull);

      final importedProgram = (await repos.programs.listAll()).single;
      expect(
        importedProgram.venueId,
        isNotNull,
        reason: 'the venue link survives the round-trip',
      );

      final venue = await repos.venues.getById(importedProgram.venueId!);
      expect(venue, isNotNull);
      expect(venue!.name, 'Town Hall');
      // The address was redacted on the send side, so the receiver's copy of
      // the venue carries the name but not the postal address (issue #853).
      expect(venue.city, isNull);
      // Contact PII was redacted on the send side and never reaches the receiver.
      expect(venue.contact1Name, isNull);
      expect(venue.contact1Email, isNull);
      expect(venue.contact2Phone, isNull);

      expect(
        result.programIssues.where(
          (i) => i.code == 'archive_program_unresolved_venue',
        ),
        isEmpty,
      );
    });

    test(
      'a shared program with a dangling venueId imports venue-less',
      () async {
        final repos = openTestRepositories();

        final program = _program(
          slots: [_slot(0, danceId: 'd1')],
          venueId: 'missing',
        );
        final json = buildProgramShareBundle(
          program,
          danceFor: (id) => id == 'd1' ? _dance('d1', 'Rory O\'More') : null,
          choreographerFor: (_) => null,
          venueFor: (_) => null,
          now: _now,
        );

        final result = await receive(repos, json);
        expect(result.primaryProgramId, isNotNull);

        final importedProgram = (await repos.programs.listAll()).single;
        expect(
          importedProgram.venueId,
          isNull,
          reason: 'the dangling venue link is nulled (tolerance unchanged)',
        );
        expect(await repos.venues.listAll(), isEmpty);
      },
    );
  });
}
