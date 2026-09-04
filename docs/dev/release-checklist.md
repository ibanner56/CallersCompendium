# Beta Release Checklist — Caller's Compendium

Use one copy of this per beta tag (e.g. v0.1.0-beta). Check every box or
explicitly mark N/A with a reason. "Gate" = must pass before tagging.

> **First time submitting to the App Store or Google Play?** This checklist is per
> *tag/build*. The one-time **store-submission** work (accounts, TestFlight
> external beta, Play testing tracks, listings, privacy/data forms) is in
> [`store-submission/`](store-submission/README.md).

## 0. Pre-flight
- [ ] main is green: your target commit's CI passed — Format/analyze/test and the
 5-platform Build matrix (android/ios/linux/macos/windows). (The **Schema
 migration gate** is `pull_request`-only — `ci.yml` runs it with
 `if: github.event_name == 'pull_request'` — so it shows on the merged PR, not
 on the main commit itself.)
- [ ] No open PR is intended for this beta but still unmerged (or consciously cut).
- [ ] Working tree clean; you are on `main` at the exact commit you intend to tag.

## 1. Version & metadata (Gate)
- [ ] Inputs are decided and recorded: beta status and valid no-leading-zero
 `X.Y.Z`. The only tags are `vX.Y.Z-beta` and `vX.Y.Z`; the selected tag
 determines channel and prerelease status.
- [ ] `app/pubspec.yaml` and `kAppVersion` are both exactly `X.Y.Z`, with no
 build metadata or prerelease suffix. The workflow rejects any other pubspec
 format or a tag whose core differs. (The repo-root `pubspec.yaml` is the
 workspace file and has **no** `version:`.)
- [ ] Every explicit build-version literal in `.github/ISSUE_TEMPLATE/*.yml` and
 `*.yaml` is the same bare `X.Y.Z` as `app/pubspec.yaml`. GitHub issue forms
 are static and cannot read the latest tag dynamically; `check_app_version.py`
 rejects a stale, tag-prefixed, or suffixed literal.
- [ ] Each `X.Y.Z` component is in `0..999`. The workflow derives Android's
 `versionCode` from the tag, with beta lower than stable for the same core; no
 manually maintained store-build suffix exists.
- [ ] The updater uses strict SemVer unchanged: `X.Y.Z-beta` ranks above older
 cores/betas and below `X.Y.Z`; release builds pass that tag-derived value to
 the updater while pubspec stays bare. Do not introduce a custom comparison
 rule.
- [ ] A bare beta core has no pre-existing non-identical prerelease tag. For
 example, after `v0.1.0-beta.1` through `.9`, `v0.1.0-beta` would sort older
 and the workflow rejects it; choose a newer `X.Y.Z` core.
- [ ] Version string is consistent everywhere it appears (about screen, update
 manifest, any hardcoded constant).
- [ ] `kCompendiumSchemaVersion` matches the schema actually shipped; if it moved
 since the last tag, a migration + migration test exists for every step.
 (Reminder: never bump schema in a patch release.)
- [ ] If `kCompendiumSchemaVersion` or `contraTaxonomyVersion` moved since the
 versioned CHANGELOG section was last written, that section has a **Data /
 Migrations** entry stating old → new and what the migration does. Each moved
 constant needs its own labelled range (`schema … 20 → 25`,
 `taxonomy … 23 → 27`); the gate checks them separately.
- [ ] Exactly one `## [x.y.z]` heading for the release's core version
 (`grep -c '^## \[0\.1\.0\]' app/CHANGELOG.md` → `1`). Promotion merges into the
 existing section; a second heading renders fine and orphans the older one.
- [ ] The required shared `## [X.Y.Z]` section exists for **both** beta and stable.
 The beta establishes it from `Unreleased`; beta-to-stable fixes are added to
 that same section.
- [ ] `app/CHANGELOG.md`'s `## [Unreleased]` covers every user-visible outcome,
 including an outcome caused by a `packages/compendium_core` change. The core
 CHANGELOG records the core package version; it does **not** feed published
 release notes and never substitutes for the app entry.
- [ ] `packages/compendium_core/CHANGELOG.md`'s `## [Unreleased]` has been read,
 and the outcome recorded either way. **Empty → the core pubspec and core
 CHANGELOG are untouched by this release** (mark this row N/A with that
 reason). Non-empty → the rows below apply. The section as written is the
 trigger; do not substitute a diff of `packages/compendium_core` or a judgement
 call.
- [ ] If it was non-empty: the new core version came from **asking the
 maintainer**, with the current `packages/compendium_core/pubspec.yaml`
 `version:` presented for context. It is not derived from the tag, from the app
 version, or from the shape of the changes.
- [ ] If it was non-empty: `packages/compendium_core/pubspec.yaml` `version:` is
 that exact bare `X.Y.Z` — no `v`, no prerelease suffix, no build metadata —
 and a new `## [X.Y.Z] - YYYY-MM-DD` section dated the release date holds the
 drained entries, with a fresh empty `## [Unreleased]` above it. Unlike the
 app's shared section, a core section is **always new**: the core version is
 not the tag's core, so a beta and a later stable that both carry core changes
 get two sections.
