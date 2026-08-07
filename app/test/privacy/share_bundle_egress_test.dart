/// Egress ratchet for the program share bundle (issue #853).
///
/// The privacy registry
/// (`packages/compendium_core/lib/src/privacy/field_registry.dart`) says which
/// columns may leave the device, and until now **nothing checked it at the
/// boundary**: the two tests under `packages/compendium_core/test/privacy/` are
/// a *coverage* ratchet ("every schema column has an entry") and a doc-render
/// test. Neither looks at what an export actually emits, which is how seven
/// venue address columns and `choreographers.deceased` — all classified
/// [EgressClass.deviceLocal] — shipped in every `.ccshare` bundle.
///
/// This test closes that gap for the share bundle, the surface that emits whole
/// entity records off-device. It derives its expectations from the registry
/// rather than from a hand-written list, so a **new** non-`shareable` column
/// cannot be added and quietly serialized: [_probes] must cover it, and the
/// export must not carry it.
///
/// Precedent: `packages/compendium_core/test/privacy/
/// data_classification_coverage_test.dart` — same shape (enumerate the real
/// artefact, diff against a declared set, fail with a paste-ready list).
///
/// There is deliberately **no exclusion list**. Every non-`shareable` column in
/// an archive-carried table must be absent from the export, with nothing carved
/// out; a field that genuinely should travel belongs in the registry as
/// `shareable`, with its reason, rather than in a carve-out here.
///
/// Scope note: the six `venues.contact*` columns are opt-in, not never-share.
/// The guard exports with **no** consent granted (the default), which is the
/// state the boundary must hold unconditionally; the opt-in path is asserted
/// separately at the end.
library;

import 'dart:convert';

import 'package:compendium_app/src/export/program_share_bundle.dart';
import 'package:compendium_app/src/export/share_sanitization.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The database tables whose rows a [CompendiumArchive] carries verbatim.
///
/// A non-`shareable` column in any of these can reach an export, so all of them
/// are reconciled against [_probes] below. Tables outside this set (settings,
/// caches, derived indexes) have no archive representation.
const _archiveTables = {
  'programs',
  'program_slots',
  'dances',
  'choreographers',
  'venues',
};

/// How one non-`shareable` column is detected in the emitted JSON.
///
/// [entityList] is the archive's top-level array the column's row lands in, and
/// [leaked] answers "does this emitted entity still carry the field?" — which is
/// not always key presence: the codec emits `deceased` unconditionally as a
/// bool, so for that one the question is whether the value is still `true`.
class _Probe {
  const _Probe(this.entityList, this.leaked, this.populate);

  final String entityList;

  /// True when [entity] still carries this field's real value.
  final bool Function(Map<String, Object?> entity) leaked;

  /// The distinctive value the fixture stores in this field, so a probe that
  /// fires is unambiguous and a probe that cannot fire is detectable.
  final Object Function() populate;
}

/// Registry column -> how to detect it in the export. Reconciled against the
/// registry below, so it cannot fall behind.
final Map<String, _Probe> _probes = {
  'choreographers.email': _Probe(
    'choreographers',
    (e) => e.containsKey('email'),
    () => 'leak-choreographer-email@example.com',
  ),
  'choreographers.location': _Probe(
    'choreographers',
    (e) => e.containsKey('location'),
    () => 'LEAK_CHOREOGRAPHER_LOCATION',
  ),
  // Non-nullable bool, emitted unconditionally by the codec: redaction means
  // `false`, so the key's presence is not the leak — a `true` value is.
  'choreographers.deceased': _Probe(
    'choreographers',
    (e) => e['deceased'] == true,
    () => true,
  ),
  'venues.address1': _Probe(
    'venues',
    (e) => e.containsKey('address1'),
    () => 'LEAK_VENUE_ADDRESS1',
  ),
  'venues.address2': _Probe(
    'venues',
    (e) => e.containsKey('address2'),
    () => 'LEAK_VENUE_ADDRESS2',
  ),
  'venues.city': _Probe(
    'venues',
    (e) => e.containsKey('city'),
    () => 'LEAK_VENUE_CITY',
  ),
  'venues.state_prov': _Probe(
    'venues',
    (e) => e.containsKey('stateProv'),
    () => 'LEAK_VENUE_STATEPROV',
  ),
  'venues.country': _Probe(
    'venues',
    (e) => e.containsKey('country'),
    () => 'LEAK_VENUE_COUNTRY',
  ),
  'venues.postal_code': _Probe(
    'venues',
    (e) => e.containsKey('postalCode'),
    () => 'LEAK_VENUE_POSTALCODE',
  ),
  'venues.plus4': _Probe(
    'venues',
    (e) => e.containsKey('plus4'),
    () => 'LEAK_VENUE_PLUS4',
  ),
  'venues.contact1_name': _Probe(
    'venues',
    (e) => e.containsKey('contact1Name'),
    () => 'LEAK_VENUE_CONTACT1NAME',
  ),
  'venues.contact1_phone': _Probe(
    'venues',
    (e) => e.containsKey('contact1Phone'),
    () => 'LEAK_VENUE_CONTACT1PHONE',
  ),
  'venues.contact1_email': _Probe(
    'venues',
    (e) => e.containsKey('contact1Email'),
    () => 'leak-venue-contact1@example.com',
  ),
  'venues.contact2_name': _Probe(
    'venues',
    (e) => e.containsKey('contact2Name'),
    () => 'LEAK_VENUE_CONTACT2NAME',
  ),
  'venues.contact2_phone': _Probe(
    'venues',
    (e) => e.containsKey('contact2Phone'),
    () => 'LEAK_VENUE_CONTACT2PHONE',
  ),
  'venues.contact2_email': _Probe(
    'venues',
    (e) => e.containsKey('contact2Email'),
    () => 'leak-venue-contact2@example.com',
  ),
};

