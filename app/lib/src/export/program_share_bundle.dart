import 'package:compendium_core/compendium_core.dart';

import '../utils/safe_name.dart';
import 'share_sanitization.dart';

/// Builds a self-contained "share this program + its dances" bundle (ROADMAP
/// §4.3, issue #298 — AirDrop/OS share-sheet sharing, send side).
///
/// The bundle is **not a new format**: it is the canonical [CompendiumArchive]
/// exchange JSON (`docs/design/imports.md` §"Generic JSON (6.6)"). Here the
/// archive carries a single [program] plus the full definitions of every dance
/// the program references, so the receiving device gets a self-contained
/// evening with nothing else attached.
///
/// On the receive side the import screen recognizes an archive that carries
/// programs, decodes it with `decodeArchive`, and commits it through
/// `CompendiumArchiveImporter` — dances, choreographers, venue **and** the
/// program itself. That holds for a file opened from the OS share sheet and,
/// since #874, for one picked manually through Import too. (A JSON file that
/// is not an archive still routes to the dance-only `GenericJsonAdapter`.)
///
/// [danceFor] resolves a slot's `danceId` to its full [Dance]; a referenced id
/// that can't be resolved is skipped (best-effort, never fatal — mirrors the
/// codec's partial-failure tolerance). Repeated `danceId`s are de-duplicated so
/// each dance appears once. Slot order and note-only slots are preserved by the
/// program itself (its `slots` carry their own `text`), so nothing extra is
/// needed for them here.
///
/// [choreographerFor] resolves an author id (from a bundled dance's `authorIds`)
/// to its full [Choreographer], so author attribution survives the round-trip:
/// the receive-side importer reads incoming author *names* from the bundle's own
/// `CompendiumArchive.choreographers` (a receiver cannot resolve the sender's
/// author ids). Only the choreographers actually referenced by the bundled
/// dances are included (deduped by id) — the bundle stays minimal and never
/// leaks unrelated authors. (The emitted archive is canonicalized by
/// [encodeArchive], which sorts entities by id, so the serialized order is by
/// id rather than reference order — only the set of included choreographers is
/// significant.) An id that can't be resolved is skipped (best-effort, never
/// fatal — mirrors [danceFor]).
///
/// Privacy (issue #412, and the [Choreographer] model's contract): a
/// choreographer's `email`/`location` are private contact data that MUST NOT
/// leave the device in a shareable export. Each included choreographer is
/// therefore sanitized here — `email`/`location` are cleared — before it is
/// embedded, so sharing carries only public attribution (name/website/notes).
///
/// [venueFor] resolves the program's `venueId` (schema v14) to its full
/// [Venue], so a shared program keeps its venue link (mirrors [danceFor]/
/// [choreographerFor]). The referenced venue is gathered into
/// `CompendiumArchive.venues` best-effort: a `null` `venueId`, or an id that
/// resolves to no venue, is simply omitted (never fatal — the receiver's
/// importer nulls a dangling `venueId`). The gathered venue is deduped by id.
///
/// Privacy (issue #515): a venue's six contact-person PII fields
/// (`contact1Name/Phone/Email`, `contact2Name/Phone/Email`) are personal
/// details that are OMIT-BY-DEFAULT. Every gathered venue is routed through
/// [sanitizeVenueForShare]; only the [VenueContactField]s in
/// [includeVenueContact] survive. This set is empty by default (full
/// redaction) and is populated **only** from an explicit, opt-in pre-share
/// consent dialog in the UI layer — there is no path that embeds an
/// unsanitized venue. All venue-descriptive fields (name/address/schedule/…)
/// are kept, matching the choreographer precedent.
///
/// [now] stamps the archive's `exportedAt`; it defaults to the current time and
/// is injectable for deterministic tests.
///
/// Cross-import venue dedupe (issue #456) does **not** apply to bundles this
/// function produces, since issue #853. `CompendiumArchiveImporter` matches an
/// incoming venue against the receiver's existing ones by content fingerprint
/// (`venueFingerprint` / `VenueFingerprintIndex`), and that key needs the venue's
/// name **plus a locating field** (`address1` or `city`). The address block is
/// classified `EgressClass.deviceLocal`, so [sanitizeVenueForShare] clears it
/// above — which leaves no locating field, no fingerprint, and no dedupe.
///
/// **Consequence: a recipient who imports the same bundle twice, or two bundles
/// naming the same hall, gets a separate venue record each time.** They are
/// name-only records, so they are easy to spot and merge by hand, and no data
/// is lost or overwritten — but they do accumulate.
///
/// This is an accepted tradeoff of the privacy fix, not an oversight: it is
/// pinned by `app/test/export/share_venue_dedupe_seam_test.dart` and explained
/// at [venueFingerprint]. Dedupe still works for venues that reach the importer
/// with their address intact (`.USR` import, backup restore, local venues).
String buildProgramShareBundle(
  Program program, {
  required Dance? Function(String danceId) danceFor,
  required Choreographer? Function(String id) choreographerFor,
  required Venue? Function(String venueId) venueFor,
  Set<VenueContactField> includeVenueContact = const {},
  DateTime? now,
}) {
  final dances = <Dance>[];
  final seen = <String>{};
  for (final slot in program.slots) {
    final danceId = slot.danceId;
    if (danceId == null || !seen.add(danceId)) continue;
    final dance = danceFor(danceId);
    if (dance != null) dances.add(dance);
  }

  final choreographers = <Choreographer>[];
  final seenAuthors = <String>{};
  for (final dance in dances) {
    for (final authorId in dance.authorIds) {
      if (!seenAuthors.add(authorId)) continue;
      final choreographer = choreographerFor(authorId);
      if (choreographer == null) continue;
      // Strip private contact fields before the record leaves the device.
      choreographers.add(sanitizeChoreographerForShare(choreographer));
    }
  }

  // Gather the program's referenced venue (best-effort, deduped by id). A null
  // or unresolvable venueId is simply omitted. Contact PII is redacted here —
  // omit-by-default unless the caller explicitly opted fields into
  // includeVenueContact — so no unsanitized venue is ever embedded.
  final venues = <Venue>[];
  final venueId = program.venueId;
  if (venueId != null) {
    final venue = venueFor(venueId);
    if (venue != null) {
      venues.add(sanitizeVenueForShare(venue, include: includeVenueContact));
    }
  }

  return encodeArchive(
    CompendiumArchive(
      exportedAt: (now ?? DateTime.now()).toUtc(),
      programs: [program],
      dances: dances,
      choreographers: choreographers,
      venues: venues,
    ),
    mode: ArchiveSerializationMode.share,
  );
}

