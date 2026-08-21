import 'package:compendium_core/compendium_core.dart';

/// Redacts a [Choreographer]'s private personal data for inclusion in a
/// **shareable** export (any program/dance share path).
///
/// The authority for what may leave the device is the classification registry
/// (`packages/compendium_core/lib/src/privacy/field_registry.dart`), not a
/// prose rule on the model. Three choreographer columns are classified
/// [EgressClass.deviceLocal] there and are therefore cleared here:
///
/// * `email` and `location` — private contact data for someone who does not
///   use this app and cannot consent to a transfer (registry
///   `choreographers.email` / `choreographers.location`).
/// * `deceased` — "personal data about someone who cannot exercise any rights
///   over it" (registry `choreographers.deceased`). This flag used to be
///   preserved as public attribution; the registry says otherwise and the
///   registry wins (issue #853).
///
/// The public attribution fields (`name`, `website`, `notes`) and
/// identity/timestamps are preserved — all are classified `shareable`.
///
/// `deceased` is non-nullable and defaults to `false`, so redaction means
/// setting it `false` rather than clearing it. The archive codec emits the key
/// unconditionally, so a shared record always reads `"deceased": false` —
/// which carries no information about the real person.
///
/// These fields remain intact in the user's own full-DB snapshot/backup: that
/// path serializes the unsanitized records, and `deviceLocal` withholds a field
/// from a *shareable* export, not from the owner's own restorable copy.
///
/// It is intentionally a top-level, reusable function (not private to any one
/// builder): the program-share bundle uses it today, and the forthcoming
/// dance-share path (issue #298) must apply the identical redaction rather than
/// re-deriving an inline copyWith that could silently drift.
Choreographer sanitizeChoreographerForShare(Choreographer choreographer) =>
    choreographer.copyWith(
      clearEmail: true,
      clearLocation: true,
      deceased: false,
    );

/// The six contact-person PII fields on a [Venue] (the two contacts' name,
/// phone, and email). These identify a specific person to reach about the
/// venue, so they are treated as private and are OMIT-BY-DEFAULT in any
/// shareable export, surviving only through an explicit opt-in. Used as the
/// allow-list keys for [sanitizeVenueForShare] and to drive the pre-share
/// consent dialog.
///
/// These are not the only venue fields withheld from a share — the postal
/// address block is withheld too — but they are the only ones the user can opt
/// back in. See [sanitizeVenueForShare] for the full boundary.
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

/// Redacts a [Venue]'s private personal data for inclusion in a **shareable**
/// export (the program-share bundle and the program PDF today; the forthcoming
/// dance-share path must REUSE this helper rather than re-deriving the
/// redaction).
///
/// Share/export is a privacy boundary, and the authority for where it falls is
/// the classification registry
/// (`packages/compendium_core/lib/src/privacy/field_registry.dart`). Thirteen
/// venue columns are classified [EgressClass.deviceLocal] there, in two groups
/// that are redacted differently:
///
/// **Contact people — opt-in.** The six [VenueContactField]s
/// (`contact1Name/Phone/Email`, `contact2Name/Phone/Email`) are enforced via an
/// **allow-list**: every one *not* present in [include] is cleared. Because
/// [include] defaults to the empty set, a caller that forgets the argument
/// still gets full redaction — PII can only survive through an explicit,
/// positive [include] entry, populated only from the pre-share consent dialog.
///
/// **Postal address — always cleared.** `address1`, `address2`, `city`,
/// `stateProv`, `country`, `postalCode` and `plus4` are classified
/// `deviceLocal` (registry `venues.address1` … `venues.plus4`, DPV
/// `street`/`city`/`region`/`country`/`postalCode`, subject `thirdParty`), and
/// the registry's own venues note puts it plainly: *"a hall's identity is
/// public, its address book is not."* They are cleared unconditionally — there
/// is no opt-in for them, because none was ever offered to the user.
///
/// This corrects a real leak (issue #853). This helper previously kept the
/// address block, reasoning that "a dance hall's address is effectively
/// public"; that prose contradicted the registry, and nothing enforced either
/// side, so every `.ccshare` bundle and every exported program PDF carried a
/// venue's full street address off the device. The registry is the boundary and
/// the prose was wrong.
///
/// The venue-*descriptive* fields (`name`, `website`, `sponsor`, `eventName`,
/// `time`, `genericSchedule`, `price`, `notes`) are kept — all classified
/// `shareable`, the same rationale by which a choreographer's public
/// name/website/notes are kept in [sanitizeChoreographerForShare].
///
/// As with the choreographer helper, this withholds fields from a *shareable*
/// export only; the user's own full-DB snapshot/backup still carries them.
Venue sanitizeVenueForShare(
  Venue venue, {
  Set<VenueContactField> include = const {},
}) => venue.copyWith(
  clearAddress1: true,
  clearAddress2: true,
  clearCity: true,
  clearStateProv: true,
  clearCountry: true,
  clearPostalCode: true,
  clearPlus4: true,
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
