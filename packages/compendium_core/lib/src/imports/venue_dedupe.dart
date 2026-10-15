import '../model/venue.dart';
import '../util/text_sanitizer.dart';

/// Separator between fingerprint fields. `\u0000` (NUL) is a C0 control, which
/// [_normalizeField] strips from every field via [sanitizeImportedText] before
/// joining — so it can never occur *inside* a field and unambiguously delimits
/// them: a "Foo" / "Bar Baz" pairing can never collide with a "Foo Bar" / "Baz"
/// pairing. The strip runs here (not only on the import path) so the invariant
/// holds for **all** stored venues, including ones created/edited locally that
/// never passed through the importer's sanitizer.
const String _fieldSeparator = '\u0000';

/// Normalizes one venue field for fingerprinting: strips control/bidi/invisible
/// characters (via [sanitizeImportedText] — see below), then trims, lowercases
/// and collapses internal whitespace runs to a single space. Empty/whitespace-
/// only (or null) becomes `null` so an absent field never contributes noise.
///
/// The [sanitizeImportedText] pass is a **security invariant**, not cosmetic: a
/// locally-created venue never goes through the import sanitizer, so without
/// this an embedded NUL (the field separator) or other control character could
/// shift field boundaries and make two distinct venues fingerprint-equal — a
/// *false merge*. Stripping the same disallowed set the importer strips (C0/C1
/// controls, DEL, bidi overrides, invisible format chars) keeps the separator
/// guarantee true for every stored venue and also denies display-spoofing
/// characters any influence over a match.
///
/// Deliberately conservative otherwise — it does NOT fold diacritics or strip
/// punctuation (unlike `normalizeTitle` in `dedupe.dart`). A venue fingerprint
/// must never produce a *false merge* (two distinct halls collapsing into one),
/// so it tolerates *false splits* ("St." vs "Street", "Café" vs "Cafe") instead:
/// splitting duplicates a row harmlessly; merging would repoint a program at the
/// wrong venue.
String? _normalizeField(String? value) {
  if (value == null) return null;
  final normalized = sanitizeImportedText(
    value,
  ).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.isEmpty ? null : normalized;
}

/// Computes a cross-import dedupe fingerprint for [venue] from its **descriptive**
/// fields (`name` + `city` + `stateProv` + `address1`), or `null` when the venue
/// is too weakly described to safely match on.
///
/// Used by [VenueFingerprintIndex] so re-importing a bundle matches a venue the
/// receiver already holds instead of minting a duplicate (issue #456). Matching
/// only ever repoints an incoming program's `venueId` at the existing venue — it
/// never overwrites the existing record — so the fresh-mint guarantee (an
/// untrusted bundle can't mutate a local venue) is preserved.
///
/// **Strong-key threshold:** returns a key only when `name` is present AND at
/// least one locating field (`address1` or `city`) is present; otherwise `null`.
/// A bare name is far too common across distinct halls ("Town Hall", "Grange")
/// to dedupe on, so a weak venue is always fresh-minted, never merged.
///
/// **Contact/PII-independent:** deliberately excludes the redactable contact
/// fields (`contact1/2*`), `notes`, `price`, `website`, `schedule`, etc. #515
/// strips a shared venue's contact PII by default, so a fingerprint over those
/// fields could never match a local venue.
///
/// **Shared venues no longer produce a key at all (issue #853).** This function
/// was written when a shared venue still carried its postal address, and its
/// original rationale — that the key uses only fields that always travel — no
/// longer holds. The address block (`address1`/`address2`/`city`/`stateProv`/
/// `country`/`postalCode`/`plus4`) is classified `EgressClass.deviceLocal` in
/// the privacy registry, so `sanitizeVenueForShare` now clears it on every
/// export. That removes **both** locating fields the strong-key threshold
/// accepts, so `venueFingerprint` returns `null` for any venue that arrived in
/// a share bundle, `CompendiumArchiveImporter` never preloads its index, and
/// **cross-import dedupe does not apply to shared bundles** — re-importing the
/// same bundle mints another venue record — *for this content-fingerprint path*.
///
/// A complementary **provenance-based path** (issue #899) fills this gap:
/// the importer stamps a `(source, externalId)` provenance on every
/// freshly-minted venue (mirroring dance/program provenance), keyed on the
/// bundle's original venue id. On re-import the exact-match lookup fires before
/// this fingerprint is consulted, so re-importing the same shared bundle now
/// dedupes correctly without needing the postal address. The two paths are
/// checked in sequence: provenance-exact (no false merges, works for shared
/// bundles) → content-fingerprint (works for new bundles without prior
/// provenance, but requires an address).
///
/// This is a known, accepted limitation for the *fingerprint* path rather than
/// an oversight, and it is pinned by `app/test/export/share_venue_dedupe_seam_test.dart`.
/// Dedupe still works for venues that reach the importer with their address
/// intact (a Caller's Companion `.USR` import, a backup restore, or any local
/// venue already in the collection), as well as for re-imports of shared bundles
/// that were imported after schema v26 (via the new provenance path).
///
/// Re-keying on fields that *do* still travel (`name` + `website`/`eventName`)
/// would restore dedupe for bundles, but it weakens the key: two distinct halls
/// that share a name and an event name would then merge, and a false merge is
/// far less recoverable than a duplicate. That tradeoff has not been taken —
/// see issue #853's discussion before changing it.
String? venueFingerprint(Venue venue) {
  final name = _normalizeField(venue.name);
  final city = _normalizeField(venue.city);
  final stateProv = _normalizeField(venue.stateProv);
  final address1 = _normalizeField(venue.address1);

  if (name == null || (address1 == null && city == null)) return null;

  return [
    name,
    city ?? '',
    stateProv ?? '',
    address1 ?? '',
  ].join(_fieldSeparator);
}