/// A filesystem-safe file name for a program share bundle, derived from the
/// program [title].
///
/// The title is sanitized to `[A-Za-z0-9._-]` (every other character — path
/// separators, spaces, control characters — becomes `_`) so it is safe to use
/// as a temp-file name and share-sheet file name without path traversal or
/// odd-character surprises. An empty/all-illegal title falls back to a stable
/// default.
///
/// The `.ccshare` extension (issue #298, PR 2) makes Caller's Compendium a
/// first-class handler for received share bundles: it maps to the app's own
/// exported UTI (`org.callerscompendium.compendiumApp.share`) so an
/// AirDrop'd/"Open with…" file routes back into the app instead of being treated
/// as a generic `.json`. The payload is still the canonical
/// [CompendiumArchive] JSON, so the importer also keeps accepting plain `.json`
/// for backward compatibility.
const String programShareBundleExtension = 'ccshare';

/// The plain-JSON extension for the same bundle payload (issue #853).
///
/// A `.json` file carries **byte-identical** content to a `.ccshare` one — both
/// are [buildProgramShareBundle]'s canonical [CompendiumArchive] JSON. Only the
/// extension differs, and it differs deliberately: `.ccshare` binds the file to
/// the app's exported UTI so a received file auto-opens here, whereas `.json`
/// stays a generic document. That is the point of offering it — a recipient
/// without the app installed, an email attachment, or a caller who just wants
/// to read or diff the file gets something their system will open.
///
/// Because it is the same payload, it is read back by the same path a
/// `.ccshare` file takes: the import screen detects a [CompendiumArchive]
/// carrying programs, decodes it with `decodeArchive`, and commits it through
/// `CompendiumArchiveImporter` — with no relaxed validation. (A `.json` file
/// that is *not* an archive still falls through to the dance-only
/// `GenericJsonAdapter`, unchanged.)
const String programShareJsonExtension = 'json';

/// A filesystem-safe file name for a program share bundle. See the library-level
/// notes above for the extension rationale.
///
/// [extension] selects between the native [programShareBundleExtension] and the
/// plain [programShareJsonExtension]. The base name is derived identically
/// either way, so a crafted program title cannot construct a different path
/// through the `.json` action than it could through the `.ccshare` one.
String programShareBundleFileName(
  String title, {
  String extension = programShareBundleExtension,
}) {
  final sanitized = replaceUnsafeNameChars(title.trim());
  // Fall back when the title has no alphanumeric content (empty, all
  // whitespace, or only illegal/punctuation characters) so the file always has
  // a meaningful, path-safe name.
  final hasContent = sanitized.contains(RegExp(r'[A-Za-z0-9]'));
  final base = hasContent ? sanitized : 'program';
  return '$base.$extension';
}