/// Every non-`shareable` column the archive can carry, straight from the
/// registry.
Set<String> _nonShareableArchiveColumns() => {
  for (final entry in fieldClassifications.entries)
    if (_archiveTables.contains(entry.key.split('.').first) &&
        entry.value.egress != EgressClass.shareable)
      entry.key,
};

String _p(String column) => _probes[column]!.populate() as String;

final _now = DateTime.utc(2026, 1, 1);

/// A venue with **every** non-`shareable` column populated with a distinctive
/// value, alongside the shareable descriptive fields that must survive.
final _venue = Venue(
  id: 'v1',
  name: 'Grange Hall',
  address1: _p('venues.address1'),
  address2: _p('venues.address2'),
  city: _p('venues.city'),
  stateProv: _p('venues.state_prov'),
  country: _p('venues.country'),
  postalCode: _p('venues.postal_code'),
  plus4: _p('venues.plus4'),
  website: 'https://grange.example',
  sponsor: 'Capital City Grange',
  eventName: 'Second Saturday Contra',
  time: '8pm',
  genericSchedule: '2nd Saturdays',
  price: r'$12',
  notes: 'Enter by the side door.',
  contact1Name: _p('venues.contact1_name'),
  contact1Phone: _p('venues.contact1_phone'),
  contact1Email: _p('venues.contact1_email'),
  contact2Name: _p('venues.contact2_name'),
  contact2Phone: _p('venues.contact2_phone'),
  contact2Email: _p('venues.contact2_email'),
);

final _choreographer = Choreographer(
  id: 'c1',
  name: 'Ada Caller',
  website: 'https://ada.example',
  notes: 'Writes lovely becket flips.',
  email: _p('choreographers.email'),
  location: _p('choreographers.location'),
  deceased: true,
);

final _dance = Dance(
  id: 'd1',
  title: "Rory O'More",
  authorIds: const ['c1'],
  figures: [
    Figure(move: 'swing', params: const {'beats': 16, 'who': 'partners'}),
  ],
  sourceCitations: const [],
  customFields: const [],
  createdAt: _now,
  updatedAt: _now,
);

final _program = Program(
  id: 'p1',
  title: 'Friday Contra',
  eventDate: DateTime.utc(2026, 3, 9),
  venue: 'Town Hall',
  venueId: 'v1',
  band: 'The Ripplers',
  caller: 'Isaac',
  dancerLevel: 'All',
  notes: 'Bring water.',
  slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
  createdAt: _now,
  updatedAt: _now,
);

String _export({Set<VenueContactField> includeVenueContact = const {}}) =>
    buildProgramShareBundle(
      _program,
      danceFor: (id) => id == 'd1' ? _dance : null,
      choreographerFor: (id) => id == 'c1' ? _choreographer : null,
      venueFor: (id) => id == 'v1' ? _venue : null,
      includeVenueContact: includeVenueContact,
      now: _now,
    );

List<Map<String, Object?>> _entities(String json, String list) {
  final root = jsonDecode(json) as Map<String, Object?>;
  final entries = (root[list] as List?) ?? const [];
  return [for (final e in entries) (e as Map).cast<String, Object?>()];
}

