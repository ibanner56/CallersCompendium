# Store listing copy & form answers (drafts)

Everything you paste into App Store Connect and the Play Console, drafted for
**Caller's Compendium** and ready to review/tweak. Character limits are noted so
you don't overflow a field. Wording is deliberately accurate about what the
app does and does **not** do (no accounts, no analytics; content leaves the
device only through optional, off-by-default Device Sync) so it survives review.
Device Sync ships in every build, so the data-practice sections below declare
its transfer; the live store answers are updated by the maintainer from this
file.

> These are **drafts for your review**, not final marketing. Adjust voice to
> taste; keep the factual claims (offline, no telemetry, free, open-source) intact
> because the store forms and reviewers are checked against them.

---

## Names & short text

| Field | Store | Limit | Draft |
|-------|-------|-------|-------|
| App name | Both | 30 | `Caller's Compendium` |
| Subtitle | Apple | 30 | `Organize & call contra dances` |
| Short description | Play | 80 | `A local-first organizer for contra callers—catalog, program, and perform.` |
| Promotional text | Apple | 170 | `An open-source dance organizer for Contra, ECD, and Squares callers. Catalog your dances, build set lists, and call from a large-print stage view—completely free.` |

`Caller's Compendium` = 19 chars. `The caller's notebook` = 21. The short
description above is 73 chars. Verify counts in the console before saving.

## Keywords (Apple only)

