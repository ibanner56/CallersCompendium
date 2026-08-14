/// The seam between send-side redaction (app package) and cross-import venue
/// dedupe (`compendium_core`), which no test covered before issue #853.
///
/// The two halves are each well tested in isolation and that is exactly why the
/// interaction escaped: `venue_dedupe_test.dart` and
/// `compendium_archive_import_test.dart` build [Venue] objects directly with
/// `address1`/`city` populated, never routing them through
/// [sanitizeVenueForShare]; the app-side share tests never ask whether the
/// result would dedupe. The question "does a *redacted* venue still dedupe?"
/// was asked by nothing, so a full green suite said nothing about it.
///
/// **What these tests pin down is a known, accepted limitation of the
/// *content-fingerprint* dedupe path, not a desirable behaviour.** Redacting
/// the postal address (issue #853 — the address block is classified
/// `EgressClass.deviceLocal`) removes both of the locating fields
/// [venueFingerprint] requires, so a shared venue can no longer produce a key
/// and cross-import venue dedupe (issue #456) does not apply to bundles *for
/// this path*.
///
/// Issue #899 adds a complementary **provenance-based path** that works for
/// re-imports of shared bundles: each freshly-minted venue receives a
/// `(source, externalId)` provenance stamp keyed on its bundle-original id,
/// so a re-import recognises it by exact match rather than by content. These
/// tests remain load-bearing for the fingerprint path: they ensure that only
/// the exact-match path fires for shared bundles and that the fingerprint gate
/// is never accidentally re-keyed on weaker content fields (which would risk
/// false merges).
///
/// They exist so that the tradeoff is **visible and load-bearing** rather than
/// rediscovered: if anyone later re-keys the fingerprint on fields that still
/// travel, these tests fail and must be rewritten deliberately, which is the
/// point at which the false-merge risk of a weaker key gets considered.
library;

import 'package:compendium_app/src/export/program_share_bundle.dart';
import 'package:compendium_app/src/export/share_sanitization.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 1, 1);

Venue _venue() => Venue(
  id: 'v1',
  name: 'Grange Hall',
  address1: '123 Main St',
  city: 'Montpelier',
  stateProv: 'VT',
  country: 'USA',
  postalCode: '05602',
  website: 'https://grange.example',
  eventName: 'Second Saturday Contra',
);

final _dance = Dance(
  id: 'd1',
  title: "Rory O'More",
  authorIds: const [],
  figures: const [],
  sourceCitations: const [],
  customFields: const [],
  createdAt: _now,
  updatedAt: _now,
);

final _program = Program(
  id: 'p1',
  title: 'Friday Contra',
  venueId: 'v1',
  slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  group('venue dedupe across the share redaction seam (#853 / #456)', () {
    test('an unredacted venue produces a fingerprint', () {
      // Control: proves the fixture is strong enough to dedupe *before*
      // redaction, so the null below is caused by redaction and not by a
      // weakly-described fixture.
      expect(venueFingerprint(_venue()), isNotNull);
    });

    test('a share-redacted venue produces NO fingerprint', () {
      // venueFingerprint requires name + (address1 or city). Redaction clears
      // both locating fields, so the strong-key threshold can never be met.
      final redacted = sanitizeVenueForShare(_venue());
      expect(redacted.name, 'Grange Hall');
      expect(redacted.address1, isNull);
      expect(redacted.city, isNull);
      expect(venueFingerprint(redacted), isNull);
    });

    test('a real share bundle carries no venue the importer can dedupe on', () {
      // The end-to-end form of the same fact, through the actual builder:
      // this mirrors CompendiumArchiveImporter's `canDedupe` gate
      // (compendium_archive_import.dart), which preloads the fingerprint
      // index only when some bundled venue yields a non-null key.
      final json = buildProgramShareBundle(
        _program,
        danceFor: (id) => id == 'd1' ? _dance : null,
        choreographerFor: (_) => null,
        venueFor: (id) => id == 'v1' ? _venue() : null,
        now: _now,
      );
      final venues = decodeArchive(json).archive.venues;

      expect(venues, hasLength(1), reason: 'the venue still travels');
      expect(venues.single.name, 'Grange Hall');
      // Descriptive fields survive; only the locating ones are gone.
      expect(venues.single.website, 'https://grange.example');
      expect(venues.single.eventName, 'Second Saturday Contra');

      final canDedupe = venues.any((v) => venueFingerprint(v) != null);
      expect(
        canDedupe,
        isFalse,
        reason:
            'Documents the accepted limitation of the content-fingerprint path: '
            'no bundled venue can produce a fingerprint, so the importer never '
            'preloads its fingerprint index for a first-time import of this '
            'bundle. Note: a *re*-import of the same bundle will dedupe by '
            'provenance (issue #899) rather than by fingerprint — this test '
            'only covers the fingerprint gate. If this ever goes true, the '
            'fingerprint was re-keyed — revisit the false-merge tradeoff and '
            'the docs that describe this.',
      );
    });
  });
}
