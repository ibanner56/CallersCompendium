import 'package:compendium_core/compendium_core.dart';

import '../utils/safe_name.dart';
import 'share_sanitization.dart';

/// Builds a self-contained "share this program + its dances" bundle (ROADMAP
/// §4.3, issue #298 — AirDrop/OS share-sheet sharing, send side).
///
/// The bundle is **not a new format**: it is the canonical [CompendiumArchive]
/// exchange JSON (`docs/design/imports.md` §"Generic JSON (6.6)"), the same
/// format the manual Import flow's `GenericJsonAdapter` already consumes. Here
/// the archive carries a single [program] plus the full definitions of every
/// dance the program references, so the receiving device can re-import the
/// dances through the existing import path with nothing else attached. The
/// program is carried alongside them for the forthcoming receive-side
/// auto-open (issue #298, PR 2), which will import the program itself; the
/// current manual Import flow imports the dances only.
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
/// Cross-import venue dedupe (issue #456, landed): re-importing a bundle no
/// longer blindly duplicates venue records. `CompendiumArchiveImporter` matches
/// each incoming venue against the venues the receiver already holds by a
/// best-effort content fingerprint (`venueFingerprint` / `VenueFingerprintIndex`,
/// over name + a locating field); on a unique match the incoming venue is dropped
/// and the program is repointed to the existing venue. This is strictly a
/// repoint, never an overwrite — the matched local record is left untouched.
/// Remaining limitation: the match key is the venue's *content*, not a stable
/// provenance/identity key, so it tolerates false splits to never risk a false
/// merge — a weakly-described venue, an ambiguous fingerprint, or a descriptive
/// field edited between imports can still fresh-mint a separate record.
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
/// exported UTI (`org.callerscompendium.compendiumApp.share`, which conforms to
/// `public.json`), so an AirDrop'd/"Open with…" file routes back into the app
/// instead of being treated as a generic `.json`. The payload is still the
/// canonical [CompendiumArchive] JSON, so the importer also keeps accepting
/// plain `.json` for backward compatibility.
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
/// Because it is the same payload, it is read back by the same
/// `GenericJsonAdapter`/`decodeArchive` path, with no relaxed validation.
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