- [ ] Both CHANGELOGs pass the structure gate — version sections strictly
 descending by SemVer precedence and
 no repeated `###` subheading inside one `##` section:

 ```sh
 python3 tools/ci/check_changelog_structure.py
 ```

## 2. Data safety (Gate — local-first app, user data is sacred)
- [ ] Every schema migration since the last release has a v(N-1)→vN migration test
 proving: new tables/columns exist, user_version tracks, pre-existing user
 data survives (no silent loss/backfill surprises).
- [ ] Import/undo round-trips verified for each supported source (JSON, Caller's
 Box, ContraDB, CC .USR): import → undo restores prior state losslessly.
- [ ] Fresh-install path works (DB created at current schema, no migration).

## 3. Build & signing (Gate)
- [ ] Android release build is SIGNED — on the **actual tag push**, or an explicit
 existing-tag recovery after the tag workflow failed, confirm the signing steps
 (Reconstruct signing config → Build signed APK → Package signed APK) succeeded
 for that immutable tag, not a prior run and not a build-only
 `workflow_dispatch`. (Without the secrets the Android leg is a no-op — it emits
 `::notice::…skipping Android release artifact` and stages no APK.)
- [ ] Desktop artifacts build for the platforms you're shipping. **macOS** is
 Developer ID-signed + notarized when the `APPLE_*` secrets are configured (the
 sign/notarize/staple + `codesign`/`spctl` verify steps ran on **that tag's**
 release run); without the secrets the macOS leg is a clean UNSIGNED build.
 **Windows is signed via Azure Trusted Signing when its five `AZURE_*` repository variables
 are configured; otherwise it remains UNSIGNED. Linux remains UNSIGNED** —
 confirm the actual tag run's Windows signing and installer-signing steps, and
 note any expected SmartScreen warning for an unsigned fallback.
- [ ] iOS build is SIGNED + uploaded to TestFlight — on the **actual tag push**
 (which exports the App Store `.ipa` with manual signing and runs
 `xcrun altool --upload-app` when the App Store Connect API key, Apple
 Distribution certificate, and both provisioning-profile secret sets are
 configured), confirm the `release-publication` protected environment was approved
 and the
 `Prepare iOS signing` → `Build signed iOS .ipa` → `Upload iOS build to
 TestFlight` steps succeeded on **that tag's** release run — **not** a
 `workflow_dispatch` (which builds+signs but never uploads). Then confirm the
 build appears in **App Store Connect → TestFlight** and reaches internal testers.
 An existing-tag recovery deliberately skips the entire iOS leg; use the original
 tag run's successful upload as this evidence rather than sending a duplicate.
 (Without all eight secrets the iOS leg is a clean skip; the API key needs the
 **App Manager** role or the upload fails.)
- [ ] iOS **export compliance** needs no per-build action — `Info.plist` declares
 `ITSAppUsesNonExemptEncryption = false` (app uses only exempt encryption), so
 App Store Connect skips the "Missing Compliance" prompt automatically.
- [ ] Each platform artifact launches and opens the collection on a clean machine
 — for **iOS**, install the TestFlight build on an **iPhone and an iPad**.

## 4. Update/distribution infrastructure
- [ ] GitHub Pages (gh-pages) is enabled and serving the update manifest at the
 expected URL.
- [ ] The update manifest points at the artifacts this tag will publish
 (URLs + versions + checksums line up).
