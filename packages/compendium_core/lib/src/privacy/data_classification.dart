/// Data classification for every field the application persists.
///
/// Design: `docs/dev/data-classification.md`. This registry is the **single
/// source of truth**: the developer doc is checked against it, and any code that
/// decides whether a field may leave the device reads [EgressClass] from here
/// rather than carrying a second, drifting allow-list.
///
/// ## Why a registry and not doc comments
///
/// Before this file the privacy boundary was prose: `Choreographer` carried a
/// comment saying its `email`/`location` "MUST NOT be emitted in any shareable
/// export". Nothing enforced it, and nothing could answer the same question for
/// the 22 columns of `venues`. A registry is checkable — see
/// `test/privacy/data_classification_coverage_test.dart`, which fails when a
/// schema column has no entry.
///
/// ## Vocabulary
///
/// Field categories use the **W3C Data Privacy Vocabulary (DPV) v2.3**, pinned.
/// DPV is a W3C Community Group Report published under the W3C Software and
/// Document License 2023, which permits reproducing its definitions with
/// attribution — unlike a paywalled standard, every contributor can read the
/// vocabulary they are being asked to tag against. See the design doc for the
/// full rationale, and for why ISO/IEC 19944-1:2020 was evaluated and rejected.
///
/// DPV term URIs are given relative to two namespaces:
/// - `pd:` — <https://w3id.org/dpv/pd#> (personal data categories)
/// - `dpv:` — <https://w3id.org/dpv#> (core vocabulary)
///
/// Two fields we hold have no DPV equivalent, so they use house terms in a
/// `cc:` namespace ([DpvTerm.deceasedFlag], [DpvTerm.websiteUrl]). DPV
/// explicitly sanctions this: the personal-data extension is published
/// separately so that adopters may use other vocabularies or define their own.
library;

import 'package:meta/meta.dart';

/// A data category, expressed as a W3C DPV v2.3 term where one exists.
///
/// [path] is the term's ancestry **with DPV's top-level bucket omitted** —
/// `Tracking` above `Contact`, and `External` above `Identifying`, are
/// container names that mislead a reader of our docs more than they inform
/// (an app whose headline promise is "no tracking" should not print a table
/// filing a venue's city under `Tracking`). The leaf term and its meaningful
/// ancestors are kept verbatim, so the mapping back to DPV stays exact.
enum DpvTerm {
  /// A person's name. DPV: `External → Identifying → Name`.
  name('pd:Name', ['Identifying', 'Name']),

  /// An email address. DPV: `Tracking → Contact → EmailAddress`.
  emailAddress('pd:EmailAddress', ['Contact', 'EmailAddress']),

  /// A telephone number. DPV: `Tracking → Contact → TelephoneNumber`.
  telephoneNumber('pd:TelephoneNumber', ['Contact', 'TelephoneNumber']),

  /// A physical address, undecomposed. DPV places this under two parents:
  /// `Tracking → Contact → PhysicalAddress` and
  /// `Tracking → Location → PhysicalAddress`. [path] follows the `Contact`
  /// branch, which is how the address block is used here.
  physicalAddress('pd:PhysicalAddress', ['Contact', 'PhysicalAddress']),

  /// A street line. DPV: `… → PhysicalAddress → Street`.
  street('pd:Street', ['Contact', 'PhysicalAddress', 'Street']),

  /// A city. DPV: `… → PhysicalAddress → City`.
  city('pd:City', ['Contact', 'PhysicalAddress', 'City']),

  /// A state, province or region. DPV: `… → PhysicalAddress → Region`.
  region('pd:Region', ['Contact', 'PhysicalAddress', 'Region']),

  /// A postal code. DPV: `… → PhysicalAddress → PostalCode`.
  postalCode('pd:PostalCode', ['Contact', 'PhysicalAddress', 'PostalCode']),

  /// A freeform locality — DPV defines this as "city, village, town, portion of
  /// a city as a location", which is exactly the shape of a hand-typed
  /// "Portland, OR". DPV: `… → PhysicalAddress → Locality`.
  locality('pd:Locality', ['Contact', 'PhysicalAddress', 'Locality']),

  /// A country. DPV: `Tracking → Location → Country`.
  country('pd:Country', ['Location', 'Country']),

  /// Personal data that does not decompose into a narrower term above — used
  /// for freeform fields a user may fill with anything, including details about
  /// a person.
  unclassifiedPersonal('dpv:PersonalData', ['PersonalData']),

  /// Data that is not about an identifiable person: dance choreography,
  /// structural fields, app configuration.
  nonPersonal('dpv:NonPersonalData', ['NonPersonalData']),

