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

Non-goals for v1: cloud sync, user accounts, choreography validation (developed
separately; planned for a later milestone), authoring/publishing back to online sources.

## Completed phases

Phases 0–5 and the settings work are done; their item-by-item record — with the
implementation notes and deviations against each item — is in
[ROADMAP-archive.md](ROADMAP-archive.md). What follows is the open work.

## Phase 6 — Imports & migration

- [x] 6.1 Source adapter framework + provenance tracking — pure-Dart import pipeline in `packages/compendium_core/lib/src/imports/`: `SourceAdapter` (discover/fetch/parse), `RawRecord` (verbatim payload → provenance), `StructuredDraft`+`ParseQuality` (structured-vs-custom score; parse-never-fails custom fallback), structured `ImportError`s with source context + partial-batch tolerance, dedupe primitives (exact `(source, externalId)` re-import + fuzzy title/author → link/duplicate/skip), and `ImportPipeline` (transactional commit writing provenance) with a session-scoped in-memory undo log (`ImportSession`; no schema bump — provenance persists via the existing v9 table, `DanceRepository.hardDelete` supports undo). Exercised end-to-end by an in-memory fake adapter (test-only). Real source adapters remain 6.2–6.6; review-queue UI is 6.3.
  - **Author resolve-or-create seam delivered** (proposed sub-note — not ticking any box): fulfils the "author linking left to the pipeline; no ids fabricated" promise made across 6.2–6.5. Adapters now carry raw author/choreographer names on `StructuredDraft.authorNames`; `ImportPipeline.commit` resolves each name to a `Choreographer` (`Dance.authorIds`) — exact normalized match (trim/collapse-ws/lowercase, punctuation significant, **no fuzzy**), else create a name-only row; blank names skipped, batch-de-duped to one row per new author, seeded Traditional/Unknown reused. Undo removes only choreographers this batch created and only when unreferenced (repo referenced-guard respected). **Behavior change:** author names are no longer folded into `callingNotes` and the `*_unresolved` info issues are gone; per-name resolution (matched vs created) is surfaced on `CommittedRecord.authorResolutions`. Re-import replaces the resolved author list. See design/imports.md §"Author resolution".