/// An in-memory index that answers "does this incoming venue already exist?" by
/// content fingerprint, mirroring `DedupeIndex`'s pure-and-testable philosophy
/// (a snapshot with no I/O). The importer seeds it once from the existing venue
/// collection, then folds in each venue it mints so two fingerprint-equal venues
/// within a single bundle also collapse to one.
///
/// Ambiguity is tracked explicitly: if two *distinct* venue ids share a
/// fingerprint, that fingerprint is poisoned and [matchFor] returns `null` for
/// it — the importer then fresh-mints rather than guessing which existing venue
/// to repoint to.
class VenueFingerprintIndex {
  VenueFingerprintIndex([Iterable<Venue> venues = const []]) {
    for (final venue in venues) {
      add(venue.id, venue);
    }
  }

  final Map<String, String> _idByFingerprint = {};
  final Map<String, String> _fingerprintById = {};
  final Set<String> _ambiguousFingerprints = {};

  /// Records [venue] under [venueId]. A weakly-described venue (null
  /// fingerprint) is never a match target. If a second, *distinct* id is seen
  /// for a fingerprint, that fingerprint becomes ambiguous and permanently stops
  /// matching.
  ///
  /// Re-adding the same id with an *unchanged* fingerprint is a no-op. Re-adding
  /// it with a *changed* fingerprint (the importer's "last-seen wins" collapse of
  /// a repeated original venue id) retires the stale fingerprint first — so a
  /// later venue matching the old content can never be repointed at this
  /// now-changed record. A poisoned (ambiguous) fingerprint is left poisoned: two
  /// distinct ids already collided on it, so it stays a fresh-mint (never
  /// un-poisoned), consistent with the never-false-merge stance.
  void add(String venueId, Venue venue) {
    final fingerprint = venueFingerprint(venue);

    final priorFingerprint = _fingerprintById[venueId];
    if (priorFingerprint != null && priorFingerprint != fingerprint) {
      if (_idByFingerprint[priorFingerprint] == venueId) {
        _idByFingerprint.remove(priorFingerprint);
      }
      _fingerprintById.remove(venueId);
    }

    if (fingerprint == null) return;
    if (_ambiguousFingerprints.contains(fingerprint)) return;

    final existing = _idByFingerprint[fingerprint];
    if (existing == null) {
      _idByFingerprint[fingerprint] = venueId;
      _fingerprintById[venueId] = fingerprint;
    } else if (existing != venueId) {
      _idByFingerprint.remove(fingerprint);
      _ambiguousFingerprints.add(fingerprint);
    }
  }

  /// The single existing venue id that [venue] deduplicates to, or `null` when
  /// its key is weak, unmatched, or ambiguous (matches more than one venue).
  String? matchFor(Venue venue) {
    final fingerprint = venueFingerprint(venue);
    if (fingerprint == null) return null;
    return _idByFingerprint[fingerprint];
  }

  /// Whether [venue]'s fingerprint is present but poisoned — i.e. it collided
  /// with more than one distinct existing venue id — as opposed to simply
  /// weak/absent ([venueFingerprint] returning `null`) or unmatched.
  ///
  /// A caller that wants to raise a non-fatal notice only for a *genuine*
  /// collision (never for the far more common "too weakly described to score
  /// at all" case, which would otherwise fire on every ordinary import) uses
  /// this to distinguish the two: [matchFor] alone can't, since it returns
  /// `null` for both.
  bool isAmbiguous(Venue venue) {
    final fingerprint = venueFingerprint(venue);
    if (fingerprint == null) return false;
    return _ambiguousFingerprints.contains(fingerprint);
  }
}
