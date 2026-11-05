# Caller's Compendium — Roadmap

An open-source, local-first, multi-platform organizer for dance callers: maintain a
collection of dance transcriptions, build and run programs for events, and import
dances from community sources.

This document is the living plan of action. Work items are atomic and roughly
ordered; each phase gates the next. Status: `[ ]` todo · `[~]` in progress · `[x]` done.

## Guiding decisions (agreed 2026-07-10)

| Decision | Choice |
|---|---|
| Platforms | Desktop (Win/mac/Linux) + tablet + phone |
| Stack | **Flutter** — see [ADR-001](adr/001-application-stack.md) |
| Persistence | Fully offline / local-first; online sources are **import-only** |
| Dance forms | Contra first; schema designed to extend to ECD & Squares |
| Performance mode | Core to v1 (large-print calling view, program navigation) |
| Notation | Fully structured figures with a searchable free-text **Custom** figure fallback |
| CallersBox | Import directly from the primary source in-app (online search + link/record import) |
| Migration | Seamless out-of-the-box import from Caller's Companion exports |
| License | AGPL-3.0 |

Non-goals for v1: user accounts, choreography validation (developed
separately; planned for a later milestone), authoring/publishing back to online sources.

Cloud sync was a v1 non-goal and is now **designed and built** — see
[ADR-004](adr/004-device-sync-and-athenaeum.md), which specifies **Device Sync** and the
**Athenaeum** sync store. Its schema migration shipped first (v25, #901 and
#903) — deliberately early, so soft-delete columns have time to hydrate across
devices before any sync code depends on them. Three prerequisite repairs landed
next: the privacy-policy disclosures (#1115, closing #1109), the
standing-invariant ratchets (#1118, closing #1110), and shareable-text
normalisation on every write path with schema v29 (#1119, closing #1111). The
engine, the client and the Athenaeum server merged via #1328 and are reachable
from Settings ▸ Experimental; the beta and ship-gate checkpoints are still
outstanding. It keeps the properties the
original non-goal was protecting: no user accounts, no sign-in, no sync-store
content we host surviving 30 days of disuse, and no **structured** venue address
or contact field ever reaching our infrastructure. The qualifier is
load-bearing: `venues.notes` is classified `shareable` and does travel, so a
contact detail typed into a free-form note travels with the note. ADR-004
requires the app to say which fields stay local rather than promise that contact
details do not move, and this line is held to the same standard.

## Completed phases

Phases 0–6 and the settings work are done; their item-by-item record — with the
implementation notes and deviations against each item — is in
[ROADMAP-archive.md](ROADMAP-archive.md). What follows is the open work.

## Phase 7 — Release

- [ ] 7.1 Packaging/signing for all platforms; update channel
  - Architecture — [ADR-002](adr/002-distribution-and-update-channels.md); release runbook — [releasing.md](dev/releasing.md). Box stays open: **Android release APKs are now signed** (upload keystore + four CI secrets configured, validated end-to-end on a release run), **macOS release builds are now signed with a Developer ID and notarized**, and **Windows release artifacts are signed via Azure Trusted Signing when configured**, while Linux remains unsigned. GitHub Pages is now enabled, so the per-channel update manifests are hosted and served (and a public landing page ships from `site/`); as of beta.4 the in-app update path also **verifies a signed (Ed25519) update manifest, restricts artifacts to a GitHub-owned host allowlist, and gates launch on that verification**. The **open beta is live** — releases from the legacy `v0.1.0-beta.1`–`v0.1.0-beta.9` series through the current `vX.Y.Z-beta` tags are published on the [Releases page](https://github.com/ibanner56/CallersCompendium/releases); each build ships signed + notarized macOS and signed Android and Windows artifacts alongside unsigned Linux, with iPhone/iPad delivered through a TestFlight **open beta** — anyone can join via the public link, no invitation needed — (see the CHANGELOG, including the one-time Android reinstall note for the unified application id).
  - **Delivered**
    - Reusable CI (`_checks.yml` via `workflow_call`) with a thin `ci.yml` caller (#228).
    - Release pipeline `release.yml` (#230): a `v*` tag reuses the checks gate, then a build matrix produces a **draft** GitHub Release of desktop artifacts — Linux x64 (AppImage + tar.gz, unsigned), macOS universal (dmg + zip), and Windows x64 (installer + zip, signed via Azure Trusted Signing when the required repository variables and federated OIDC configuration are present, with an unsigned fallback) — under deterministic `CallersCompendium-<ver>-<platform>-<arch>.<ext>` names, plus a `SHA256SUMS` manifest, keyless SLSA build-provenance + artifact attestation, and the per-channel `stable.json` / `beta.json` update manifests. Least-privilege (global `contents: read`; the build matrix runs behind the `release-signing` approval gate with `id-token: write` for Windows' Azure OIDC signing; only the publish job gets `contents: write`), canonical-repo + tag guards, SHA-pinned actions.
    - CHANGELOG-driven release notes (`tools/release/gen_release_notes.py`): both
      stable and the permitted bare-beta tag fail fast without their shared
      `## [x.y.z]` section.
    - CycloneDX SBOM per release (`tools/release/gen_sbom.py`), folded into `SHA256SUMS` and attested (#242).
    - In-app update client **Stage 1** (A11a, #245): pure-Dart manifest model + schema guard, SemVer compare, channel filter, a dedicated Settings **Updates** section (manual check + beta opt-in + auto-check; the last two default OFF), and a dismissible update banner linking the release page.
    - **Stage 1.5** assisted download (A11b, #250): desktop-only, user-initiated download → mandatory sha256 verify → OS handoff (mobile stays link-only); fails loudly on every path.
    - Update-manifest hosting (A11c, #249): the pipeline publishes each channel's manifest to a persistent `gh-pages` branch (cross-channel-preserving; [releasing.md](dev/releasing.md#publishing-the-update-manifest-github-pages)).
    - **GitHub Pages enabled + public landing page** (#408): Pages is turned on (Deploy from a branch → `gh-pages` → `/ (root)`), so the hosted update manifests are live and a dependency-free landing page ships from `site/` at https://ibanner56.github.io/CallersCompendium/ (auto-aligning download links from `beta.json`, beta-signup CTA, and user-guide links).
    - Android release signing **complete**: Gradle `release` `signingConfig` from `key.properties` in `app/android/app/build.gradle.kts` — with **no** debug fallback (a release build without `key.properties` fails loudly rather than silently debug-signing, #450) (#244) + a `release.yml` build+sign+stage universal-APK leg (#251). The upload keystore and all four `ANDROID_*` CI secrets are now configured, and a release run built + signed `CallersCompendium-<ver>-android-universal.apk` end-to-end (the JDK-21 fix in #265 keeps release lint enabled). Users can sideload the signed APK from GitHub Releases — no Play Store required.
    - iOS release signing + TestFlight leg **wired** (gated on the App Store
      Connect API-key, Apple Distribution certificate, and provisioning-profile
      secrets): a `release.yml` iOS leg (`macos-latest`) archives unsigned, then
      manually exports a signed App Store `.ipa` and uploads it to **TestFlight**
      via `xcrun altool --upload-app`. Its `CFBundleVersion` is the bounded
      SemVer-derived code for the tag, shared with Android's `versionCode`; the
      visible `pubspec.yaml` version remains `X.Y.Z`. Upload is gated to **real
      `v*` tags** (a `workflow_dispatch` builds + signs for validation but never
      uploads). iOS is **store-delivered** — the `.ipa` is not a GitHub Release
      asset / `SHA256SUMS` / manifest entry. Targets **iPhone + iPad**; first
      channel is internal TestFlight (no Beta App Review). **Now live:** beta.2
      was archived, signed, and uploaded to TestFlight, and invited testers are
      running the iOS/iPadOS build (bug reports have come in against `0.1.0` on
      iOS). **TestFlight external testing is now live too:** it passed Beta App
      Review and iOS/iPadOS is an **open beta** — anyone can join through the
      public link (<https://testflight.apple.com/join/REgW311w>), no invitation
      needed. See
      [releasing.md](dev/releasing.md#ios-testflight-via-app-store-connect-api)
      and [store-submission/app-store.md](dev/store-submission/app-store.md#4-open-beta--testflight-external-testing--done).
    - **macOS Developer ID signing + notarization delivered** (#311, notarization wait bounded in #329): the `release.yml` macOS leg signs the universal build with an Apple Developer ID and notarizes it (gated on the configured Apple secrets), so the macOS `.dmg`/`.zip` now open without the Gatekeeper right-click workaround. Shipped in beta.2.
  - **Resolved (maintainer ops)**
    - Android signing-key custody, backup, and rotation policy — documented in the
      [release runbook](dev/releasing.md#android-signing-key-custody-backup-and-rotation)
      (#692, #1087). The cross-channel decision is made: the Play app-signing key
      is **intentionally distinct** from the direct-APK key, so moving between
      channels is a backup → uninstall → install → restore, not an in-place update.
  - **Deferred** (later signing wave — needs paid developer accounts / a decision; see [ADR-002](adr/002-distribution-and-update-channels.md) §6)
    - Windows Authenticode/Store (MSIX) signing — Azure Trusted Signing is wired for the Windows installer and portable bundle when configured; the Linux half is decided in ADR-003 and tracked in #491. (macOS is now signed + notarized and iOS is distributed via TestFlight — see **Delivered** above.)
    - Store distribution (Google Play, F-Droid, Flathub). **Google Play is in closed testing:** a release-workflow leg builds and stages a **signed Android App Bundle (`.aab`)** for Play (#535) and uploads it to Play when the Play service-account secret is configured (#1762); the closed-testing track exists and Android testers are pointed at it (#1082; [google-play.md](dev/store-submission/google-play.md#5b-closed-testing-the-mandatory-gate--gate-new-long-pole) has the tester count). A store-distribution **license exception** to the AGPL was added so managed marketplaces are permitted (#534), and **App Store & Google Play submission guides** plus listing copy, a privacy policy, and a contact address landed under [docs/dev/store-submission/](dev/store-submission/) (#532, #534). Open testing and a public store listing are still pending. For Linux, the post-beta channel evaluation is decided in [ADR-003](adr/003-linux-native-distribution-channel.md): **Flathub-first** (auto-update + desktop integration + trusted-publisher signing, no self-run infra), with Snap/Launchpad PPA secondary and a self-hosted apt repo only on clear demand.
    - Reconcile the bundle-id mismatch — **done**: all platforms now unify on the Apple form `org.callerscompendium.compendiumApp` (Android `applicationId`/namespace + Linux `APPLICATION_ID` updated to match; Apple was already the target and is the source of truth, since Apple bundle IDs disallow underscores).
- [ ] 7.2 User documentation
  - **Delivered** — the [user-guide hub](user/README.md) + [style guide](user/style-guide.md), and the guides: Getting Started, Installation, Collection & search, Write & edit dances, Programs & matrix, Perform mode, Dialect (flagship), Settings, Accessibility, Imports & migration, Share/print & export, Backup & portability, FAQ & troubleshooting, and Glossary; plus an offline **in-app User Guide** (#233). (#219/#222/#223/#224/#229/#233/#239/#240/#243)
  - **Delivered — accuracy + structure pass:** the whole guide set was re-verified against shipped behaviour and reorganised into an intent-based hub (task index, six guide groups, no status column), with two new guides (**Write & edit dances**, **Share, print & export**). The in-app reader now titles a guide from its own H1 and honours same-page `#anchor` links.
  - **Delivered — hosted docs site:** the guides are now rendered as a browsable
    section of the Pages site at
    [/guide/](https://ibanner56.github.io/CallersCompendium/guide/), so the
    landing page's guide links resolve on-site instead of bouncing readers to
    GitHub markdown. `tools/site/render_user_docs.py` pre-renders `docs/user/*.md`
    to static HTML (stdlib-only, escaped, no third-party JS/CDN) and stages it
    alongside `site/` for the existing non-destructive `gh-pages` publisher, so
    the update manifests and the guides coexist on one branch. `docs/user/` now
    feeds three consumers — GitHub, the offline in-app reader, and the web. (#694)
  - **Delivered — screenshots pass (#703):** optimized screenshots now illustrate
    the Collection, dance detail, Programs builder and matrix, Perform mode,
    Settings/Dialect, import review, and dance editor. GitHub and the hosted
    `/guide/` Pages site render them. The bundled in-app reader first showed only
    their descriptive alt text; it now bundles and renders the same PNGs
    (#1897), falling back to the alt text if one cannot load. Guides remain
    complete without images so the offline reader is fully usable.
  - **Delivered — per-platform installation:** the [Installation guide](user/installation.md) has a section per platform (Linux, macOS, Windows, Android, iPhone/iPad) covering first-launch steps, and the public landing page ([site/](../site/), #408) surfaces per-platform downloads. No separate install page or OS auto-detection is planned: readers know their own platform.
  - **Remaining**
    - Beta-program page — tracked under 7.3.
- [ ] 7.3 Beta program with real callers; feedback triage
  - **Delivered**
    - Triage label taxonomy (`.github/labels.yml` + `label-sync.yml`) and structured issue forms — general feedback, a **beta signup / "Join the beta"** form (#413), plus revised bug/feature reports — with a Discussions + private-email contact config (#221).
    - Beta docs: [beta guide](beta/beta-guide.md), [test charter](beta/test-charter.md), [triage rubric](beta/triage-rubric.md) (#227); a [beta-recruitment plan](product/beta-recruitment.md); and CONTRIBUTING/README feedback hooks.
    - **GitHub Discussions is enabled** (with categories), so the contact/community links resolve.
  - **Resolved (maintainer ops)**
    - Project contact address is **`compendium@contra.dance`**, used consistently
      across every public surface: the issue-form contact link
      (`.github/ISSUE_TEMPLATE/config.yml`), `CODE_OF_CONDUCT.md`, `SECURITY.md`,
      the [beta guide](beta/beta-guide.md), the landing page and privacy policy
      (`site/`), and the store-submission listing/privacy docs. No personal
      maintainer address remains in the repo.
  - **In progress**
    - Beta execution with real callers. Underway: builds ship for every platform (macOS signed + notarized, Android signed, Windows signed when configured, Linux unsigned; iPhone/iPad via an open TestFlight beta), the Getting Started guide is live, and beta callers are filing feedback against the current beta releases. There are no formal exit criteria: the target audience is fewer than a thousand callers, too few for a numeric bar to mean much, so the first stable release is the maintainer's call once the beta feels ready (maintainer decision given in the session that produced #1754, recorded in that PR's description). Each release, stable included, still passes the per-tag gates in the [release checklist](dev/release-checklist.md).

## Later milestones

- ECD and Squares support — the ECD figure grammar is proposed in [ADR-006](adr/006-english-country-dance-canonical-grammar.md)
- ~~Optional device-to-device sync, beyond Apple-native AirDrop support.~~ —
  **Cut**: [ADR-004](adr/004-device-sync-and-athenaeum.md) rules out local
  network discovery. Device-local data (venue addresses and contacts) moves by
  the existing JSON backup export/import, or AirDrop of that file; everything
  shareable syncs through Athenaeum instead.
- **Glossary / terms** (CC `Term`: term + definition + source) — a browsable
  reference of caller terminology, dialect-aware. **Tracked in #695** (closed as
  completed 2026-10-14).
  - **Delivered:** a read-only **Glossary** navigation destination, off by
    default behind **Settings ▸ Experimental ▸ Show glossary**, listing the
    taxonomy's built-in figures in the active dialect. Its built-in entries
    are derived from the taxonomy at runtime, so they are never stored or
    synced.
  - **Delivered:** a shipped, read-only definition and description for every
    built-in figure (`contra_figure_definitions.dart`), checked against The
    Caller's Box glossary and the glossary of Larry Jennings's *Give and Take*
    and written in the project's own words. A test requires every taxonomy
    figure to have one.
  - **Maintainer decisions** (2026-10-14, recorded in the PR that delivered
    the view): each built-in figure shows a read-only shipped definition and
    description, with a user-editable notes field; the shipped glossary does
    not sync, but any user additions (own terms, notes on figures) must.
    Own terms and the CC `Term` mapping in
    [6.5](ROADMAP-archive.md#phase-6--imports--migration) are delivered (#1023, below).
  - **Delivered (#709):** notes on built-in figures, and the user's own
    compound figures behind a nested **Custom Figures** setting — added,
    edited and deleted in the Glossary, kept in backups (maintainer decisions
    recorded in #709's consolidated spec, 2026-10-14). Own terms followed with
    #1023, which closed with #1876. All of these sync, with the Custom Figures
    setting and compound shorthands, as the `glossaryEntry` and `figureNote`
    record kinds behind the sync capability gates `glossary.v1` (compound
    figures and notes) and `glossary.v2` (own terms and own figures)
    (sync-spec §4.3, §6.15): each waits until
    every attached device runs a build that reads them, and the notice names
    the device holding them back. Clients also skip a record kind they do not
    know instead of refusing a peer's whole manifest (sync-spec §4.5).
- **User-defined quick-entry snippets** — CC's "Insert Call" buttons (per-user
  label → expansion text + beats + a gender-free alternate). **Accepted, reframed**
  over our structured model (see #401): a user shorthand maps to a fully-configured
  taxonomy *figure* (move + params) rather than expansion *text* — beats become a
  figure param and the gender-free alternate is produced by the existing dialect
  system, so there are no per-snippet text/beats/alternate fields. Tracked as #420
  (shorthand→figure mappings), which built on #419 (free-text figure entry mode)
  and #398 (parser-gap flagging); sequencing #398 → #419 → #420, **all delivered in
  beta.4**. The *structured* analogue already shipped as DD.3 (per-move figure-entry
  defaults).
- **UI localization / multi-language** — **shipped (see G.8).** The i18n stack is wired
  app-wide, UI-string extraction is complete across every screen, and the app now ships
  in **six languages** — English (source) plus **German, French, Japanese, Danish, and
  Dutch** — selectable live, with **every string translated in all five** and a CI
  ratchet enforcing that (#813). What remains here is additive: welcoming further
  **community-contributed** `app_<locale>.arb` translations (assisted tooling + a
  validation gate now support that, #523). Exported dance/program documents now
  follow the UI language too (#529), and the core-layer diagnostics the UI renders
  were localized in #573 (closing #528); the only surface still English by design
  is the diagnostics-log export body (a maintainer support artifact). See
  [docs/dev/localization.md](dev/localization.md).

### Plugin system (user-installable extensions)

A user-installable **plugins folder** that lets the community extend the app
without forking. A plugin is dropped into a known location, discovered and
loaded by the app, and enabled by the user. Plugins can add net-new
destinations to the main navigation rail or otherwise augment the app UX
(buttons, panels, renderers). Local-first and opt-in: this keeps the core lean
while giving power users and contributors a supported extension surface.

Design questions to settle before committing (deferred):

- **Extension surface / API contract** — which hooks a plugin may use: register
  a rail destination, inject actions into the dance/program views, contribute a
  renderer, and read/write collection data through a stable, sandboxed API.
- **Trust, sandboxing, and distribution** — where plugins come from, how they're
  vetted, and how much of the app/data (and network) a plugin may touch.
  Publish/export plugins that need credentials and network access raise the
  trust bar substantially.
- **Packaging + versioning** — how a plugin declares compatibility with the
  app's data model and taxonomy version so upgrades don't silently break it.

Motivating plugins (concrete asks driving the design):

- **ContraDB export / publication** — add buttons to the dance and program views
  to export/publish a dance or program up to ContraDB. This is a *write*
  integration, so it requires the user to be **logged in to their ContraDB
  account** — unlike our read-only search + import, which needs no auth.
  ContraDB today runs plain Devise session auth with **no delegated-auth
  surface** (no OAuth/OIDC provider, no token or API-key system; the only API
  is anonymous read-only). So a publish plugin would either depend on an
  **upstream ContraDB change** to add OAuth/scoped tokens (the clean path) or
  fall back to insecure credential custody (password/session handling) — which
  we would not ship without that upstream capability. Tracked here so the auth
  prerequisite is explicit.
- **Dance visualization / rendering** (from
  [dperelman](https://github.com/dperelman)) — a plugin that visualizes and
  renders dances (spatial/animated choreography views) as a net-new view,
  rather than baking it into core.
- **Choreography validation integration** - dance "compiler" that lets the user
  know whether the choreography entered progresses correctly the expected number
  of times, baked into the dance view as a warning alongside the beat counter.