- [ ] **Update manifests are signed (Gate).** `UPDATE_SIGNING_KEY` (Ed25519
 private-key PEM) MUST be provisioned; its absence fails publication. Confirm
 `Sign refreshed manifests` ran and each published manifest has its matching
 current `.sig` — no changed manifest may retain a stale signature. A stable
 refreshes signed `stable.json` **and** `beta.json`; a beta refreshes signed
 `beta.json` only. Then verify a real client accepts the signed update
 end-to-end. See
 [releasing.md → Signing the update manifest](releasing.md#signing-the-update-manifest-ed25519-issue-431).
- [ ] **`pages-sig-gate` is green (Gate — issues #759, #810).**
 The post-publish `Assert gh-pages signature invariant` step in the `pages` job
 reports this synchronously — a red step means the published `<channel>.json.sig` is
 missing **or does not verify** against the pinned key (`kUpdateManifestPublicKey`);
 either failure causes the updater to silently report "no update" to all users on this
 channel. A stale signature from a previous release alongside an updated manifest also
 fails (issue #810). The `gh-pages signature gate` workflow also runs daily (≤24h
 detection window for out-of-band changes); confirm no pending failures at
 **Actions → gh-pages signature gate**.
- [ ] In-app update check resolves against the manifest (or is knowingly disabled
 for beta — record which).
- [ ] **Landing page aligned:** the `site/` editorial copy (status list, feature
 cards, screenshots) reflects what this release ships — version strings are NOT
 editorial and need no bump; leave `site/index.html` alone unless the copy
 actually changed (editing it triggers the full build matrix) — see
 [releasing.md → Keeping the landing page aligned](releasing.md#keeping-the-landing-page-aligned).
 (Downloads self-update from `beta.json`; only the editorial copy needs a look.)
 After publishing, confirm <https://ibanner56.github.io/CallersCompendium/> shows
 the new version — `pages-site.yml` redeploys on merge to `main`, or run
 `gh workflow run pages-site.yml`.

## 5. Licensing & attribution (Gate — AGPL-3.0)
- [ ] LICENSE present and unchanged (AGPL-3.0).
- [ ] Source-offer / repo link is reachable from the app (AGPL network clause).
- [ ] Third-party/source attributions (ContraDB, The Caller's Box, Caller's
 Companion) are present where required; no bundled data violates its terms.

## 6. Smoke test (do on a real build of the tagged commit)
- [ ] Create/edit/delete a Dance; soft-delete + restore.
- [ ] Create/edit/duplicate/soft-delete a Program; Recently Deleted restore/purge.
- [ ] Run one import per source; confirm result dialog counts + undo.
- [ ] Search/filter with a non-default dialect; confirm enrichment resolves.
- [ ] Navigate Collection ⇄ Programs; Settings reachable.

## 7. Accessibility (Gate — prospective, see note)
> **Prospective gate.** This section is first enforced for the release tagged
> **after** it merges to `main`; it does not retroactively block whatever
> build is already in progress when it lands. From that point on, every
> release must pass the three checks below before tagging. This is a scoped,
> release-blocking subset of the full baseline in
> [`accessibility-baseline.md`](../research/accessibility-baseline.md) — see
> that doc's "Release-blocking subset vs. full baseline" section for the
> rationale and what's deliberately excluded.

- [ ] **Screen-reader smoke (iOS/VoiceOver + Android/TalkBack) — Gate.** On a
 **real iOS device** with VoiceOver enabled (the iOS Simulator does not give a
 real VoiceOver experience — do not substitute it) and on Android (a real
 device or an emulator with TalkBack enabled is fine there), using only the
 screen reader (no sighted mouse/tap shortcuts), complete on **both**
 platforms: browse/search the Collection, open a Dance's detail/card, build
 or edit a Program, and enter Performance mode for one dance. **Pass**: every
 control the flow touches is reachable in a sensible order, has an
 announced name/role/state (no "button, button" or unlabeled-image style
 gaps), and no step is stuck in a trap or silently fails to announce a
 result (e.g. search count, save confirmation).
- [ ] **Text-scaling / reflow — Gate.** Set the platform's largest supported
 text-scaling setting and repeat: Collection list, Dance detail/card, Program
 builder, Settings. On **Android**, set font scale to **2.0×**; on **iOS**,
 set Dynamic Type to its **largest accessibility size**. **Pass**: no text is
 clipped, truncated without a way to reveal the rest, or overlapping other
 content; layouts reflow instead of overflowing off-screen.
- [ ] **Keyboard-only navigation (desktop) — Gate.** On a desktop build
 (macOS/Linux/Windows), unplug/ignore the mouse and complete the same core
 flows using Tab/Shift+Tab/Enter/Arrow keys only. **Pass**: every interactive
 element is reachable via Tab order, has a visible focus indicator at every
 step, no keyboard trap exists, and fast dance entry (roadmap power-user
 flow) is possible without the mouse.
- [ ] **Deferred (advisory, not gating).** NVDA, Narrator, and Orca full
 screen-reader passes remain tracked as aspirational in
 [`accessibility-baseline.md`](../research/accessibility-baseline.md) but are
 **not** part of this release-blocking gate yet; note any known issues found
 informally in the known-issues list (§9) rather than blocking on them.

## 8. Device Sync operational readiness (W16 - Gate)
- [ ] The compatible Athenaeum server was deployed and smoke-tested before any
  beta or public client distribution. Record the image digest and deployment
  timestamp.
- [ ] Follow [`athenaeum-operations.md`](athenaeum-operations.md) and attach
  evidence for the no-redirect plaintext `:80 /v1` refusal, successful HTTPS
  request with HSTS, proxy header/body/address checks, and every documented
  rate-limit budget. Include the labeled output from
  `server/deploy/smoke_test.sh`, which runs these checks through the
  host-network Apache vhost.
- [ ] Attach live staging evidence for quota and sweep alerts reaching a human,
  30-day retention removal with log-content absence, one authorized break-glass
  access with exactly one separate audit row, and the lost-ID "not recoverable"
  support response.

## 9. Tag & publish
- [ ] Release notes drafted (see the [first-beta](release-notes-first-beta.md) / [recurring &amp; stable](release-notes-recurring.md) guide) and reviewed.
- [ ] Annotated tag created on the exact reviewed commit: `vX.Y.Z-beta` or
  `vX.Y.Z`.
- [ ] GitHub Release created from the tag, marked "Pre-release", artifacts attached.
- [ ] Post-publish: download each artifact FROM the release and re-launch once
 (catches broken uploads).

## 10. Post-release
- [ ] Roadmap updated (what shipped, what's still open).
- [ ] Known-issues list published with the release.
- [ ] Feedback channel for testers is stated in the release notes.
