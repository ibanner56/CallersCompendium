import 'package:meta/meta.dart';

import 'provenance.dart';

/// A reusable venue (a hall, church, grange, festival site, …) that programs
/// reference. A first-class entity like [Choreographer]/[PublishedSource] — many
/// programs can be held at the same venue, so address/contact/schedule edits
/// happen in one place.
///
/// Faithful to Caller's Companion's `Venue` table, minus its FileMaker plumbing
/// (`VenueDisplay_c`, `zc_*`/`zi_*` audit, `zk_Constant`, `SiteID`, the numeric
/// `zk_VenueID`): the app mints its own uuid [id], and CC's stored
/// `VenueDisplay_c` is reimplemented as the computed [displayName] getter rather
/// than a persisted column.
///
/// A program links to a venue by id ([Program.venueId]); the free-text
/// [Program.venue] label persists independently so the two modes coexist
/// non-destructively (see `docs/design/domain-model.md`).
@immutable
class Venue {
  Venue({
    required this.id,
    required this.name,
    String? address1,
    String? address2,
    String? city,
    String? stateProv,
    String? country,
    String? postalCode,
    String? plus4,
    String? website,
    String? sponsor,
    String? eventName,
    String? time,
    String? genericSchedule,
    String? price,
    String? notes,
    String? contact1Name,
    String? contact1Phone,
    String? contact1Email,
    String? contact2Name,
    String? contact2Phone,
    String? contact2Email,
    this.provenance,
  }) : address1 = _normalize(address1),
       address2 = _normalize(address2),
       city = _normalize(city),
       stateProv = _normalize(stateProv),
       country = _normalize(country),
       postalCode = _normalize(postalCode),
       plus4 = _normalize(plus4),
       website = _normalize(website),
       sponsor = _normalize(sponsor),
       eventName = _normalize(eventName),
       time = _normalize(time),
       genericSchedule = _normalize(genericSchedule),
       price = _normalize(price),
       notes = _normalize(notes),
       contact1Name = _normalize(contact1Name),
       contact1Phone = _normalize(contact1Phone),
       contact1Email = _normalize(contact1Email),
       contact2Name = _normalize(contact2Name),
       contact2Phone = _normalize(contact2Phone),
       contact2Email = _normalize(contact2Email) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must be non-empty');
    }
  }

  final String id;

  /// The venue's name (CC `Venue`); required and non-empty.
  final String name;

  /// First address line; nullable.
  final String? address1;

  /// Second address line (suite/room/etc.); nullable.
  final String? address2;

  /// City/town; nullable.
  final String? city;

  /// State or province; nullable.
  final String? stateProv;

  /// Country; nullable.
  final String? country;

  /// Postal/ZIP code; nullable. Kept separate from [plus4] (CC parity).
  final String? postalCode;

  /// The US ZIP+4 add-on; nullable. Separate field from [postalCode].
  final String? plus4;

  /// Canonical URL for the venue, if any; nullable.
  final String? website;

  /// Hosting organization/sponsor; nullable.
  final String? sponsor;

  /// The recurring event's name held here (CC user field); nullable.
  final String? eventName;

  /// Free-text time-of-day for the event (CC user field); nullable.
  final String? time;

  /// Free-text recurrence description (e.g. "2nd Saturdays"); nullable.
  final String? genericSchedule;

  /// Free-text admission price; nullable.
  final String? price;

  /// Freeform notes about the venue; nullable.
  final String? notes;

  /// Primary contact's name; nullable.
  final String? contact1Name;

  /// Primary contact's phone; nullable.
  final String? contact1Phone;

  /// Primary contact's email; nullable.
  final String? contact1Email;

  /// Secondary contact's name; nullable.
  final String? contact2Name;

  /// Secondary contact's phone; nullable.
  final String? contact2Phone;

  /// Secondary contact's email; nullable.
  final String? contact2Email;

  /// Import provenance: where this venue record came from, under what
  /// `(source, externalId)` pair. Null for user-created venues and for venues
  /// imported before schema v26. When non-null, the importer can recognise a
  /// previously-imported venue by its exact provenance key instead of relying
  /// on the content fingerprint, enabling dedupe for shared bundles where the
  /// postal address has been redacted.
  final Provenance? provenance;

  /// A one-line human label for the venue — the app-side equivalent of CC's
  /// stored `VenueDisplay_c`, but computed (never persisted) so it always
  /// reflects the current fields. Concatenates [name], [address1], [city],
  /// [stateProv] and [country] (in that order), skipping any that are null,
  /// joined by ", ". Since [name] is always present, this is never empty.
  ///
  /// **Not safe on an export path as-is.** Four of those five fields
  /// ([address1], [city], [stateProv], [country]) are classified
  /// `EgressClass.deviceLocal` in the privacy registry, so this label carries
  /// data that must not leave the device — reading it straight off a stored
  /// record and putting the result in a shared file, printed page or clipboard
  /// is a leak, and one that happened (issue #853). On-screen use is fine; that
  /// is what the label is for. Any export must pass the venue through
  /// `sanitizeVenueForShare` **first**, after which this collapses to [name].
  String get displayName =>
      [name, address1, city, stateProv, country].whereType<String>().join(', ');

  /// Normalizes a freeform optional string: trims and treats empty/whitespace
  /// as `null`, so "unset" is a single canonical value (mirrors the
  /// [PublishedSource]/[Choreographer] contact-field precedent).
  static String? _normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Returns a copy with the given fields replaced. The `clear*` flags reset
  /// the respective nullable field to `null` and **win** over any value passed
  /// for the same field (precedent: [PublishedSource.copyWith]).
  Venue copyWith({
    String? name,
    String? address1,
    bool clearAddress1 = false,
    String? address2,
    bool clearAddress2 = false,
    String? city,
    bool clearCity = false,
    String? stateProv,
    bool clearStateProv = false,
    String? country,
    bool clearCountry = false,
    String? postalCode,
    bool clearPostalCode = false,
    String? plus4,
    bool clearPlus4 = false,
    String? website,
    bool clearWebsite = false,
    String? sponsor,
    bool clearSponsor = false,
    String? eventName,
    bool clearEventName = false,
    String? time,
    bool clearTime = false,
    String? genericSchedule,
    bool clearGenericSchedule = false,
    String? price,
    bool clearPrice = false,
    String? notes,
    bool clearNotes = false,
    String? contact1Name,
    bool clearContact1Name = false,
    String? contact1Phone,
    bool clearContact1Phone = false,
    String? contact1Email,
    bool clearContact1Email = false,
    String? contact2Name,
    bool clearContact2Name = false,
    String? contact2Phone,
    bool clearContact2Phone = false,
    String? contact2Email,
    bool clearContact2Email = false,
    Provenance? provenance,
    bool clearProvenance = false,
  }) => Venue(
    id: id,
    name: name ?? this.name,
    address1: clearAddress1 ? null : (address1 ?? this.address1),
    address2: clearAddress2 ? null : (address2 ?? this.address2),
    city: clearCity ? null : (city ?? this.city),
    stateProv: clearStateProv ? null : (stateProv ?? this.stateProv),
    country: clearCountry ? null : (country ?? this.country),
    postalCode: clearPostalCode ? null : (postalCode ?? this.postalCode),
    plus4: clearPlus4 ? null : (plus4 ?? this.plus4),
    website: clearWebsite ? null : (website ?? this.website),
    sponsor: clearSponsor ? null : (sponsor ?? this.sponsor),
    eventName: clearEventName ? null : (eventName ?? this.eventName),
    time: clearTime ? null : (time ?? this.time),
    genericSchedule: clearGenericSchedule
        ? null
        : (genericSchedule ?? this.genericSchedule),
    price: clearPrice ? null : (price ?? this.price),
    notes: clearNotes ? null : (notes ?? this.notes),
    contact1Name: clearContact1Name
        ? null
        : (contact1Name ?? this.contact1Name),
    contact1Phone: clearContact1Phone
        ? null
        : (contact1Phone ?? this.contact1Phone),
    contact1Email: clearContact1Email
        ? null
        : (contact1Email ?? this.contact1Email),
    contact2Name: clearContact2Name
        ? null
        : (contact2Name ?? this.contact2Name),
    contact2Phone: clearContact2Phone
        ? null
        : (contact2Phone ?? this.contact2Phone),
    contact2Email: clearContact2Email
        ? null
        : (contact2Email ?? this.contact2Email),
    provenance: clearProvenance ? null : (provenance ?? this.provenance),
  );

  @override
  bool operator ==(Object other) =>
      other is Venue &&
      other.id == id &&
      other.name == name &&
      other.address1 == address1 &&
      other.address2 == address2 &&
      other.city == city &&
      other.stateProv == stateProv &&
      other.country == country &&
      other.postalCode == postalCode &&
      other.plus4 == plus4 &&
      other.website == website &&
      other.sponsor == sponsor &&
      other.eventName == eventName &&
      other.time == time &&
      other.genericSchedule == genericSchedule &&
      other.price == price &&
      other.notes == notes &&
      other.contact1Name == contact1Name &&
      other.contact1Phone == contact1Phone &&
      other.contact1Email == contact1Email &&
      other.contact2Name == contact2Name &&
      other.contact2Phone == contact2Phone &&
      other.contact2Email == contact2Email;

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    address1,
    address2,
    city,
    stateProv,
    country,
    postalCode,
    plus4,
    website,
    sponsor,
    eventName,
    time,
    genericSchedule,
    price,
    notes,
    contact1Name,
    contact1Phone,
    contact1Email,
    contact2Name,
    contact2Phone,
    contact2Email,
  ]);
}