void main() {
  group('share-bundle egress ratchet', () {
    test('every non-shareable archive column has a probe', () {
      final missing =
          _nonShareableArchiveColumns()
              .difference(_probes.keys.toSet())
              .toList()
            ..sort();
      expect(
        missing,
        isEmpty,
        reason:
            'These columns are classified non-shareable in the privacy '
            'registry, but this test does not know how to look for them in an '
            'export, so nothing would stop them being serialized. Add a '
            '_Probe for each:\n  ${missing.join('\n  ')}',
      );
    });

    test('no probe describes a column that is shareable or gone', () {
      final stale =
          _probes.keys
              .toSet()
              .difference(_nonShareableArchiveColumns())
              .toList()
            ..sort();
      expect(
        stale,
        isEmpty,
        reason:
            'These probes no longer match a non-shareable registry column — '
            'either the column was reclassified or removed. Delete the stale '
            'probes so this test keeps describing the real boundary:\n  '
            '${stale.join('\n  ')}',
      );
    });

    test('the fixture populates every probed column', () {
      // Without this, a probe could pass merely because the fixture never set
      // the field, and the guard below would read as rigorous while being
      // structurally incapable of failing. Assert against the UNSANITIZED
      // records — what the export would emit with the guards removed.
      final unsanitized = <String, Map<String, Object?>>{
        'choreographers': {
          'email': _choreographer.email,
          'location': _choreographer.location,
          'deceased': _choreographer.deceased,
        },
        'venues': {
          'address1': _venue.address1,
          'address2': _venue.address2,
          'city': _venue.city,
          'stateProv': _venue.stateProv,
          'country': _venue.country,
          'postalCode': _venue.postalCode,
          'plus4': _venue.plus4,
          'contact1Name': _venue.contact1Name,
          'contact1Phone': _venue.contact1Phone,
          'contact1Email': _venue.contact1Email,
          'contact2Name': _venue.contact2Name,
          'contact2Phone': _venue.contact2Phone,
          'contact2Email': _venue.contact2Email,
        },
      };

      final unset = <String>[];
      _probes.forEach((column, probe) {
        // Mirror the codec's omit-nulls behaviour so `leaked` sees the same
        // shape it would see in a real export.
        final asEmitted = {
          for (final e in unsanitized[probe.entityList]!.entries)
            if (e.value != null) e.key: e.value,
        };
        if (!probe.leaked(asEmitted)) unset.add(column);
      });

      expect(
        unset..sort(),
        isEmpty,
        reason:
            'The fixture leaves these probed columns unset, so their probes '
            'can never fire and the guard below is vacuous for them:\n  '
            '${unset.join('\n  ')}',
      );
    });

    test('no non-shareable column survives into the exported JSON', () {
      final json = _export();
      final leaked = <String>[];
      _probes.forEach((column, probe) {
        for (final entity in _entities(json, probe.entityList)) {
          if (probe.leaked(entity)) leaked.add(column);
        }
      });

      expect(
        leaked..sort(),
        isEmpty,
        reason:
            'These columns are classified non-shareable in the privacy '
            'registry but the share bundle emitted them. Redact them in the '
            'share sanitizers (app/lib/src/export/share_sanitization.dart) — '
            'NOT in archive_codec.dart, which also serializes the user\'s own '
            'backup:\n  ${leaked.join('\n  ')}',
      );
    });

    test('shareable fields still survive the redaction', () {
      // The guard above must not be satisfiable by exporting nothing.
      final json = _export();

      final venue = _entities(json, 'venues').single;
      expect(venue['id'], 'v1');
      expect(venue['name'], 'Grange Hall');
      expect(venue['website'], 'https://grange.example');
      expect(venue['sponsor'], 'Capital City Grange');
      expect(venue['eventName'], 'Second Saturday Contra');
      expect(venue['time'], '8pm');
      expect(venue['genericSchedule'], '2nd Saturdays');
      expect(venue['price'], r'$12');
      expect(venue['notes'], 'Enter by the side door.');

      final choreographer = _entities(json, 'choreographers').single;
      expect(choreographer['name'], 'Ada Caller');
      expect(choreographer['website'], 'https://ada.example');
      expect(choreographer['notes'], 'Writes lovely becket flips.');

      expect(_entities(json, 'dances').single['title'], "Rory O'More");
      expect(_entities(json, 'programs').single['title'], 'Friday Contra');
    });

    test('an opted-in contact field survives, and only that one', () {
      final json = _export(
        includeVenueContact: {VenueContactField.contact1Email},
      );
      final venue = _entities(json, 'venues').single;

      expect(venue['contact1Email'], 'leak-venue-contact1@example.com');
      // Consent is per-field: opting one in must not open the others, and must
      // not reopen the address block, which has no opt-in at all.
      expect(venue.containsKey('contact1Name'), isFalse);
      expect(venue.containsKey('contact1Phone'), isFalse);
      expect(venue.containsKey('contact2Email'), isFalse);
      expect(venue.containsKey('address1'), isFalse);
      expect(venue.containsKey('city'), isFalse);
    });
  });
}