Apple keywords are a single 100-character comma-separated field. **Do not** repeat
words already in the app name/subtitle (they're indexed automatically). No spaces
between terms (spaces waste characters):

```
contra,dance,caller,calling,square,ecd,program,setlist,choreography,folk,barn,perform,swing
```

(91 characters — trim a term if the console counts it over 100.)

Google Play has **no** keyword field; Play ranks on the descriptions, so the full
description below front-loads the important terms naturally.

## Full description (both stores)

Apple "Description" and Play "Full description" both allow up to 4000 chars. The
text below is ~1.9k chars and works verbatim for both. (Apple doesn't render
Markdown; Play renders minimal formatting — the plain bullets below are fine for
both.)

```
Caller's Compendium is a free, open-source, local-first organizer for contra
dance callers. Catalog your dances, build programs for your gigs, and call from a
large-print, stage-ready view — all on your own device, fully offline, with
nothing to sign in to. Nothing leaves your phone or tablet unless you turn on
optional Device Sync.

Built by a caller, for callers.

COLLECTION
- Catalog dances with structured, searchable figures.
- Search by title, author, type, formation, level, or even the figures
  themselves ("chain then swing in B2") — plus your own custom fields.

PROGRAMS
- Build set lists for an event, with alternates and free-text slots.
- See the shape of your evening with a programming matrix computed from the
  choreography itself.
- Build a program from a plain title list or straight from a ContraDB event.
- Duplicate a good set to reuse it; print or share a program with all its dances.

PERFORM MODE
- A large-print, high-contrast, stage-ready calling view.
- Keeps the screen awake, with edge-reachable navigation for a dim hall.
- Tap-tempo visual metronome and screen-reader-friendly figure rendering.

YOUR TERMS (DIALECT)
- Role-neutral by default (Larks/Robins, with Leads/Follows ready to pick).
- Rename roles, substitute moves and dancer terms, flag discouraged terms —
  applied over a standard vocabulary so search always works and data stays
  portable. Create and quick-switch named dialects per gig.

IMPORTS
- Bring dances in from The Caller's Box, ContraDB, and Caller's Companion, or from
  a Caller's Compendium file — through a review-and-commit queue you can undo.

YOUR DATA STAYS YOURS
- Local-first: your collection lives on your device and the app works fully
  offline. No account, no telemetry, nothing collected automatically.
- Device Sync is disabled by default and opt-in only. Once you turn it on and
  connect a store, it syncs automatically; the store is anonymous and can be shared
  across your devices or with other callers using the app.
- Export a full backup to a single human-readable file (with a built-in
  integrity checksum) and restore it anywhere.

Accessibility is a first-class goal: large type, high contrast, low-vision fonts,
and screen-reader support throughout.

Free and open source (AGPL-3.0). Source, issues, and the beta program:
https://github.com/ibanner56/CallersCompendium
```

## Categories

| Store | Primary | Secondary |
|-------|---------|-----------|
| Apple App Store | Productivity | Reference |
| Google Play | Productivity | (Play uses one category; "Tools" is an acceptable alt) |

## "What's new" / release notes (beta)

Reuse per release; keep it tester-focused. Source of truth is
[`app/CHANGELOG.md`](../../../app/CHANGELOG.md).

```
Thanks for testing Caller's Compendium! This build adds new Perform and analysis
tools, richer ContraDB and browser-share importing, and quality-of-life polish
across browsing, editing, and sharing. Everything stays on your device unless
you turn on optional Device Sync — no account, no telemetry. Please send feedback from within TestFlight / Play, or on
GitHub. Tell us your device, the version, and what you were doing.
```

## TestFlight "Test Information" (Apple, external testing)

- **Beta app description:**
  ```
  Caller's Compendium is a free, offline organizer for contra dance callers:
  catalog dances, build programs, and call from a large-print Perform mode. This
  beta is for real callers to use it at real gigs and tell us what breaks. No
  account or sign-in; everything works offline. Optional: try an import (paste a
  ContraDB program link) to exercise a network feature.
  ```
- **Feedback email:** compendium@contra.dance
- **Marketing URL:** https://ibanner56.github.io/CallersCompendium/
- **Privacy Policy URL:** https://ibanner56.github.io/CallersCompendium/privacy/
- **What to test:** Collection search, building a Program and viewing the matrix,
  Perform mode at a real dance, switching Dialect, and importing from a source.

---

## App Privacy (Apple)

Set in App Store Connect → App Privacy. Device Sync can transfer content, so
**"Data Not Collected" is not the right answer** for a Sync-capable build.
Expected result: **Data collected, not linked to you, not used for tracking.**

- [ ] **"Do you or your third-party partners collect data from this app?"** →
  **Yes.**
- [ ] **Data type:** **User Content → Other User Content.** This is the
  choreography, programs, tags and shareable settings that optional Device Sync
  transfers to the configured sync service (default endpoint
  `https://athenaeum.callerscompendium.com/`, run by the project). Mirrors
  `site/privacy/index.html` §1.
  - **Purpose:** App Functionality only.
  - **Linked to the user's identity?** **No** (no account; anonymous sync store).
  - **Used for tracking?** **No.**
  - Optional and **off by default**: nothing is sent until the user turns on
    Device Sync and connects a store. Once connected, passes run automatically
    after local changes and at app start (Wi-Fi only by default).
- Rationale to keep on file: the app is local-first. Apart from Device Sync it
  makes only **user-initiated** network requests (imports the user chooses to
  run) and an **opt-in, off-by-default** update check; those are not used to
  collect data about the user. There is no analytics/tracking SDK and no
  advertising identifier is used.
- Note: a build with Device Sync compiled out would answer "Data Not Collected".
  No such build exists today; do not use that answer for the shipped app.
- [ ] **Tracking:** the app does **not** track users across apps/sites → no
  `NSUserTrackingUsageDescription`, no ATT prompt.

> Honesty check: imports and the update check contact third-party or public
> servers, and Device Sync contacts the sync service. Keep the rationale above
> handy in case a reviewer asks; the declared data type is only what Device Sync
> sends.

## Data safety (Google Play)

Set in Play Console → App content → Data safety. Device Sync can transfer
content, so **"No data collected" / "No data shared" is not the right answer**
for a Sync-capable build.

- [ ] **Does your app collect or share any of the required user data types?** →
  **Yes.**
- [ ] **Data type:** **App activity → Other user-generated content** (the
  choreography, programs, tags and shareable settings that optional Device Sync
  transfers; mirrors `site/privacy/index.html` §1).
  - **Collected or shared?** Collected (sent to the project's sync service by
    default). Not shared with third parties.
  - **Optional?** Yes — users can choose whether to enable Device Sync, which is
    **off by default**.
  - **Purpose:** App functionality.
  - **Linked to identity?** No account or identity is involved.
- [ ] **Is all user data encrypted in transit?** → Yes. The default sync
  endpoint and imports use HTTPS; a user-entered sync endpoint must be HTTPS
  except plain-HTTP `localhost`/`127.0.0.1`, which never leaves the device.
- [ ] **Do you provide a way for users to request data deletion?** → Yes:
  disabling Device Sync and deleting the sync store requests removal from the
  service (see `site/privacy/index.html` §7); all local data is under the user's
  control via backup/restore and in-app delete.
- Rationale to keep on file (same as Apple): local-first, no analytics, no ads, no
  accounts; imports and the opt-in update check do not send personal user data to
  the developer. A build with Device Sync compiled out would answer "No data
  collected"; none exists today.
- [ ] **Advertising ID:** declare the app does **not** use an advertising ID, and
  confirm no dependency adds the `AD_ID` permission.

## Age & content rating

Answer these truthfully in **both** questionnaires (Apple's own; Google's IARC).
Expected outcome: **Apple 4+ / Google "Everyone."**

| Question theme | Answer |
|----------------|--------|
| Violence (cartoon, fantasy, realistic) | None |
| Sexual content / nudity | None |
| Profanity / crude humor | None |
| Alcohol, tobacco, drugs | None |
| Gambling / contests | None |
| Horror / fear themes | None |
| Mature/suggestive themes | None |
| **Unrestricted web access / embedded browser** | **No** — the app only fetches specific import URLs the user explicitly provides (or a chosen source's endpoint), over HTTPS, and does not render arbitrary web pages; it is **not** a general web browser. Requests pass an SSRF guard that requires HTTPS and blocks localhost/LAN/reserved addresses. The Caller's Box and ContraDB import sources are further restricted to a fixed host allowlist (`ibiblio.org`/`www.ibiblio.org` under the `/contradance/thecallersbox/` mirror prefix for Caller's Box; `contradb.com`/`www.contradb.com` for ContraDB — #621, #667, #766); only the generic Caller's-Compendium-JSON-file import source still accepts any public DNS host the user supplies, by design, to support a user's own self-hosted JSON export |
| User-generated content shared publicly / social features | No — sharing is device-to-device (AirDrop / files); there is no public feed or messaging |
| Data collection for ads / tracking | None |
| Made primarily for children | No — a utility for adult callers |

## Reviewer notes (both stores)

Paste into Apple's **App Review Information → Notes** / TestFlight **Beta App
Review** notes and Play's **App access** section.

```
Caller's Compendium is an offline organizer/reference for contra dance callers.

- No account or login is required. Every feature is available offline on first
  launch; the app seeds one sample dance ("The Baby Rose") so the collection is
  never empty.
- No special device permissions are requested (no camera, microphone, location,
  contacts, or photos). Permissions are INTERNET and ACCESS_NETWORK_STATE (the
  latter added by the `connectivity_plus` plugin, used to honour the Wi-Fi-only
  sync setting), used for user-initiated imports, browsing or importing published collections, an opt-in (off by
  default) update check, and Device Sync when the user enables it.
- To exercise an import network feature: open Import and paste a ContraDB program
  URL (e.g. https://contradb.com/programs/1) or a Caller's Box dance id, then
  review and commit. Nothing is uploaded — imports only fetch.
- Device Sync is disabled by default. When a user enables it and connects a store,
  the app then syncs automatically, transferring
  configured application settings, choreography, and programming content to an 
  anonymous sync store so the user can share it across devices or with other 
  callers using the app. This data is used only for app functionality, is not 
  linked to the user's identity, and does not require an account.
- The app has no analytics, advertising, or tracking telemetry.
- Free and open source (AGPL-3.0): https://github.com/ibanner56/CallersCompendium
```

## Assets checklist (recap)

| Asset | Apple | Google Play |
|-------|-------|-------------|
| App icon | 1024×1024 (no alpha) | 512×512 (32-bit PNG) |
| Feature graphic | — | 1024×500 (required) |
| Phone screenshots | 6.9" iPhone set | 2–8, 9:16 or 16:9 |
| Tablet screenshots | 13" iPad set (required, we support iPad) | 7" + 10" (recommended) |
| Promo video | Optional (App Preview) | Optional (YouTube URL) |
| Privacy policy URL | Required | Required |
| Support / marketing URL | Required / optional | Required / optional |

Screenshot content to capture (both stores): **Perform mode**, **Collection with
search**, **Programs + matrix**, **Dialect editor**, **Imports review queue**.
