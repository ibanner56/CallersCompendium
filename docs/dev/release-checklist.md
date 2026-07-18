# Beta Release Checklist — Caller's Compendium

Use one copy of this per beta tag (e.g. v0.1.0-beta.1). Check every box or
explicitly mark N/A with a reason. "Gate" = must pass before tagging.

## 0. Pre-flight
- [ ] main is green: your target commit's CI passed — Format/analyze/test and the
 5-platform Build matrix (android/ios/linux/macos/windows). (The **Schema
 migration gate** is `pull_request`-only — `ci.yml` runs it with
 `if: github.event_name == 'pull_request'` — so it shows on the merged PR, not
 on the main commit itself.)
- [ ] No open PR is intended for this beta but still unmerged (or consciously cut).
- [ ] Working tree clean; you are on `main` at the exact commit you intend to tag.

## 1. Version & metadata (Gate)
- [ ] `app/pubspec.yaml` version bumped to the target (e.g. `0.1.0-beta.1` / build
 no.). (The repo-root `pubspec.yaml` is the workspace file and has **no**
 `version:`; the releasable version lives in `app/pubspec.yaml`.)
- [ ] Version string is consistent everywhere it appears (about screen, update
 manifest, any hardcoded constant).
- [ ] `kCompendiumSchemaVersion` matches the schema actually shipped; if it moved
 since the last tag, a migration + migration test exists for every step.
 (Reminder: never bump schema in a patch release.)

## 2. Data safety (Gate — local-first app, user data is sacred)
- [ ] Every schema migration since the last release has a v(N-1)→vN migration test
 proving: new tables/columns exist, user_version tracks, pre-existing user
 data survives (no silent loss/backfill surprises).
- [ ] Import/undo round-trips verified for each supported source (JSON, Caller's
 Box, ContraDB, CC .USR): import → undo restores prior state losslessly.
- [ ] Fresh-install path works (DB created at current schema, no migration).

## 3. Build & signing (Gate)
- [ ] Android release build is SIGNED — on the **actual tag push** (which builds the
 signed APK because the `ANDROID_*` secrets are configured), confirm the signing
 steps (Reconstruct signing config → Build signed APK → Package signed APK)
 succeeded on **that tag's** release run, not a prior run and not a build-only
 `workflow_dispatch`. (Without the secrets the Android leg is a no-op — it emits
 `::notice::…skipping Android release artifact` and stages no APK.)
- [ ] Desktop artifacts build for the platforms you're shipping. Note explicitly
 which desktop targets are UNSIGNED (currently expected) so testers aren't
 surprised by OS warnings.
- [ ] Each platform artifact launches and opens the collection on a clean machine.

## 4. Update/distribution infrastructure
- [ ] GitHub Pages (gh-pages) is enabled and serving the update manifest at the
 expected URL.
- [ ] The update manifest points at the artifacts this tag will publish
 (URLs + versions + checksums line up).
- [ ] In-app update check resolves against the manifest (or is knowingly disabled
 for beta — record which).

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

## 7. Tag & publish
- [ ] Release notes drafted (see the [first-beta](release-notes-first-beta.md) / [recurring &amp; stable](release-notes-recurring.md) guide) and reviewed.
- [ ] Annotated tag created on the exact reviewed commit: `v0.1.0-beta.1`.
- [ ] GitHub Release created from the tag, marked "Pre-release", artifacts attached.
- [ ] Post-publish: download each artifact FROM the release and re-launch once
 (catches broken uploads).

## 8. Post-release
- [ ] Roadmap updated (what shipped, what's still open).
- [ ] Known-issues list published with the release.
- [ ] Feedback channel for testers is stated in the release notes.
