import 'package:compendium_core/compendium_core.dart';

/// Redacts a [Choreographer]'s private contact data for inclusion in a
/// **shareable** export (any program/dance share path).
///
/// The [Choreographer] model documents (choreographer.dart:6-9) that [email]
/// and [location] are private contact data that are safe in the user's own
/// full-DB snapshot/backup but MUST NOT be emitted in any shareable export.
/// This helper enforces that at the single send-side choke point: it clears
/// `email` and `location` while preserving the public attribution fields
/// (`name`, `website`, `notes`, `deceased`, and identity/timestamps).
///
/// It is intentionally a top-level, reusable function (not private to any one
/// builder): the program-share bundle uses it today, and the forthcoming
/// dance-share path (issue #298) must apply the identical redaction rather than
/// re-deriving an inline copyWith that could silently drift.
Choreographer sanitizeChoreographerForShare(Choreographer choreographer) =>
    choreographer.copyWith(clearEmail: true, clearLocation: true);

/// The six contact-person PII fields on a [Venue] (the two contacts' name,
/// phone, and email). These identify a specific person to reach about the
/// venue, so — unlike the venue's own descriptive fields (name, address,
/// schedule, …) — they are treated as private and are OMIT-BY-DEFAULT in any
/// shareable export. Used as the allow-list keys for [sanitizeVenueForShare]
/// and to drive the pre-share consent dialog.
enum VenueContactField {
  contact1Name,
  contact1Phone,
  contact1Email,
  contact2Name,
  contact2Phone,
  contact2Email,
}

/// The subset of [VenueContactField]s that are actually populated (non-null) on
/// [venue]. The consent dialog uses this to decide whether to prompt at all and
/// which rows to offer — an empty result means there is no contact PII to leak,
/// so no dialog is shown.
Set<VenueContactField> populatedVenueContactFields(Venue venue) => {
  if (venue.contact1Name != null) VenueContactField.contact1Name,
  if (venue.contact1Phone != null) VenueContactField.contact1Phone,
  if (venue.contact1Email != null) VenueContactField.contact1Email,
  if (venue.contact2Name != null) VenueContactField.contact2Name,
  if (venue.contact2Phone != null) VenueContactField.contact2Phone,
  if (venue.contact2Email != null) VenueContactField.contact2Email,
};

/// Redacts a [Venue]'s contact-person PII for inclusion in a **shareable**
/// export (the program-share bundle today; the forthcoming dance-share path
/// must REUSE this helper rather than re-deriving the redaction).
///
/// Share/export is a privacy boundary: a venue's contact people are personal
/// details that MUST NOT leave the device unless the user has affirmatively
/// opted in. This helper enforces omit-by-default via an **allow-list**: every
/// one of the six [VenueContactField]s **not** present in [include] is cleared
/// (via [Venue.copyWith]'s `clear*` flags). Because [include] defaults to the
/// empty set, a caller that forgets the argument still gets full redaction —
/// PII can only survive through an explicit, positive [include] entry.
///
/// All venue-*descriptive* fields (name, address1/2, city, stateProv, country,
/// postalCode, plus4, website, sponsor, eventName, time, genericSchedule,
/// price, notes) are kept: a dance hall's address is effectively public, the
/// same rationale by which a choreographer's public name/website/notes are kept
/// in [sanitizeChoreographerForShare].
Venue sanitizeVenueForShare(
  Venue venue, {
  Set<VenueContactField> include = const {},
}) => venue.copyWith(
  clearContact1Name: !include.contains(VenueContactField.contact1Name),
  clearContact1Phone: !include.contains(VenueContactField.contact1Phone),
  clearContact1Email: !include.contains(VenueContactField.contact1Email),
  clearContact2Name: !include.contains(VenueContactField.contact2Name),
  clearContact2Phone: !include.contains(VenueContactField.contact2Phone),
  clearContact2Email: !include.contains(VenueContactField.contact2Email),
);

/// Returns a shallow copy of [venuesById] with the entry for [venueId] (when
/// present) replaced by its [sanitizeVenueForShare] form for the [include] set;
/// every other entry is preserved. A `null` [venueId], or one that is not in
/// the map, returns [venuesById] unchanged.
///
/// This is the funnel the **PDF export** path uses to hand its renderer a venue
/// whose contact PII is *physically absent* unless the user opted in. Both the
/// share-bundle and the PDF paths therefore redact through the single
/// [sanitizeVenueForShare] primitive — the PDF renderer never needs (and must
/// not grow) its own parallel redaction; it simply draws whatever survives.
Map<String, Venue> venuesWithSanitizedContact(
  Map<String, Venue> venuesById,
  String? venueId, {
  Set<VenueContactField> include = const {},
}) {
  if (venueId == null) return venuesById;
  final venue = venuesById[venueId];
  if (venue == null) return venuesById;
  return {
    ...venuesById,
    venueId: sanitizeVenueForShare(venue, include: include),
  };
}