  /// **House term.** Whether a person is deceased. DPV v2.3 has no equivalent
  /// (verified against all 235 `pd:` terms). Ordinary personal data under GDPR
  /// Art. 4(1) rather than an Art. 9 special category, but about a person who
  /// cannot exercise any rights over it.
  deceasedFlag('cc:DeceasedFlag', ['DeceasedFlag']),

  /// **House term.** A website URL. DPV v2.3 has no equivalent (verified
  /// against all 235 `pd:` terms). Names an organisation's public page far more
  /// often than an individual's.
  websiteUrl('cc:WebsiteUrl', ['WebsiteUrl']);

  const DpvTerm(this.uri, this.path);

  /// The term's namespaced URI, e.g. `pd:EmailAddress`.
  final String uri;

  /// The term's ancestry with DPV's top-level bucket omitted; see [DpvTerm].
  final List<String> path;

  /// Whether this term denotes personal data. [websiteUrl] is deliberately
  /// **not** personal: it names an organisation's public page far more often
  /// than an individual's, and the classification that governs it is
  /// [EgressClass], not personhood.
  bool get isPersonalData => this != nonPersonal && this != websiteUrl;

  /// The rendered path used by the developer doc, e.g.
  /// `Contact → PhysicalAddress → City`.
  String get displayPath => path.join(' → ');
}

/// Whose data this is.
///
/// **No published taxonomy supplies this axis**, and it is the one that matters
/// most here: DPV, GDPR and the app-store vocabularies all assume the data
/// subject is the person using the app. In Caller's Compendium the sensitive
/// data is overwhelmingly about people who have never touched it — the contact
/// for a hall, the choreographer of a dance — who cannot consent to a transfer
/// they do not know exists.
enum DataSubject {
  /// Not about a person at all: a dance's title, a figure's beat count.
  none,

  /// About the person using the app.
  appUser,

  /// About someone who does not use the app and has no relationship with it:
  /// venue contacts, choreographers, callers and bands named on a program.
  thirdParty,
}

/// Whether a field may leave the device, and by which route.
///
/// This is the decision every export, share and sync path must consult. It is
/// deliberately about the *route*, not about sensitivity: two fields can both
/// be personal data and still differ here.
enum EgressClass {
  /// May travel by any route the user chooses, including infrastructure the
  /// project operates: file export, share sheet, and device sync.
  shareable,

  /// Must never reach project-operated infrastructure. May leave only by a
  /// transfer the user deliberately initiates between their own devices, or in
  /// a local backup file they control.
  deviceLocal,

  /// Never transmitted by any route, because the value is meaningless or
  /// actively wrong on another device — a window position, a per-device marker,
  /// a per-installation key.
  ///
  /// Distinct from [deviceLocal]: that is withheld because of what it
  /// *contains*, this because of what it *means*. The difference is
  /// behavioural, not editorial — [deviceLocal] data may still move by a direct
  /// device-to-device transfer, while this must not travel by any route at all.
  ///
  /// **"Any route" is absolute, and deliberately so.** An identifier a protocol
  /// must put on the wire in order to function is therefore *not* this class,
  /// however device-specific it is. A draft of Device Sync read "transmitted"
  /// as "transmitted as record content" so that a sync device ID could be
  /// `deviceScoped` and still travel in a request path; that was rejected,
  /// because it makes egress depend on which part of a request a value lands in
  /// rather than on the classification, and because the ruling on #923 turns on
  /// the absolute reading. Such an identifier takes a class of its own —
  /// see `docs/design/sync.md`.
  deviceScoped,

  /// Never transmitted at all. Rebuildable from other fields on arrival, so
  /// sending it would be redundant as well as risky.
  derived,

  /// An opaque identifier the protocol must transmit for routing, but which
  /// must never be adopted from a peer.
  protocolIdentifier,

  /// A bearer credential that authorizes the request carrying it. It may travel
  /// only to the configured endpoint, and must never be retained recoverably.
  accessControlData,
}

/// The classification of one persisted field.
@immutable
class DataClassification {
  const DataClassification({
    required this.term,
    required this.subject,
    required this.egress,
    this.note,
    this.isIdentity = false,
  });

  /// The data category.
  final DpvTerm term;

  /// Whose data this is.
  final DataSubject subject;

  /// Whether, and by what route, the field may leave the device.
  final EgressClass egress;

  /// Whether this field is a record or relational identity and must never be
  /// rewritten as content.
  final bool isIdentity;

  /// Why this classification, where the reason is not self-evident. A reviewer
  /// should not have to guess why a personal-data field is
  /// [EgressClass.shareable].
  final String? note;

  @override
  bool operator ==(Object other) =>
      other is DataClassification &&
      other.term == term &&
      other.subject == subject &&
      other.egress == egress &&
      other.note == note;

  @override
  int get hashCode => Object.hash(term, subject, egress, note);

  @override
  String toString() =>
      'DataClassification(${term.uri}, ${subject.name}, ${egress.name})';
}
