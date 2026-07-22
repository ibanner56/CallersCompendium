import '../model/venue.dart';

/// Separator between fingerprint fields. `\u0000` (NUL) can never occur in a
/// sanitized venue field (`sanitizeImportedText` strips C0 controls on decode),
/// so it unambiguously delimits fields — a "Foo" / "Bar, Baz" pairing can never
/// collide with a "Foo, Bar" / "Baz" pairing.
const String _fieldSeparator = '\u0000';

/// Normalizes one venue field for fingerprinting: trims, lowercases and
/// collapses internal whitespace runs to a single space. Empty/whitespace-only
/// (or null) becomes `null` so an absent field never contributes noise.
///
/// Deliberately conservative — it does NOT fold diacritics or strip punctuation
/// (unlike `normalizeTitle` in `dedupe.dart`). A venue fingerprint must never
/// produce a *false merge* (two distinct halls collapsing into one), so it
/// tolerates *false splits* ("St." vs "Street", "Café" vs "Cafe") instead:
/// splitting duplicates a row harmlessly; merging would repoint a program at the
/// wrong venue.
String? _normalizeField(String? value) {
  if (value == null) return null;
  final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
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
/// fields could never match a local venue — the key uses only fields that always
/// travel with a shared venue.
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
  final Set<String> _ambiguousFingerprints = {};

  /// Records [venue] under [venueId]. A weakly-described venue (null
  /// fingerprint) is ignored — it can never be a dedupe target. If a second,
  /// *distinct* id is seen for a fingerprint, that fingerprint becomes ambiguous
  /// and stops matching. Re-adding the same id for a fingerprint is a no-op.
  void add(String venueId, Venue venue) {
    final fingerprint = venueFingerprint(venue);
    if (fingerprint == null) return;
    if (_ambiguousFingerprints.contains(fingerprint)) return;

    final existing = _idByFingerprint[fingerprint];
    if (existing == null) {
      _idByFingerprint[fingerprint] = venueId;
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
}
