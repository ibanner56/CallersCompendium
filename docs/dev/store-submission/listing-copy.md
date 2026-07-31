# Store listing copy & form answers (drafts)

Everything you paste into App Store Connect and the Play Console, drafted for
**Caller's Compendium** and ready to review/tweak. Character limits are noted so
you don't overflow a field. Wording is deliberately accurate about what the app
does and does **not** do (no data collection, no accounts) so it survives review.

> These are **drafts for your review**, not final marketing. Adjust voice to
> taste; keep the factual claims (offline, no telemetry, free, open-source) intact
> because the store forms and reviewers are checked against them.

---

## Names & short text

| Field | Store | Limit | Draft |
|-------|-------|-------|-------|
| App name | Both | 30 | `Caller's Compendium` |
| Subtitle | Apple | 30 | `The caller's notebook` *(alt: `Organize & call your dances`)* |
| Short description | Play | 80 | `A local-first organizer for contra callers—catalog, program, and perform.` |
| Promotional text | Apple | 170 | `Catalog your dances, build set lists, and call from a large-print stage view—free, fully offline, and completely private. Your collection never leaves your device.` |

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
nothing to sign in to and no data that ever leaves your phone or tablet.

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
  offline. No account, no cloud, no telemetry, nothing collected automatically.
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
across browsing, editing, and sharing. Everything stays on your device — no
account, no telemetry. Please send feedback from within TestFlight / Play, or on
GitHub. Tell us your device, the version, and what you were doing.
```

## TestFlight "Test Information" (Apple, external testing)

- **Beta app description:**
  ```
  Caller's Compendium is a free, offline organizer for contra dance callers:
  catalog dances, build programs, and call from a large-print Perform mode. This
  beta is for real callers to use it at real gigs and tell us what breaks. No
  account or sign-in; everything works offline. Optional: try an import (paste a
  ContraDB program link) to exercise the one network feature.
  ```
- **Feedback email:** compendium@contra.dance
- **Marketing URL:** https://ibanner56.github.io/CallersCompendium/
- **Privacy Policy URL:** https://ibanner56.github.io/CallersCompendium/privacy/
- **What to test:** Collection search, building a Program and viewing the matrix,
  Perform mode at a real dance, switching Dialect, and importing from a source.

---

## App Privacy (Apple)

Set in App Store Connect → App Privacy. Expected result: **"Data Not Collected."**

- [ ] **"Do you or your third-party partners collect data from this app?"** →
  **No / Data Not Collected.**
- Rationale to keep on file: the app is local-first. It makes only **user-initiated**
  network requests (imports the user chooses to run) and an **opt-in, off-by-default**
  update check. None of this is used to **collect** data about the user, none is
  linked to an identity, there is no analytics/tracking SDK, and no advertising
  identifier is used. That satisfies Apple's definition for "not collected."
- [ ] **Tracking:** the app does **not** track users across apps/sites → no
  `NSUserTrackingUsageDescription`, no ATT prompt.

> Honesty check: because the update check and imports do contact servers, keep the
> one-line rationale above handy in case a reviewer asks. It does not change the
> "Data Not Collected" answer — that answer is about what *you* collect.

## Data safety (Google Play)

Set in Play Console → App content → Data safety. Expected result: **"No data
collected" and "No data shared."**

- [ ] **Does your app collect or share any of the required user data types?** →
  **No.**
- [ ] **Is all user data encrypted in transit?** → N/A (no data collected). If the
  form forces an answer, note that all network calls the app makes are HTTPS.
- [ ] **Do you provide a way for users to request data deletion?** → N/A (nothing
  is collected; all data is local and user-controlled via backup/restore and
  in-app delete).
- Rationale to keep on file (same as Apple): local-first, no analytics, no ads, no
  accounts; network use is user-initiated imports + an opt-in update check, which
  do not send personal user data to the developer.
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
| **Unrestricted web access / embedded browser** | **No** — the app only fetches specific import URLs the user explicitly provides (or a chosen source's endpoint), over HTTPS, and does not render arbitrary web pages; it is **not** a general web browser. Requests pass an SSRF guard that requires HTTPS and blocks localhost/LAN/reserved addresses. The Caller's Box and ContraDB import sources are further restricted to a fixed host allowlist (`thecallersbox.com`/`ibiblio.org` for Caller's Box; `contradb.com`/`www.contradb.com` for ContraDB — #621, #667); only the generic Caller's-Compendium-JSON-file import source still accepts any public DNS host the user supplies, by design, to support a user's own self-hosted JSON export |
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
  contacts, or photos). The only permission is INTERNET, used solely for
  user-initiated imports and an opt-in (off by default) update check.
- To exercise the one network feature: open Import and paste a ContraDB program
  URL (e.g. https://contradb.com/programs/1) or a Caller's Box dance id, then
  review and commit. Nothing is uploaded — imports only fetch.
- No data is collected or transmitted to us; the app has no telemetry.
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