- [ ] ~~6.2 CallersBox sanitization pipeline (separate tool) + hosted snapshot~~ — **Cut**: superseded by direct in-app import from the primary source; we will not ingest a full snapshot or host it for download
- [ ] ~~6.3 CallersBox snapshot import in-app~~ — **Cut**: folded into direct import (no hosted snapshot to consume)
  - Adapter-agnostic import review-queue UI delivered (`app/lib/src/screens/import_review_screen.dart`): source input (.json file / paste) → non-destructive plan → review queue (parse-quality, issues, new/reimport/ambiguous actions; ambiguous defaults to skip) → commit → result summary → undo, with a live Collection refresh. Reached from Settings › General; currently wired to `GenericJsonAdapter`. The CallersBox-specific in-app import shipped via direct link import (see below); the hosted-snapshot path is cut.
  - **Core `CallersBoxAdapter` delivered** (pure-Dart CORE `SourceAdapter`, `ProvenanceSource.callersbox`): parses The Caller's Box **per-dance JSON** (`dance.php?id=N&format=JSON`) through the standard pipeline (discover → fetch → parse). Core stays I/O-free — it parses a payload string; the app URL-fetch + wiring lands in a follow-up PR (so no line ticks and CallersBox import is not yet user-reachable). `Name`→title, `FormationBase`/`FormationDetail`→`FormationShape` best-effort (original kept as detail), `Progression`/`PhraseStructure` best-effort, `CallingNotes`/`OtherNames`/`Appearances`/`Music`→callingNotes, `Tunes`→tunes, `Authors[]`→callingNotes + one info issue each (author linking left to the pipeline; no ids fabricated). **Headline: gendered-term dialect scrubbing** — each `(beats) text` figure line is beats-parsed and routed through the CORE `canonicalizeText(…, Dialect.canonical)` chokepoint (gents/ladies/larks/robins/ladles/gentlespoons → `role1`/`role2` tokens), with a `gypsy`→`shoulder round` legacy-move safety net; the canonicalized text is stored (storage is dialect-agnostic). **Permission tiers honored exactly**: `full` imports figures; `search`/blank/omitted → metadata-only stub with a warning issue (figures never fabricated). Figures import as **custom** (dialect-scrubbed text + beats); free-text `(beats) text` → structured-move grammar parsing is **deferred to a follow-up** (same scope call as ContraDB 6.4 / CC 6.5). Validated against synthetic fixtures + the real id=1 example ("The Nice Combination").
  - **User-facing CallersBox-by-link import wired** (`import_review_screen.dart` + `import_io.dart`): the import screen now offers an explicit source selector; picking "The Caller's Box" resolves a pasted dance URL (`…/dance.php?id=N`) or a bare numeric id to the `&format=JSON` endpoint (`buildCallersBoxJsonUrl`, app-layer), fetches it via the existing `UrlFetcher` seam (single user-initiated fetch — no crawl), and parses it with the core `CallersBoxAdapter` through the same plan → review → commit → undo pipeline; the resolved endpoint is stashed on `ImportRequest.uri` for provenance. Core stays I/O-free. *(6.2/6.3 cut: direct link import is the shipped path; there is no hosted snapshot to consume.)*
  - **Free-text figures now structure where recognized** (shared-parser phase): CallersBox figure lines route through the new core `parseFigureLine` (`imports/figure_parser.dart`), which conservatively upgrades recognized moves (swing/balance/circle/star/chain/allemande/do-si-do/shoulder-round/…) into structured taxonomy figures and degrades everything else to the same dialect-scrubbed `custom` figure as before (parse-never-fails; source beats preserved). Section labels are no longer prefixed onto the figure text (they derive from cumulative beats via the domain model, and beats are already a structured field — the old `'$label: $scrubbed'` prefix duplicated structured data), so custom figures now store clean scrubbed text. The previously-deferred `(beats) text` → taxonomy structuring for CallersBox is delivered here.
  - **Pasted title-list import delivered (#823).** The Collection import pane gains a fifth source, **"a list of titles"** — the first whose input is pasted text rather than a file or URL, and the only one that plans without a `SourceAdapter`. `resolveTitleList` (`app/lib/src/data/title_list_import.dart`) reuses the program importer's local-match stage (`parsePlaintextProgram`) verbatim and its online stage via the newly-extracted, non-committing `lookupUniqueExactTitle`, then **skips** `buildProgramSlots` — the only program-coupled stage — so the dances land in the Collection with no program created. Deliberately does **not** reuse `resolveUnmatchedOnline` wholesale: that commits as it goes (correct for a program line, which has no user to adjudicate it), which would leave nothing to review. Instead every resolved title becomes an `ImportRecordPlan` for `ImportReviewScreen`, so the batch is confirmed once and an `ambiguous` verdict still defaults to skip — sidestepping #685's non-interactive amplifier rather than widening it. **Every** pasted title appears in the review grouped by outcome (to import / already in your collection, named with the matched dance's choreographer / not found, with which way it missed), and a list with nothing importable shows that answer instead of dead-ending on "no dances found". Untrusted-paste bounds: 65,536 UTF-16 code units of raw text (a length cap, not a byte cap — the same count is roughly three times as many bytes for Japanese or Chinese titles), 100 **distinct** titles refused before any request (never silently truncated), 200 characters per line, case-insensitive de-duplication, per-title error isolation, and serial, cancellable lookups with progress. `OnlineSearchService.loadPreview` gains an optional shared `DedupeIndex` so an N-title batch plans against one snapshot instead of 2N full collection loads. **Behavior change:** dropdown order and default selection are now separate concerns (`ImportSource.preselected`), so the source list leads with the title list while **The Caller's Box** is what the screen opens on — previously the generic-JSON source was both first and the default.
- [x] 6.4 ContraDB import
  - `ContraDbAdapter` (pure-Dart CORE `SourceAdapter`, `ProvenanceSource.contradb`) imports ContraDB JSON **per dance** through the standard pipeline (discover → fetch → parse → dedupe → commit). ContraDB's `figures_json` move/parameter model maps move-for-move onto our taxonomy via a **positional→named** conversion table per move (~45 moves), with the gyre → `shoulder_round` term migration and the see saw / swat the flea / meltdown swing aliases. Parse-never-fails: unmapped moves, the ContraDB `custom` move, and unconvertible params fall back to `customFigure` / taxonomy defaults with non-fatal `ImportIssue`s. `start_type` free text is classified to a `FormationShape` best-effort (original kept as detail); `hook` → hook, `preamble`/`notes`/choreographer name → callingNotes (author linking left to the pipeline). **Validated against SYNTHETIC fixtures only** — ContraDB is a grey-code site with no committed real export, so the input shape and per-move positional orders are assumed from the documented `defineFigure` model; revisit with a real dump when available. This `figures_json` path remains **web-unobtainable** (ContraDB serves no JSON: `dances/N.json` → HTTP 406, no public API), so it is reachable only from a self-hosted instance, a DB dump, or the AGPL seed data — the user-facing import (below) uses the HTML page instead.
  - **User-facing ContraDB-by-link import delivered (HTML scrape).** Delivered via HTML scrape of `contradb.com/dances/N` (`ContraDbHtmlAdapter`, pure-Dart CORE `SourceAdapter`, `ProvenanceSource.contradb`): since the `figures_json` path above is web-unobtainable (406 / no API), the user-facing import parses the **server-rendered dance page** — the page a normal website visitor gets — into a `StructuredDraft` (`html` package added to core; still Flutter-free per ADR-001). It reads `h1.dance-show-title`→title, `p.dance-show-formation`→`FormationShape` best-effort (original kept as detail; unknown→other+warning), `p.dance-show-choreographer`→callingNotes + one info issue (`authorIds` left empty; no ids fabricated), and walks `table.contra-table-nonfluid` rows as (section-label, beats, free-text) tuples — carrying the last non-empty section label forward onto continuation rows and capturing `<u>`/`⁋` progression markers via the figure progression flag. Figure text shares the **CallersBox/CC free-text path**: `gypsy`→`shoulder round` safety net + the CORE `canonicalizeText(…, Dialect.canonical)` chokepoint (gendered role terms → `role1`/`role2`), stored with the section label preserved as a prefix (`'$label: $scrubbed'`). Parse-never-fails: malformed/missing elements → non-fatal `ImportIssue`s; a page with no figures table imports as a metadata stub with a warning. Core stays I/O-free — the app fetches. **App wiring:** `import_io.dart` gains `buildContraDbUrl` (bare id or pasted `…/dances/N` URL → canonical `https://contradb.com/dances/N`; user-info dropped), and Settings › Import offers a third **"ContraDB"** source (single user-initiated fetch via the existing `UrlFetcher`, no crawl; resolved URL stashed on `ImportRequest.uri`). Validated against synthetic HTML fixtures modeled on the real `dances/1` DOM **and** the live `contradb.com/dances/1` page (1 dance, 7 figures with correct beats + progression flags, `improper` formation, "Dan Pearl" folded into notes). **Honest scope note:** figures still import as **custom** (scrubbed text + beats + progression flag) — the shared free-text → structured-move taxonomy parser (common to ContraDB / CallersBox / CC 6.5) is now scoped as its **own follow-up phase**, not a per-adapter task.
  - **Shared free-text parser landed (that follow-up phase).** The ContraDB-HTML figure path now routes its scrubbed `(beats, text)` tuples through the core `parseFigureLine` (`imports/figure_parser.dart`): recognized moves become structured taxonomy figures, the rest fall back to the identical `custom` figure (progression flag + source beats preserved). Section labels are no longer prefixed onto the text (they derive from beats), so custom figures store clean scrubbed text — this drops the earlier `'$label: $scrubbed'` prefix. Validated against the real `dances/1`-modeled "The Rendezvous" fixture (balance & swing, long lines, circle → structured; the "or"/multi-move lines correctly stay custom).
- [ ] 6.5 Caller's Companion migration import — map CC tables discovered in the
  schema audit: `Dance` (incl. `Level`, composed/revised dates, `Rating`,
  `UserDefined_*` → custom fields), `Set`+`SetItem` → Programs (with band/caller/
  dancerLevel, ALT flags, guest caller, timing), `Author` → Choreographers,
  `Venue` → venue entity (delivered — schema v14, Phase 4.2 entity, plus the
  CC `.USR` import mapping into it), `Term` → glossary,
  `Dance_Related` → related links (delivered).
  Free-text figures route through the shared `parseFigureLine` grammar: lines the
  parser recognizes import as STRUCTURED moves and only the remainder falls back
  to `custom` (see design/imports.md §2).
  - **Clipboard/text migration adapter delivered** (part 1 of 2):
    `CallersCompanionTextAdapter` (pure-Dart CORE `SourceAdapter`,
    `ProvenanceSource.callersCompanion`) imports **dances** from CC's "copy
    formatted dance" clipboard/text export through the standard import pipeline
    (discover → fetch → parse → dedupe → commit). CC records map into our model
    via a source-agnostic `mapCallersCompanionDance` unit (`callers_companion_
    mapping.dart`) — header fields → title/level/formation/progression/dates,
    free-text body `(beats) text` lines → `custom` figures (design §2;
    opportunistic structuring deferred until the TCB grammar parser lands),
    author names surfaced for review (no fabricated ids). No stable CC id →
    fuzzy title/author dedupe.
  - **Binary `.USR` migration adapter delivered** (part 2 of 2; box stays open —
    see caveats): the headline FileMaker-12 binary path landed in PR #204,
    reusing the `mapCallersCompanionDance` unit above.
    - Pure-Dart FileMaker-12 `.USR` binary reader (`readFmp12` + SCSU text
      decode) — block/sector chain + catalog table/field-name recovery —
      **validated against the real `CallersCompanion2.USR`** (22 tables, 40
      dances, 205 authors; byte-for-byte cross-check against the `fmptools`
      reference across five real files). Stays **Flutter-free** (pure
      `dart:typed_data`; passes the ADR-001 guard).
    - `CallersCompanionUsrAdapter` imports **dances end-to-end** through the
      existing pipeline (discover → fetch → parse → dedupe → commit), reusing
      `mapCallersCompanionDance`; `externalId` = CC `zk_Dance_ID`; `Rating` →
      `Dance.rating`, `UserDefined_*` → calling notes.
    - **Shared free-text parser now applied to CC figures** (shared-parser
      phase): `mapCallersCompanionDance` routes every body line through the core
      `parseFigureLine`, so recognized moves structure and the rest fall back to
      `custom` (parse-never-fails; beats + section label preserved). Two
      intentional, flagged behavior changes: (1) the CC **text** adapter now
      dialect-scrubs figure text like the other adapters (it previously did not),
      and (2) recognized lines carry structured moves rather than `custom`. Still
      **not validated against real CC figure notation** (the sample `.USR`
      library has no `A1`–`B2`/`Moves` text) — real-figure validation for the
      parser is anchored to the CallersBox/ContraDB fixtures instead, per the
      phase brief.
    - `Set`/`SetItem` → `Program` **builder** (`buildCcPrograms`) delivered and
      **real-file-validated for FK linkage** — it joins on CC's own field values
      `zk_Set_ID`/`zk_Dance_ID`, not the FileMaker record ids. The **app-layer
      program persistence + undo wiring is now delivered** (#273):
      `CallersCompanionUsrImporter` commits the built programs alongside the
      dances in the same review/commit flow and rolls them back on undo, and
      **program provenance dedupe** landed (#284) so re-importing updates existing
      programs instead of duplicating them.
    - What now ships beyond dances + programs: `Author` rows resolve to
      **Choreographers** through the shared import pipeline (resolve-or-create,
      no fabricated ids — see the 6.2–6.5 author-resolution sub-note above), so
      migrated dances carry their choreographer links. `UserDefined_*` fields
      import as calling notes **by design** (not typed custom fields).
    - **Venue linking/minting delivered** (#687, PR #700): when venue-entity
      mode is ON, `.USR` program commit now resolves each set's cleaned
      `Location` text to a venue entity via the shared fingerprint path
      (`venue_dedupe.dart`), mirroring the native archive importer's
      fresh-mint-never-guess rule — unique fingerprint match → link, no
      match → mint, weak/absent or ambiguous fingerprint → fresh-mint (never
      guess). Mode OFF is unchanged (venue stays free text). A bare `.USR`
      location can't produce a strong fingerprint, so same-import duplicate
      locations are merged into a single venue via a this-commit-only
      normalized-location-text match, while cross-import reuse stays
      intentionally rare (a
      deliberate never-mis-merge tradeoff). Original `venue` text is always
      kept as a fallback label; newly minted venues are tracked as
      `insertedVenueIds` and reverted on undo; re-importing an
      already-linked program preserves `priorVenueId` and mints zero new
      venues.
    - **`Dance_Related` → `relatedDance` links delivered** (#688, PR #706):
      the real `Dance_Related` table (`zk_Dance1_ID`/`zk_Dance2_ID`/
      `zk_DanceRelatedID`/`zk_DanceRelatedID_PairID`) was confirmed against a
      real `CallersCompanion2.USR` catalog, though that sample had zero
      populated rows, so row shape is unvalidated and parsing stays
      maximally defensive (parse-never-fails: missing/renamed table →
      non-fatal warning + zero links). Links are directional only (no
      symmetrize); an endpoint that wasn't imported is skipped with a
      non-fatal `ImportIssue` rather than a dangling `targetDanceId`.
      Fail-closed caps: `maxDanceRelatedRows=20000`,
      `maxRelatedDancesPerDance=512`. Undo reverts created links.
    - The free-text figure path is now **validated against real CC figure data**
      (#559): the transcription does not live in the Dance row's `A1`–`C2`
      columns (those are empty in the real library, which is why the importer
      previously produced zero figures) but in the separate `Phrase` table.
      `extractCcUsrArchive` now joins it, and the real-file test asserts all 40
      dances in the sample `CallersCompanion2.USR` come across with a
      Phrase-joined body (162 `Phrase` rows) rather than bodyless. `InsertCall`
      call buttons also seed figure shorthands (#562), and the ingestion is
      sanitized + fail-closed bounded (#561). One source table is confirmed
      present in the real file but not yet mapped:
      - `Term` → glossary import remains **blocked** on the glossary browser,
        which is not yet built (post-GA "later" scope). **Tracked in #695.**
        It is now the only remaining unmapped CC table for 6.5.
- [x] 6.6 Generic import/export (JSON) for backup and inter-user sharing
  - Export/backup delivered under G.5 (whole-collection archive + restore/merge).
  - Inter-user-sharing **import** delivered: `GenericJsonAdapter` (pure-Dart CORE
    `SourceAdapter`, `ProvenanceSource.json`) imports our canonical
    `CompendiumArchive` JSON **per dance** through the standard import pipeline
    (discover → fetch → parse → dedupe → commit). App-side wiring / review-queue
    UI now delivered under 6.3, making JSON import user-reachable end to end.
  - **Program sharing between devices delivered** (send #339; receive #298/#361):
    a program can be shared as one self-contained `CompendiumArchive` bundle that
    carries the program *and* every dance it references, handed to the OS share
    sheet (AirDrop on Apple platforms, share intent elsewhere). The app is also a
    **share target** — opening a received bundle (AirDrop / "Open with" / share
    intent) launches the app and routes the program and its dances through the
    same **import review/consent screen** as other imports (identity-first dedupe,
    untrusted-input validation), so nothing is committed without your say-so
    (#432). Platform intake wiring:
    iOS declares `LSSupportsOpeningDocumentsInPlace` for the share-import type
    (#372); macOS routes incoming files through a native bridge (#361/#377).

## Phase 7 — Release

- [ ] 7.1 Packaging/signing for all platforms; update channel
  - Architecture — [ADR-002](adr/002-distribution-and-update-channels.md); release runbook — [releasing.md](dev/releasing.md). Box stays open: **Android release APKs are now signed** (upload keystore + four CI secrets configured, validated end-to-end on a release run), **macOS release builds are now signed with a Developer ID and notarized**, and **Windows release artifacts are signed via Azure Trusted Signing when configured**, while Linux remains unsigned. GitHub Pages is now enabled, so the per-channel update manifests are hosted and served (and a public landing page ships from `site/`); as of beta.4 the in-app update path also **verifies a signed (Ed25519) update manifest, restricts artifacts to a GitHub-owned host allowlist, and gates launch on that verification**. The **first public beta is well underway** — `v0.1.0-beta.1` (desktop + Android), `v0.1.0-beta.2`, `v0.1.0-beta.3`, `v0.1.0-beta.4`, `v0.1.0-beta.5`, and the current `v0.1.0-beta.6` are published on the [Releases page](https://github.com/ibanner56/CallersCompendium/releases); each build ships signed + notarized macOS and signed Android artifacts alongside unsigned Linux, with iPhone/iPad delivered to TestFlight testers (see the CHANGELOG, including the one-time Android reinstall note for the unified application id).
  - **Delivered**
    - Reusable CI (`_checks.yml` via `workflow_call`) with a thin `ci.yml` caller (#228).
    - Release pipeline `release.yml` (#230): a `v*` tag reuses the checks gate, then a build matrix produces a **draft** GitHub Release of **unsigned** desktop artifacts — Linux x64 (AppImage + tar.gz), macOS universal (dmg + zip), Windows x64 (installer + zip) — under deterministic `CallersCompendium-<ver>-<platform>-<arch>.<ext>` names, plus a `SHA256SUMS` manifest, keyless SLSA build-provenance + artifact attestation, and the per-channel `stable.json` / `beta.json` update manifests. Least-privilege (global `contents: read`; only the publish job elevates), canonical-repo + tag guards, SHA-pinned actions.
    - CHANGELOG-driven release notes (`tools/release/gen_release_notes.py`), channel-conditional — stable fails fast without a `## [x.y.z]` section; beta/rc degrade gracefully (#235).
    - CycloneDX SBOM per release (`tools/release/gen_sbom.py`), folded into `SHA256SUMS` and attested (#242).
    - In-app update client **Stage 1** (A11a, #245): pure-Dart manifest model + schema guard, SemVer compare, channel filter, a dedicated Settings **Updates** section (manual check + beta opt-in + auto-check; the last two default OFF), and a dismissible update banner linking the release page.
    - **Stage 1.5** assisted download (A11b, #250): desktop-only, user-initiated download → mandatory sha256 verify → OS handoff (mobile stays link-only); fails loudly on every path.
    - Update-manifest hosting (A11c, #249): the pipeline publishes each channel's manifest to a persistent `gh-pages` branch (cross-channel-preserving; [releasing.md](dev/releasing.md#publishing-the-update-manifest-github-pages)).
    - **GitHub Pages enabled + public landing page** (#408): Pages is turned on (Deploy from a branch → `gh-pages` → `/ (root)`), so the hosted update manifests are live and a dependency-free landing page ships from `site/` at https://ibanner56.github.io/CallersCompendium/ (auto-aligning download links from `beta.json`, beta-signup CTA, and user-guide links).
    - Android release signing **complete**: Gradle `release` `signingConfig` from `key.properties` in `app/android/app/build.gradle.kts` — with **no** debug fallback (a release build without `key.properties` fails loudly rather than silently debug-signing, #450) (#244) + a `release.yml` build+sign+stage universal-APK leg (#251). The upload keystore and all four `ANDROID_*` CI secrets are now configured, and a release run built + signed `CallersCompendium-<ver>-android-universal.apk` end-to-end (the JDK-21 fix in #265 keeps release lint enabled). Users can sideload the signed APK from GitHub Releases — no Play Store required.
    - iOS release signing + TestFlight leg **wired** (gated on the Apple API-key secrets, which are configured): a `release.yml` iOS leg (`macos-latest`) archives + signs an App Store `.ipa` using **automatic signing driven by an App Store Connect API key** (App Manager role — **no manual cert or provisioning profile**) and uploads it to **TestFlight** via `xcrun altool --upload-app`. The `CFBundleVersion` is a monotonic `GITHUB_RUN_NUMBER` (TestFlight rejects duplicates; `pubspec.yaml` untouched), and the upload is gated to **real `v*` tags** (a `workflow_dispatch` builds + signs for validation but never uploads). iOS is **store-delivered** — the `.ipa` is not a GitHub Release asset / `SHA256SUMS` / manifest entry. Targets **iPhone + iPad**; first channel is internal TestFlight (no Beta App Review). **Now live:** beta.2 was archived, signed, and uploaded to TestFlight, and invited testers are running the iOS/iPadOS build (bug reports have come in against `0.1.0` on iOS). See [releasing.md](dev/releasing.md#ios-testflight-via-app-store-connect-api).
    - **macOS Developer ID signing + notarization delivered** (#311, notarization wait bounded in #329): the `release.yml` macOS leg signs the universal build with an Apple Developer ID and notarizes it (gated on the configured Apple secrets), so the macOS `.dmg`/`.zip` now open without the Gatekeeper right-click workaround. Shipped in beta.2.
  - **Remaining (maintainer — one-time, $0)**
    - Document Android upload-keystore custody (owner, secure backup, rotation policy) — the key is generated and wired into CI, so this is governance, not a build blocker (see [ADR-002](adr/002-distribution-and-update-channels.md) §6). **Tracked in #692**, which also records the sideload-vs-Play App Signing distinction (the sideload signing key is unrotatable; the Play upload key is resettable) and the cross-channel key decision that must be made before the first Play publication.
  - **Deferred** (later signing wave — needs paid developer accounts / a decision; see [ADR-002](adr/002-distribution-and-update-channels.md) §6)
    - Windows Authenticode/Store (MSIX) signing — Azure Trusted Signing is wired for the Windows installer and portable bundle when configured; the Linux half is decided in ADR-003 and tracked in #491. (macOS is now signed + notarized and iOS is distributed via TestFlight — see **Delivered** above.)
    - Store distribution (Google Play, F-Droid, Flathub). **Google Play submission is now in preparation:** a release-workflow leg builds and stages a **signed Android App Bundle (`.aab`)** for Play (#535), a store-distribution **license exception** to the AGPL was added so managed marketplaces are permitted (#534), and **App Store & Google Play submission guides** plus listing copy, a privacy policy, and a contact address landed under [docs/dev/store-submission/](dev/store-submission/) (#532, #534). Actual store listing/publication is still pending. For Linux, the post-beta channel evaluation is decided in [ADR-003](adr/003-linux-native-distribution-channel.md): **Flathub-first** (auto-update + desktop integration + trusted-publisher signing, no self-run infra), with Snap/Launchpad PPA secondary and a self-hosted apt repo only on clear demand.
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
    `/guide/` Pages site render them; the bundled in-app reader intentionally
    shows their descriptive alt text instead. Guides remain complete without
    images so the offline reader is fully usable.
  - **Remaining**
    - Per-platform install page — the public landing page ([site/](../site/), #408) now surfaces per-platform downloads, and the [Installation guide](user/installation.md) covers first-launch steps; a dedicated install page is optional.
    - Beta-program page — tracked under 7.3.
- [ ] 7.3 Beta program with real callers; feedback triage
  - **Delivered**
    - Triage label taxonomy (`.github/labels.yml` + `label-sync.yml`) and structured issue forms — general feedback, import-source problem, beta check-in, a **beta signup / "Join the beta"** form (#413), plus revised bug/feature reports — with a Discussions + private-email contact config (#221).
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
    - Beta execution — recruit → run → interview → GA. Underway: builds ship for every platform (macOS signed + notarized, Android signed, Windows signed when configured, Linux unsigned; iPhone/iPad via TestFlight), the Getting Started guide is live, and invited callers are filing beta feedback against `v0.1.0-beta.x`. Remaining is the run → interview → GA arc with more real callers.

## Later milestones

- ECD and Squares support
- Optional device-to-device sync, beyond Apple-native AirDrop support.
- **Glossary / terms** (CC `Term`: term + definition + source) — a browsable
  reference of caller terminology, dialect-aware. **Tracked in #695**; today the
  app ships only the static `docs/user/glossary.md` guide (no glossary entity),
  which is why the CC `Term` mapping in 6.5 stays blocked.
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
  follow the UI language too (#529); the only surfaces still English by design are
  a small set of core service-layer messages (#528) and the diagnostics-log export
  body (a maintainer support artifact). See
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
