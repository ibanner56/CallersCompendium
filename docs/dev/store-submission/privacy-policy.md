# Privacy Policy (mirror of the published page)

> **Published.** The live, authoritative version of this policy is the page at
> <https://ibanner56.github.io/CallersCompendium/privacy/>, served from
> `site/privacy/index.html` (part of the existing GitHub Pages site) — that is
> the copy the stores link to. Use that URL in both App Store Connect and the
> Play Console; both stores require a working privacy-policy link before you can
> distribute, even for beta/testing tracks. This markdown is a human-readable
> mirror of that page for review and history. There is no build step that
> generates one from the other, so **any policy change must be made to both
> `site/privacy/index.html` and this file, keeping their wording and the
> effective date in sync.** This is not legal advice.

---

## Privacy Policy for Caller's Compendium

**Effective date:** September 3, 2026

Caller's Compendium ("the app") is a free, open-source, local-first application
for dance callers, developed by Isaac Banner ("we," "us"). This policy explains
what data the app does and does not handle. The short version: **the app has no
accounts or tracking and keeps your collection on your device.** Optional Device
Sync can also store selected shareable content on a configured sync service for
app functionality; it is not linked to your identity.

### 1. Data we collect

Device Sync is optional. When you enable it, the app transfers selected
shareable content — including choreography, programs, tags, and shareable
settings — to a configured sync service for app functionality. This is
**Other User Content** and is not linked to your identity.

**Names of other people in your collection.** Your collection records the people
credited in the dances and programs you call: choreographers, the authors of
published sources, and the callers and bands billed on a program. Those names
are personal data about people who do not use the app. We carry them because
attribution is the reason the field exists — a dance without its choreographer
is not usable, and the credit is already published wherever the dance or event
is published.

This follows established practice for published authorship. Library catalogues
treat an author's name as personal data about that author and justify publishing
it, rather than treating publication as making the data non-personal. See, for
example, the [National Library of Scotland's privacy notice for catalogue
records](https://www.nls.uk/privacy/catalogue-records/), which records
name-authority data as personal data processed in the public interest, with a
right of objection and a disclosed international transfer to the Library of
Congress.

We do not collect account or identity information, sell information, or use
content for advertising or tracking. The app has:

- **No user accounts and no sign-in.**
- **No analytics, tracking, or telemetry.**
- **No advertising and no advertising identifiers.**
- **No third-party tracking SDKs.**

### 2. Where your data lives

Everything you create in the app — your dance collection, programs, custom fields,
dialects, themes, and settings — is stored **locally on your device**. It is under
your control. If you enable Device Sync, selected shareable content is also
stored by the sync service you configure so it can be synchronized.

The service operator can read the plaintext synchronized store if they choose to.
A break-glass access path exists for abuse investigations, and every use is
logged. The derived sync storage path in that log becomes eligible for nulling
after 30 days of access and is nulled by the next hourly sweep; after that it
becomes a timestamp-only aggregate row. Ordinary diagnostic events that contain
store-derived metadata become eligible for removal after 30 days and are
removed by the next hourly sweep. They never include request bodies, record
content, or bearer credentials.

Device Sync does not transfer structured venue street address, city, region,
country, postal or ZIP code, or contact name, phone, or email fields. **Freeform
venue notes** are shareable, however, and can contain names or phone numbers;
avoid putting private contact information there.

Some fields are never sent to a sync service or included in shared content. A
choreographer's email address, location, and deceased flag, and a venue's street
address, city, state or region, postal code and country are always excluded.
Venue contact names, phone numbers and email addresses are also excluded from
shared content unless you explicitly choose to include them. All of these fields
are still included in a complete backup file, which stays under your control.
Notes fields are shared, so a contact detail typed into a note travels with the
note.

You can export a complete backup to a single file (a plain, human-readable JSON
file carrying a built-in SHA-256 integrity checksum that catches accidental
corruption — not encryption, and, because the checksum travels inside the file,
not a safeguard against deliberate tampering) and restore it on another device. Those backup files
are created and kept by you; we never receive them.

### 3. Network connections the app makes

The app works fully offline when Device Sync is disabled. When it contacts the
internet, it does so only in the cases and for the purposes described below:

- **Published collections you choose to browse or import.** The app fetches the
  catalog and archives of developer-published dance collections so you can review
  and import them locally. It does not upload your collection to obtain them.
- **Imports you initiate.** When you choose to import dances or programs from an
  online source — such as The Caller's Box, ContraDB, or a link/ID you provide —
  the app requests that content directly from that third-party service so it can
  be added to your local collection. Your use of those services is subject to
  their own terms and privacy practices. The app requests only the resource you
  ask for; it does not send them your collection or personal data.
- **Optional update check.** The app can check whether a newer version is
  available by requesting a small, public update-information file. This check is
  **off by default** and only runs if you turn it on in Settings. It downloads
  version information only; it does not send us any information about you or your
  data.
- **Optional Device Sync.** When you enable it, the app contacts the configured
  sync service to synchronize selected shareable content for app functionality.

As with any internet request, a service the app contacts can see your device's IP
address and standard request information, as is technically necessary to deliver
a response. We do not use that information to identify or track you.

### 4. Permissions

The app requests only network (internet) access, used for the purposes in
Section 3. It does **not** request access to your camera, microphone, location,
contacts, photos, or similar sensitive device data.

### 5. Sharing between your own devices

If you share a program or dances with another person or device (for example via
AirDrop, "Open with," or a share sheet), that transfer happens directly through
the sharing mechanism you chose on your device or platform. It does not pass
through us, and there is no public feed, messaging, or social component in the
app.

### 6. Children's privacy

The app is a utility for dance callers and is not directed to children. We do not
knowingly collect personal information from children.

### 7. Your control over your data

Your local data remains under your control:

- Delete individual items in the app, or uninstall the app to remove its local
  data from your device.
- Export a backup at any time to keep or move your data yourself.
- Disable Device Sync when you no longer want the app to synchronize selected
  content.

When Device Sync is enabled, the configured sync service holds the selected
content for as long as the store receives authenticated activity, then reaps it
after 30 days of disuse. Unreferenced uploads are protected for 24 hours while
they can still be published, but deleting the store requests immediate removal.
If physical removal fails, a durable cleanup record retries it on later requests
and hourly sweeps.
The access log's derived sync storage path becomes eligible for nulling 30 days
after access and is nulled by the next hourly sweep; it retains a timestamp-only
aggregate row after that. Ordinary diagnostic events become eligible for
removal after 30 days and are removed by the next hourly sweep. They contain no
content or bearer credentials.

### 8. Open source

Caller's Compendium is open source under the AGPL-3.0 license. You can inspect
exactly what the app does — including every network request — in the source code
at <https://github.com/ibanner56/CallersCompendium>.

### 9. Changes to this policy

If this policy changes, we will update the effective date above and post the new
version at this URL. Material changes will also be noted in the app's release
notes.

### 10. Contact

Questions about this policy or the app's privacy practices:
**compendium@contra.dance** — or open an issue at
<https://github.com/ibanner56/CallersCompendium/issues>.

Questions or objections about names in a collection should be directed to the
person or organization controlling that collection. Questions about handling by
a configured sync service should be directed to that service's operator.
